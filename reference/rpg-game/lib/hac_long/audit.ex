defmodule HacLong.Audit do
  @moduledoc """
  Đối soát vàng và đồ hiếm (FEATURE_CATALOG E1), dựa trên `gold_log` / `gear_log` mà
  `HacLong.Game.Characters.save!/4` ghi cùng transaction với mỗi lần lưu nhân vật.

  Lỗi (`problems`, `mix hac_long.audit` thoát mã 1):

  - **gold_mismatch**: vàng của nhân vật khác tổng `delta` trong `gold_log` của tài khoản đó
    (vàng đổi mà không qua `Characters.save!`, hoặc ai đó sửa thẳng database).
  - **gear_duplicate**: cùng một `uid` đồ hiếm nằm ở hai chỗ (hai nhân vật, hoặc nhân vật và chợ)
    — dấu hiệu nhân đồ.
  - **gear_unlogged**: đồ hiếm đang ở nhân vật nhưng dòng `gear_log` cuối cùng của nó không phải
    `in` cho đúng tài khoản đó.

  Thống kê (không phải lỗi): vàng vào/ra theo lý do và người nhận nhiều vàng nhất trong
  `days` ngày gần đây.

  `prune/1` xóa dòng cũ hơn N ngày; vàng của các dòng bị xóa gộp thành một dòng `CARRY` cho mỗi
  tài khoản để tổng vẫn khớp.
  """

  import Ecto.Query
  alias HacLong.Repo

  @doc "Đối soát. Trả về `%{problems: [...], stats: %{...}}`."
  def run(opts \\ []) do
    days = Keyword.get(opts, :days, 1)
    problems = gold_mismatch() ++ gear_duplicate() ++ gear_unlogged()
    %{problems: problems, stats: stats(days)}
  end

  defp gold_mismatch do
    %{rows: rows} =
      Repo.query!("""
      SELECT c.user_id, c.name, c.gold, COALESCE(l.total, 0)
      FROM characters c
      LEFT JOIN (SELECT user_id, SUM(delta) AS total FROM gold_log GROUP BY user_id) l
        ON l.user_id = c.user_id
      WHERE c.gold <> COALESCE(l.total, 0)
      ORDER BY c.user_id
      """)

    for [uid, name, gold, logged] <- rows do
      %{
        kind: "gold_mismatch",
        user_id: uid,
        name: name,
        gold: gold,
        logged: to_int(logged),
        text: "#{name}: có #{gold} vàng nhưng nhật ký cộng ra #{to_int(logged)}."
      }
    end
  end

  defp gear_duplicate do
    %{rows: rows} =
      Repo.query!("""
      SELECT uid, array_agg(place ORDER BY place) FROM (
        SELECT g->>'uid' AS uid, 'nhân vật ' || c.user_id AS place
        FROM characters c, unnest(c.gear) AS g
        UNION ALL
        SELECT gear->>'uid', 'chợ ' || id FROM market_listings WHERE gear IS NOT NULL
      ) x
      GROUP BY uid HAVING count(*) > 1
      """)

    for [uid, places] <- rows do
      %{
        kind: "gear_duplicate",
        uid: uid,
        places: places,
        text: "Đồ #{uid} nằm ở #{length(places)} chỗ: #{Enum.join(places, ", ")}."
      }
    end
  end

  defp gear_unlogged do
    %{rows: rows} =
      Repo.query!("""
      SELECT c.user_id, c.name, g->>'uid', last.user_id, last.action
      FROM characters c
      CROSS JOIN unnest(c.gear) AS g
      LEFT JOIN LATERAL (
        SELECT user_id, action FROM gear_log WHERE uid = g->>'uid' ORDER BY id DESC LIMIT 1
      ) last ON true
      WHERE last.action IS DISTINCT FROM 'in' OR last.user_id <> c.user_id
      """)

    for [uid, name, gear_uid, last_uid, action] <- rows do
      %{
        kind: "gear_unlogged",
        user_id: uid,
        name: name,
        uid: gear_uid,
        text:
          "#{name} giữ #{gear_uid} nhưng nhật ký cuối là #{(action && "#{action} (tài khoản #{last_uid})") || "không có"}."
      }
    end
  end

  @doc "Vàng vào/ra theo lý do và top người nhận trong `days` ngày."
  def stats(days) do
    since = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    by_reason =
      Repo.all(
        from l in "gold_log",
          where: l.inserted_at >= ^since and l.reason not in ["BASELINE", "CARRY"],
          group_by: l.reason,
          order_by: [desc: sum(fragment("abs(?)", l.delta))],
          select: %{
            reason: l.reason,
            in: type(sum(fragment("GREATEST(?, 0)", l.delta)), :integer),
            out: type(sum(fragment("LEAST(?, 0)", l.delta)), :integer),
            n: count()
          }
      )

    top =
      Repo.all(
        from l in "gold_log",
          left_join: c in "characters",
          on: c.user_id == l.user_id,
          where:
            l.inserted_at >= ^since and l.delta > 0 and l.reason not in ["BASELINE", "CARRY"],
          group_by: [l.user_id, c.name],
          order_by: [desc: sum(l.delta)],
          limit: 10,
          select: %{user_id: l.user_id, name: c.name, gold: type(sum(l.delta), :integer)}
      )

    %{days: days, by_reason: by_reason, top: top}
  end

  @doc "Nhật ký vàng mới nhất của một tài khoản."
  def gold_history(user_id, limit \\ 50) do
    Repo.all(
      from l in "gold_log",
        where: l.user_id == ^user_id,
        order_by: [desc: l.inserted_at, desc: l.id],
        limit: ^limit,
        select: %{
          id: l.id,
          delta: l.delta,
          balance: l.balance,
          reason: l.reason,
          ref: l.ref,
          at: l.inserted_at
        }
    )
  end

  @doc """
  Xóa dòng nhật ký cũ hơn `days` ngày (mặc định 180). Vàng của các dòng bị xóa gộp thành một
  dòng `CARRY` mỗi tài khoản (ghi ở thời điểm `days` ngày trước). Trả về `%{gold: số_dòng_xóa, gear: số_dòng_xóa}`.
  """
  def prune(days \\ 180) when is_integer(days) and days > 0 do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    {:ok, result} =
      Repo.transaction(fn ->
        Repo.query!(
          """
          INSERT INTO gold_log (user_id, delta, balance, reason, inserted_at)
          SELECT user_id, SUM(delta), (array_agg(balance ORDER BY id DESC))[1], 'CARRY', $1
          FROM gold_log WHERE inserted_at < $1 GROUP BY user_id
          """,
          [cutoff]
        )

        # cả dòng CARRY của lần dọn trước (đã cộng vào dòng CARRY mới ở trên)
        {gold, _} = Repo.delete_all(from l in "gold_log", where: l.inserted_at < ^cutoff)

        # đồ hiếm: giữ dòng cuối cùng của mỗi uid (đối soát cần biết đồ đang ở đâu)
        %{num_rows: gear} =
          Repo.query!(
            """
            DELETE FROM gear_log g WHERE g.inserted_at < $1
              AND g.id <> (SELECT max(id) FROM gear_log WHERE uid = g.uid)
            """,
            [cutoff]
          )

        %{gold: gold, gear: gear}
      end)

    result
  end

  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n), do: n
end

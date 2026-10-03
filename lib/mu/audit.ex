defmodule Mu.Audit do
  @moduledoc """
  Kiểm tra chống dupe / lệch dữ liệu (P5-M3, P5-6 (2); `KB_TECHNICAL §9–§10`: serial unique, mỗi
  item đúng một chỗ, "audit log mọi chuyển owner → phát hiện dupe"; `KB_GAME_DESIGN §17`: theo dõi
  tổng cung Zen). Chỉ đọc DB — chạy bằng `mix mu.audit` (quản trị), sau soak, hoặc theo lịch.

  `run/1` trả `%{problems: [%{check, id, detail}], supply: …}`:

  - `serial_dup` — serial xuất hiện ở > 1 item (DB đã có UNIQUE; kiểm lại cho chắc);
  - `orphan` — item không có dòng `item_locations`;
  - `owner_mismatch` — chủ hiện tại (`char:<id>` cho túi / trang bị, `acc:<id>` cho kho) khác
    `to_owner` của dòng audit **chuyển chủ** gần nhất (bỏ qua dòng tiêu hao một phần như
    `USE` / `SELL` / `JEWEL_USE` một phần stack, vì item vẫn còn); `no_audit` — item không có dòng
    audit chuyển chủ nào;
  - `zen_mismatch` — Zen nhân vật ≠ tổng `delta` trong `zen_audit_log`.

  `supply`: tổng Zen đang có, và theo ngày (UTC) trong `days` ngày gần nhất: Zen sinh ra / mất đi
  theo `reason`.
  """

  alias Mu.Repo

  @doc "Chạy mọi phép kiểm."
  def run(opts \\ []) do
    problems = serial_dups() ++ orphans() ++ owners() ++ zen()
    %{problems: problems, supply: supply(Keyword.get(opts, :days, 7))}
  end

  defp rows(sql, params \\ []), do: Repo.query!(sql, params).rows

  defp serial_dups do
    for [serial, n] <-
          rows("SELECT serial, count(*) FROM items GROUP BY serial HAVING count(*) > 1"),
        do: %{check: "serial_dup", id: serial, detail: "#{n} item cùng serial"}
  end

  defp orphans do
    for [id, tid] <-
          rows("""
          SELECT i.id::text, i.template_id FROM items i
          LEFT JOIN item_locations l ON l.item_id = i.id
          WHERE l.item_id IS NULL
          """),
        do: %{check: "orphan", id: id, detail: tid}
  end

  defp owners do
    sql = """
    WITH owner_rows AS (
      SELECT DISTINCT ON (item_id) item_id, to_owner, action
      FROM item_audit_log
      WHERE to_owner LIKE 'char:%' OR to_owner LIKE 'acc:%'
      ORDER BY item_id, at DESC, id DESC
    )
    SELECT i.id::text, i.template_id,
           CASE l.location WHEN 'WAREHOUSE' THEN 'acc:' || l.account_id::text
                           ELSE 'char:' || l.character_id::text END AS expected,
           o.to_owner, o.action
    FROM items i
    JOIN item_locations l ON l.item_id = i.id
    LEFT JOIN owner_rows o ON o.item_id = i.id
    WHERE o.to_owner IS NULL
       OR o.to_owner <> CASE l.location WHEN 'WAREHOUSE' THEN 'acc:' || l.account_id::text
                                         ELSE 'char:' || l.character_id::text END
    """

    for [id, tid, expected, owner, action] <- rows(sql) do
      if owner == nil,
        do: %{
          check: "no_audit",
          id: id,
          detail: "#{tid} ở #{expected}, không có audit chuyển chủ"
        },
        else: %{
          check: "owner_mismatch",
          id: id,
          detail: "#{tid} ở #{expected}, audit cuối (#{action}) ghi #{owner}"
        }
    end
  end

  defp zen do
    sql = """
    SELECT c.id::text, c.name, c.zen, COALESCE(sum(z.delta), 0)::bigint
    FROM characters c
    LEFT JOIN zen_audit_log z ON z.character_id = c.id
    GROUP BY c.id, c.name, c.zen
    HAVING c.zen <> COALESCE(sum(z.delta), 0)
    """

    for [id, name, zen, logged] <- rows(sql),
        do: %{check: "zen_mismatch", id: id, detail: "#{name}: Zen #{zen}, tổng log #{logged}"}
  end

  defp supply(days) do
    [[total, chars]] = rows("SELECT COALESCE(sum(zen), 0)::bigint, count(*) FROM characters")

    by_day =
      for [day, reason, gained, spent] <-
            rows(
              """
              SELECT to_char(date_trunc('day', at), 'YYYY-MM-DD'), reason,
                     COALESCE(sum(delta) FILTER (WHERE delta > 0), 0)::bigint,
                     COALESCE(sum(delta) FILTER (WHERE delta < 0), 0)::bigint
              FROM zen_audit_log
              WHERE at >= now() - make_interval(days => $1)
              GROUP BY 1, 2 ORDER BY 1, 2
              """,
              [days]
            ),
          do: %{day: day, reason: reason, gained: gained, spent: spent}

    %{total: total, characters: chars, by_day: by_day}
  end
end

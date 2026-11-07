defmodule HacLong.AccountStorage do
  @moduledoc """
  Thùng đồ chung của tài khoản ở Thủ Kho (DECISIONS "Nhiều nhân vật"): mọi nhân vật của tài khoản cất / lấy chung
  đồ thường (`inv`), đồ hiếm (`gear`, kèm cấp ép `up`), vàng và số lần mở rộng. Bảng `account_storage`, một dòng mỗi
  tài khoản.

  Trong bộ nhớ, `Session` giữ bản sao ở `player.storage` (`%{inv, extra, gold, gear}`), nạp lại khi vào game và
  trước mỗi lệnh Thủ Kho; lệnh Thủ Kho đánh dấu `player.storage_dirty` và `Session` ghi bằng `write!/2` cùng
  transaction với nhân vật. Mỗi tài khoản chỉ một nhân vật online nên không ghi đè lẫn nhau.

  Đồ hiếm vào / ra thùng ghi `gear_log` với mã tài khoản, lý do `SHARED` (đối soát `HacLong.Audit`).
  """

  import Ecto.Query
  alias HacLong.Repo
  alias HacLong.Game.{Data, Gear}

  @rules Data.rules().storage

  def empty, do: %{inv: %{}, extra: 0, gold: 0, gear: []}

  @doc "Thùng đồ của tài khoản `acct` (dạng engine)."
  def get(acct) when is_integer(acct) do
    q =
      from s in "account_storage",
        where: s.account_id == ^acct,
        select: %{inv: s.inv, gear: s.gear, gold: s.gold, extra: s.extra}

    case Repo.one(q) do
      nil -> empty()
      r -> from_row(r)
    end
  end

  def get(_), do: empty()

  defp from_row(r) do
    ups = Map.new(r.gear || [], &{&1["uid"], &1["up"]})

    gear =
      for g <- Gear.load(r.gear || []) do
        case ups[g.uid] do
          n when is_integer(n) and n > 0 -> Map.put(g, :up, n)
          _ -> g
        end
      end

    %{
      inv:
        for(
          {id, n} <- r.inv || %{},
          Data.item(id),
          is_integer(n) and n > 0,
          into: %{},
          do: {id, n}
        ),
      extra: min(r.extra || 0, length(@rules.expand)),
      gold: max(0, r.gold || 0),
      gear: gear
    }
  end

  @doc """
  Ghi thùng đồ `st` của tài khoản `acct` (gọi trong transaction của `Session`). Đồ hiếm mới vào / vừa ra ghi
  `gear_log` (`in` / `out`, lý do `SHARED`).
  """
  def write!(acct, st) do
    old =
      Repo.one(
        from s in "account_storage",
          where: s.account_id == ^acct,
          select: s.gear,
          lock: "FOR UPDATE"
      ) || []

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    gear = Enum.map(st.gear, &dump/1)

    Repo.insert_all(
      "account_storage",
      [
        %{
          account_id: acct,
          inv: st.inv,
          gear: gear,
          gold: st.gold,
          extra: st.extra,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:inv, :gear, :gold, :extra, :updated_at]},
      conflict_target: :account_id
    )

    before = Map.new(old, &{&1["uid"], {&1["base"], &1["rarity"] || 0}})
    after_ = Map.new(st.gear, &{&1.uid, {&1.base, &1.rarity}})

    rows =
      for {uid, {base, rarity}} <- Map.drop(after_, Map.keys(before)) do
        %{user_id: acct, uid: uid, base: base, rarity: rarity, action: "in"}
      end ++
        for {uid, {base, rarity}} <- Map.drop(before, Map.keys(after_)) do
          %{user_id: acct, uid: uid, base: base, rarity: rarity, action: "out"}
        end

    if rows != [],
      do: Repo.insert_all("gear_log", Enum.map(rows, &Map.merge(&1, %{reason: "SHARED"})))

    :ok
  end

  @doc "Đồ hiếm trong thùng vừa thêm (so với `old`): có thì ghi nhân vật trước, thùng sau (nhật ký đúng thứ tự)."
  def added?(old, new) do
    old_ids = MapSet.new(old.gear, & &1.uid)
    Enum.any?(new.gear, &(not MapSet.member?(old_ids, &1.uid)))
  end

  # như cột `gear` của nhân vật, thêm cấp ép `up`
  defp dump(g) do
    g
    |> Map.take([:uid, :base, :rarity, :opt, :exc, :luck, :skill, :anc, :wopt, :locked])
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> then(&if(g[:up], do: Map.put(&1, "up", g.up), else: &1))
  end

  @doc """
  Chuyển Tủ Đồ kiểu cũ của nhân vật (`storage` riêng, đồ hiếm cờ `stored` trong `gear`) vào thùng chung, gộp với
  những gì đã có. Trả `{nhân_vật_đã_bỏ_tủ_riêng, thùng_mới}` hoặc nil nếu không có gì để chuyển.
  """
  def merge_legacy(p, shared) do
    legacy = Map.get(p, :storage) || %{}
    stored = Enum.filter(Gear.list(p), & &1[:stored])
    inv = legacy[:inv] || %{}
    gold = legacy[:gold] || 0
    extra = legacy[:extra] || 0

    if inv == %{} and gold == 0 and extra == 0 and stored == [] do
      nil
    else
      ups = Map.get(p, :upgrades) || %{}

      moved =
        for g <- stored do
          g = Map.delete(g, :stored)
          if ups[g.uid], do: Map.put(g, :up, ups[g.uid]), else: g
        end

      uids = Enum.map(stored, & &1.uid)

      p =
        p
        |> Map.put(:gear, Enum.reject(Gear.list(p), & &1[:stored]))
        |> Map.put(:upgrades, Map.drop(ups, uids))
        |> Map.put(:storage, nil)

      st = %{
        shared
        | inv: Map.merge(shared.inv, inv, fn _k, a, b -> a + b end),
          gold: shared.gold + gold,
          extra: max(shared.extra, extra),
          gear: shared.gear ++ moved
      }

      {p, st}
    end
  end
end

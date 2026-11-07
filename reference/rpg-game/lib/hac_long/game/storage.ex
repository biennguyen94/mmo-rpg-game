defmodule HacLong.Game.Storage do
  @moduledoc """
  Tủ Đồ (Phase 4, C7) do Thủ Kho ở Làng giữ (trước ở Nhà; DECISIONS "Bỏ Nhà: Thủ Kho ở Làng"). Hàm thuần, như
  `Engine`; lệnh chỉ chạy khi đứng cạnh Thủ Kho (`HacLong.Game.Commands`, NPC `role: "wardrobe"` trong
  `priv/maps/village.json`).

  - Đồ thường cất trong `storage.inv` (`%{id => số}`), tối đa `RULES.storage.items` loại.
  - Đồ hiếm cất vào `storage.gear` (kèm cấp ép `up`), ra khỏi `gear` / `upgrades` của nhân vật.
    Tối đa `RULES.storage.gear` món, mở rộng thêm theo `RULES.storage.expand` (trả vàng).
  - Thùng chung cả tài khoản (DECISIONS "Nhiều nhân vật", `HacLong.AccountStorage`): `player.storage` là bản sao
    `Session` nạp từ database; lệnh nào đổi thùng thì đặt `storage_dirty` để `Session` ghi lại.

  - Vàng cất trong `storage.gold` (2026-10-24): không mất khi chết / thua đồ sát, không tiêu được cho tới khi rút ra;
    tối đa `RULES.storage.gold_max` (null = không giới hạn).

  `player.storage = %{inv: %{}, extra: số_lần_mở_rộng, gold: vàng_trong_tủ, gear: [món]}`.
  """

  alias HacLong.Game.{Data, Engine, Gear}

  @rules Data.rules().storage

  def empty, do: %{inv: %{}, extra: 0, gold: 0, gear: []}

  @doc "Đọc từ database (khóa chuỗi); bỏ món không còn trong dữ liệu."
  def load(m) when is_map(m) do
    inv = m["inv"] || %{}

    %{
      inv: for({id, n} <- inv, Data.item(id), is_integer(n) and n > 0, into: %{}, do: {id, n}),
      extra: min(m["extra"] || 0, length(@rules.expand)),
      gold: max(0, if(is_integer(m["gold"]), do: m["gold"], else: 0))
    }
  end

  def load(_), do: empty()

  def get(p), do: Map.merge(empty(), Map.get(p, :storage) || %{})

  @doc "Vàng đang cất trong tủ."
  def gold(p), do: get(p).gold

  @doc "Số món đồ hiếm cất được (gốc + các lần mở rộng)."
  def gear_cap(p) do
    @rules.gear + (@rules.expand |> Enum.take(get(p).extra) |> Enum.map(& &1.gear) |> Enum.sum())
  end

  def items_cap, do: @rules.items
  def stored_gear(p), do: get(p).gear

  # thùng đổi: `Session` ghi lại (`HacLong.AccountStorage.write!/2`)
  defp put_st(p, s), do: p |> Map.put(:storage, s) |> Map.put(:storage_dirty, true)

  @doc "Lần mở rộng tiếp theo (`%{gear, gold}`) hoặc nil nếu đã mở hết."
  def next_expand(p), do: Enum.at(@rules.expand, get(p).extra)

  defp ok(msg), do: %{ok: true, msg: msg}
  defp err(msg), do: %{ok: false, msg: msg}

  @doc "Cất `n` món đồ thường `id`, hoặc món đồ hiếm `id` (uid)."
  def store(p, id, n \\ 1)

  def store(%{battle: b} = p, _id, _n) when b != nil, do: {err("Đang trong trận."), p}

  def store(p, "#" <> _ = uid, _n) do
    g = Gear.find(p, uid)

    cond do
      g == nil or g[:stored] ->
        {err("Không có món này trong túi."), p}

      Gear.equipped?(p, uid) ->
        {err("Tháo món này ra trước khi cất."), p}

      length(stored_gear(p)) >= gear_cap(p) ->
        {err("Tủ đã đầy trang bị (#{gear_cap(p)} món)."), p}

      true ->
        ups = Map.get(p, :upgrades) || %{}
        g2 = g |> Map.drop([:stored, :sell, :price])
        g2 = if ups[uid], do: Map.put(g2, :up, ups[uid]), else: g2
        s = get(p)

        p =
          p
          |> Gear.remove(uid)
          |> Map.put(:upgrades, Map.delete(ups, uid))
          |> put_st(%{s | gear: s.gear ++ [g2]})

        {ok("Đã cất #{Gear.resolve(g).name} vào tủ."), p}
    end
  end

  def store(p, id, n) do
    s = get(p)
    have = Map.get(p.inv, id, 0)

    cond do
      not (is_binary(id) and Data.item(id) && is_integer(n) and n >= 1) ->
        {err("Không cất được món này."), p}

      have < n ->
        {err("Không đủ #{Data.item(id).name} trong túi."), p}

      not Map.has_key?(s.inv, id) and map_size(s.inv) >= @rules.items ->
        {err("Tủ đã đủ #{@rules.items} loại đồ."), p}

      true ->
        inv = if have == n, do: Map.delete(p.inv, id), else: Map.put(p.inv, id, have - n)
        s = %{s | inv: Map.update(s.inv, id, n, &(&1 + n))}

        {ok("Đã cất #{Data.item(id).name} ×#{n} vào tủ."), %{p | inv: inv} |> put_st(s)}
    end
  end

  @doc "Lấy ra `n` món đồ thường `id`, hoặc món đồ hiếm `id` (uid)."
  def take(p, id, n \\ 1)

  def take(%{battle: b} = p, _id, _n) when b != nil, do: {err("Đang trong trận."), p}

  def take(p, "#" <> _ = uid, _n) do
    s = get(p)
    g = Enum.find(s.gear, &(&1.uid == uid))

    cond do
      g == nil ->
        {err("Không có món này trong tủ."), p}

      length(Gear.bag(p)) >= Gear.max_bag() ->
        {err("Túi trang bị đầy (#{Gear.max_bag()} món)."), p}

      true ->
        ups = Map.get(p, :upgrades) || %{}

        p =
          p
          |> Map.put(:gear, Gear.list(p) ++ [Map.delete(g, :up)])
          |> Map.put(:upgrades, if(g[:up], do: Map.put(ups, uid, g.up), else: ups))
          |> put_st(%{s | gear: Enum.reject(s.gear, &(&1.uid == uid))})

        {ok("Đã lấy #{Gear.resolve(g).name} ra túi."), p}
    end
  end

  def take(p, id, n) do
    s = get(p)
    have = Map.get(s.inv, id, 0)

    cond do
      not (is_binary(id) and is_integer(n) and n >= 1) or have == 0 ->
        {err("Không có món này trong tủ."), p}

      have < n ->
        {err("Trong tủ chỉ có #{have}."), p}

      true ->
        s = %{
          s
          | inv: if(have == n, do: Map.delete(s.inv, id), else: Map.put(s.inv, id, have - n))
        }

        p = p |> Engine.add_item(id, n) |> put_st(s)
        {ok("Đã lấy #{Data.item(id).name} ×#{n} ra túi."), p}
    end
  end

  @doc "Mở rộng chỗ cất đồ hiếm (trả vàng theo `RULES.storage.expand`)."
  def expand(p) do
    case next_expand(p) do
      nil ->
        {err("Tủ đã mở rộng tối đa."), p}

      %{gold: gold} when p.gold < gold ->
        {err("Cần #{gold} vàng."), p}

      %{gold: gold, gear: n} ->
        s = get(p)
        p = %{p | gold: p.gold - gold} |> put_st(%{s | extra: s.extra + 1})
        {ok("Tủ chứa thêm #{n} món trang bị (#{gear_cap(p)} món)."), p}
    end
  end

  @doc "Cất `n` vàng vào tủ (tối đa `RULES.storage.gold_max` nếu có)."
  def store_gold(%{battle: b} = p, _n) when b != nil, do: {err("Đang trong trận."), p}

  def store_gold(p, n) do
    s = get(p)
    max = @rules[:gold_max]

    cond do
      not (is_integer(n) and n >= 1) ->
        {err("Số vàng không hợp lệ."), p}

      p.gold < n ->
        {err("Chỉ có #{p.gold} vàng."), p}

      max && s.gold + n > max ->
        {err("Tủ chứa tối đa #{max} vàng."), p}

      true ->
        {ok("Đã cất #{n} vàng vào tủ."),
         %{p | gold: p.gold - n} |> put_st(%{s | gold: s.gold + n})}
    end
  end

  @doc "Rút `n` vàng từ tủ ra túi."
  def take_gold(%{battle: b} = p, _n) when b != nil, do: {err("Đang trong trận."), p}

  def take_gold(p, n) do
    s = get(p)

    cond do
      not (is_integer(n) and n >= 1) ->
        {err("Số vàng không hợp lệ."), p}

      s.gold < n ->
        {err("Tủ chỉ có #{s.gold} vàng."), p}

      true ->
        {ok("Đã rút #{n} vàng."), %{p | gold: p.gold + n} |> put_st(%{s | gold: s.gold - n})}
    end
  end

  @doc "Dữ liệu cho giao diện: `%{inv, gear: [uid], ups: %{uid => cấp ép}, cap, items_cap, next, gold}`."
  def view(p) do
    %{
      gold: gold(p),
      inv: get(p).inv,
      gear: Enum.map(stored_gear(p), & &1.uid),
      ups: for(g <- stored_gear(p), g[:up], into: %{}, do: {g.uid, g.up}),
      cap: gear_cap(p),
      items_cap: @rules.items,
      next: next_expand(p)
    }
  end
end

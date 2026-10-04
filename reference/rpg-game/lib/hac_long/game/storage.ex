defmodule HacLong.Game.Storage do
  @moduledoc """
  Tủ Đồ ở Nhà (Phase 4, C7). Hàm thuần, như `Engine`; lệnh chỉ chạy khi đứng cạnh Tủ Đồ
  (`HacLong.Game.Commands`, NPC `role: "wardrobe"` trong `priv/maps/home.json`).

  - Đồ thường cất trong `storage.inv` (`%{id => số}`), tối đa `RULES.storage.items` loại.
  - Đồ hiếm vẫn ở `gear` của nhân vật, gắn cờ `stored` (`HacLong.Game.Gear.stored?/2`): túi không
    tính, không mặc / bán / giao dịch được, nhưng nhật ký đồ hiếm và đối soát không phải đổi.
    Tối đa `RULES.storage.gear` món, mở rộng thêm theo `RULES.storage.expand` (trả vàng).

  Nhân vật lưu `storage: %{inv: %{}, extra: số_lần_mở_rộng}`.
  """

  alias HacLong.Game.{Data, Engine, Gear}

  @rules Data.rules().storage

  def empty, do: %{inv: %{}, extra: 0}

  @doc "Đọc từ database (khóa chuỗi); bỏ món không còn trong dữ liệu."
  def load(m) when is_map(m) do
    inv = m["inv"] || %{}

    %{
      inv: for({id, n} <- inv, Data.item(id), is_integer(n) and n > 0, into: %{}, do: {id, n}),
      extra: min(m["extra"] || 0, length(@rules.expand))
    }
  end

  def load(_), do: empty()

  def get(p), do: Map.get(p, :storage) || empty()

  @doc "Số món đồ hiếm cất được (gốc + các lần mở rộng)."
  def gear_cap(p) do
    @rules.gear + (@rules.expand |> Enum.take(get(p).extra) |> Enum.map(& &1.gear) |> Enum.sum())
  end

  def items_cap, do: @rules.items
  def stored_gear(p), do: Enum.filter(Gear.list(p), & &1[:stored])

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
      g == nil or g[:stored] -> {err("Không có món này trong túi."), p}
      Gear.equipped?(p, uid) -> {err("Tháo món này ra trước khi cất."), p}
      length(stored_gear(p)) >= gear_cap(p) -> {err("Tủ đã đầy đồ hiếm (#{gear_cap(p)} món)."), p}
      true -> {ok("Đã cất #{Gear.resolve(g).name} vào tủ."), Gear.put(p, uid, :stored, true)}
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

        {ok("Đã cất #{Data.item(id).name} ×#{n} vào tủ."),
         %{p | inv: inv} |> Map.put(:storage, s)}
    end
  end

  @doc "Lấy ra `n` món đồ thường `id`, hoặc món đồ hiếm `id` (uid)."
  def take(p, id, n \\ 1)

  def take(%{battle: b} = p, _id, _n) when b != nil, do: {err("Đang trong trận."), p}

  def take(p, "#" <> _ = uid, _n) do
    g = Gear.find(p, uid)

    cond do
      g == nil or not g[:stored] ->
        {err("Không có món này trong tủ."), p}

      length(Gear.bag(p)) >= Gear.max_bag() ->
        {err("Túi đồ hiếm đầy (#{Gear.max_bag()} món)."), p}

      true ->
        {ok("Đã lấy #{Gear.resolve(g).name} ra túi."), Gear.put(p, uid, :stored, nil)}
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

        p = p |> Engine.add_item(id, n) |> Map.put(:storage, s)
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
        p = %{p | gold: p.gold - gold} |> Map.put(:storage, %{s | extra: s.extra + 1})
        {ok("Tủ chứa thêm #{n} món đồ hiếm (#{gear_cap(p)} món)."), p}
    end
  end

  @doc "Dữ liệu cho giao diện: `%{inv, gear: [uid], cap, items_cap, next}`."
  def view(p) do
    %{
      inv: get(p).inv,
      gear: Enum.map(stored_gear(p), & &1.uid),
      cap: gear_cap(p),
      items_cap: @rules.items,
      next: next_expand(p)
    }
  end
end

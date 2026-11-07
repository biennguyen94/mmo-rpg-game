defmodule HacLong.Game.Trader do
  @moduledoc """
  Thương Nhân Chợ Nổi (DECISIONS "Bản đồ đẹp hơn"): mỗi ngày (giờ Việt Nam) bày `RULES.trader.show` món chọn cố định
  theo ngày trong `RULES.trader.offers`; mỗi nhân vật mua mỗi món tối đa `limit` lần / ngày, đếm ở `daily.trader`
  (`HacLong.Game.Daily` làm mới mỗi ngày). Hàm thuần: ngày truyền vào.
  """
  alias HacLong.Game.{Data, Engine}

  defp rules, do: Data.rules().trader

  @doc "Các món bày hôm `date` (chuỗi \"YYYY-MM-DD\"): giữ thứ tự trong bảng."
  def offers(date) do
    all = rules().offers
    picked = all |> Enum.sort_by(&:erlang.phash2({date, &1.id})) |> Enum.take(rules().show)
    Enum.filter(all, &(&1 in picked))
  end

  @doc "Cho client: món hôm nay, tên món, đã mua bao nhiêu lần."
  def view(p, date) do
    bought = get_in(p, [:daily, :trader]) || %{}

    for o <- offers(date) do
      it = Data.item(o.item) || %{name: o.item}

      Map.merge(o, %{
        name: it.name,
        bought: Map.get(bought, o.id) || Map.get(bought, to_string(o.id)) || 0
      })
    end
  end

  @doc "Mua món `id` (một lần = `n` món) hôm `date`."
  def buy(p, id, date) do
    o = Enum.find(offers(date), &(&1.id == id))
    bought = get_in(p, [:daily, :trader]) || %{}
    used = Map.get(bought, id) || Map.get(bought, String.to_atom(id || "_")) || 0

    cond do
      p.battle ->
        {%{ok: false, msg: "Đang trong trận đấu."}, p}

      o == nil ->
        {%{ok: false, msg: "Hôm nay không bày món này."}, p}

      used >= o.limit ->
        {%{ok: false, msg: "Hôm nay bạn đã mua đủ #{o.limit} lần món này, mai quay lại nhé."}, p}

      p.gold < o.price ->
        {%{ok: false, msg: "Không đủ vàng (cần #{o.price})."}, p}

      p[:daily] == nil ->
        {%{ok: false, msg: "Thử lại sau giây lát."}, p}

      true ->
        p = %{p | gold: p.gold - o.price} |> Engine.add_item(o.item, o.n)
        p = put_in(p, [:daily, :trader], Map.put(bought, id, used + 1))
        name = (Data.item(o.item) || %{name: o.item}).name
        {%{ok: true, msg: "Đã mua #{name}#{if o.n > 1, do: " ×#{o.n}", else: ""}."}, p}
    end
  end
end

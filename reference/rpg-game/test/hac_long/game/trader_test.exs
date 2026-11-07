defmodule HacLong.Game.TraderTest do
  # DECISIONS "Bản đồ đẹp hơn": Thương Nhân Chợ Nổi, thời tiết ảnh hưởng chỉ số
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine, Trader}
  alias HacLong.World.{Maps, Weather}

  @date "2026-11-07"

  defp player do
    {:ok, p} = Engine.new_player("Khach", "dk")
    %{p | gold: 100_000} |> Map.put(:daily, %{date: @date, tasks: [], bosses: []})
  end

  test "mỗi ngày bày `show` món, cố định theo ngày, đổi theo ngày" do
    n = Data.rules().trader.show
    assert length(Trader.offers(@date)) == n
    assert Trader.offers(@date) == Trader.offers(@date)

    days = for d <- 1..20, do: Trader.offers("2026-11-#{String.pad_leading("#{d}", 2, "0")}")
    assert days |> Enum.uniq() |> length() > 1
  end

  test "mua: trừ vàng, thêm món, đếm lần; quá giới hạn / thiếu vàng / món không bày thì không được" do
    [o | _] = Trader.offers(@date)
    p = player()
    {r, p2} = Trader.buy(p, o.id, @date)
    assert r.ok
    assert p2.gold == p.gold - o.price
    assert Map.get(p2.inv, o.item, 0) == Map.get(p.inv, o.item, 0) + o.n

    p_full = put_in(p, [:daily, :trader], %{o.id => o.limit})
    assert {%{ok: false}, _} = Trader.buy(p_full, o.id, @date)
    assert {%{ok: false}, _} = Trader.buy(%{p | gold: 0}, o.id, @date)

    hidden = Enum.find(Data.rules().trader.offers, &(&1 not in Trader.offers(@date)))
    assert {%{ok: false}, _} = Trader.buy(p, hidden.id, @date)

    v = Trader.view(p2, @date)
    assert Enum.find(v, &(&1.id == o.id)).bought == 1
  end

  test "thời tiết: kỹ năng cùng hệ được cộng, khác hệ / đòn thường / không có thời tiết thì không" do
    p = player() |> Map.put(:battle, %{wx: %{kind: "storm", element: "lightning", pct: 0.1}})
    assert Engine.weather_mult(p, %{element: "lightning"}) == 1.1
    assert Engine.weather_mult(p, %{element: "fire"}) == 1
    assert Engine.weather_mult(Map.put(p, :battle, %{wx: nil}), %{element: "lightning"}) == 1

    assert %{element: el, pct: pct} = Weather.bonus(Maps.get("forest_1"))
    assert is_binary(el) and pct > 0
    assert Weather.bonus(Maps.get("tower")) == nil
  end
end

defmodule HacLongWeb.Market15hTest do
  @moduledoc """
  Phase 15h (docs/ITEMS_PHASE15B.md §11): rao đồ lên chợ giữ đủ mọi dòng của món (trước đây chỉ lưu
  uid / base / độ hiếm / chỉ số cộng nên mất Excellent, May mắn, Kỹ năng, Bộ Thần, dòng cánh, Ngọc Sinh Mệnh).
  """
  use HacLongWeb.ChannelCase

  alias HacLong.Market
  alias HacLong.Game.{Characters, Commands, Gear}

  defp with_character(user, attrs) do
    name = "Cho #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    p = p |> Map.put(:tutorial, nil) |> Map.merge(attrs)
    Characters.save!(user.id, p)
    p
  end

  test "rao bán rồi mua: món giữ Excellent, May mắn, Kỹ năng, Ngọc Sinh Mệnh, cấp nâng" do
    seller = create_user()
    buyer = create_user()

    g =
      Gear.new("item_0_3", 2, %{str: 3})
      |> Map.merge(%{exc: ["atk_pct"], luck: true, skill: true, opt: 2})

    a = with_character(seller, %{gear: [g], upgrades: %{g.uid => 7}})
    b = with_character(buyer, %{gold: 10_000_000})

    {:ok, _, a2} = Market.list(seller.id, a, g.uid, 1, 1000, &Characters.save!(seller.id, &1))
    assert a2.gear == []

    [l] = Market.listings("", buyer.id)
    assert %{exc: ["atk_pct"], luck: true, skill: true, opt: 2, up: 7} = l.gear

    {:ok, _, b2} = Market.buy(buyer.id, b, l.id, &Characters.save!(buyer.id, &1))
    [got] = b2.gear
    assert %{exc: ["atk_pct"], luck: true, skill: true, opt: 2, bonus: %{str: 3}} = got
    assert b2.upgrades[got.uid] == 7
  end

  test "đồ Thần và cánh có dòng giữ nguyên qua chợ (rút về)" do
    seller = create_user()
    anc = Map.put(Gear.new("item_8_0", 1, %{}), :anc, true)
    wing = Map.put(Gear.plain("wing_dk_2"), :wopt, "hp")
    a = with_character(seller, %{gear: [anc, wing]})
    save = &Characters.save!(seller.id, &1)

    {:ok, _, a} = Market.list(seller.id, a, anc.uid, 1, 500, save)
    {:ok, _, a} = Market.list(seller.id, a, wing.uid, 1, 500, save)

    for l <- Market.mine(seller.id) do
      {:ok, _, back} = Market.cancel(seller.id, a, l.id, save)
      g = Enum.find(back.gear, &(&1.base == l.gear.base))
      if g.base == "item_8_0", do: assert(g.anc), else: assert(g.wopt == "hp")
    end
  end
end

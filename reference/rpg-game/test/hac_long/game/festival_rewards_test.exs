defmodule HacLong.Game.FestivalRewardsTest do
  # DECISIONS "Lễ hội: nâng phần thưởng": vàng theo cấp và số lần chuyển sinh, đổi ngọc, Túi Quà dòng từ +8
  use ExUnit.Case, async: false

  alias HacLong.Game.{Data, Engine, Events, Gear, Rng}

  @r Data.rules().events

  setup do
    old = Application.get_env(:hac_long, :event)
    Application.put_env(:hac_long, :event, "pumpkin")

    on_exit(fn ->
      Rng.clear()

      if old,
        do: Application.put_env(:hac_long, :event, old),
        else: Application.delete_env(:hac_long, :event)
    end)

    {:ok, p} = Engine.new_player("Le Hoi", "dk")
    {:ok, p: %{p | level: 50, gold: 0, inv: %{"pumpkin_candy" => 500}}}
  end

  test "vàng nhân theo số lần chuyển sinh", %{p: p} do
    base = @r.gold_base + 50 * @r.gold_per_level
    {%{ok: true}, q} = Events.exchange(p, "gold")
    assert q.gold == base
    {%{ok: true}, q} = Events.exchange(Map.put(p, :rebirths, 6), "gold")
    assert q.gold == base * (1 + 6 * @r.gold_per_rebirth)
    assert q.inv["pumpkin_candy"] == 500 - @r.shop.gold
  end

  test "đổi ngọc ép đồ đúng giá", %{p: p} do
    for j <- @r.jewels do
      {%{ok: true}, q} = Events.exchange(p, j.id)
      assert q.inv[j.id] == 1 and q.inv["pumpkin_candy"] == 500 - j.cost
    end

    poor = %{p | inv: %{"pumpkin_candy" => 1}}
    assert {%{ok: false}, _} = Events.exchange(poor, "jewel_life")
  end

  test "Túi Quà: luôn có dòng cộng thêm từ +8; có lúc ra Excellent", %{p: p} do
    for i <- 1..30 do
      Rng.put_sequence(Stream.cycle([rem(i * 37, 100) / 100]) |> Enum.take(50))
      {%{ok: true}, q} = Events.exchange(p, "gear")
      g = List.last(Gear.list(q))
      assert (g[:opt] || 0) >= 2
    end

    Rng.put_sequence(List.duplicate(0.01, 50))
    {%{ok: true}, q} = Events.exchange(p, "gear")
    assert List.last(Gear.list(q))[:exc] not in [nil, []]
  end
end

defmodule HacLong.InvasionTest do
  @moduledoc "Phase 7: Golden Invasion — lịch (đồng hồ giả), quái vàng không hồi sinh, trùm vàng, kết thúc sớm, thưởng ×5."
  use HacLong.DataCase, async: false

  alias HacLong.Invasion
  alias HacLong.Game.{Data, Engine}
  alias HacLong.World.MapServer

  @map "forest_1"

  setup do
    MapServer.clear_monsters(@map)
    on_exit(fn -> Invasion.stop_now() end)
    :ok
  end

  defp golds, do: Enum.filter(MapServer.snapshot(@map).monsters, & &1.gold)

  defp kill(m, uid) do
    {:engage, _} = MapServer.step(@map, uid, {m.x, m.y}, true)
    :ok = MapServer.defeat(@map, uid, m.id)
  end

  defp wait_status(pred, tries \\ 50) do
    st = Invasion.status()
    if pred.(st) or tries == 0, do: st, else: Process.sleep(10) && wait_status(pred, tries - 1)
  end

  test "lịch: mốc tròn mỗi 2 giờ theo giờ Việt Nam" do
    # 01:30 giờ VN (18:30 UTC hôm trước) → 02:00 giờ VN = 19:00 UTC
    assert Invasion.next_start(~U[2026-10-03 18:30:00Z]) == ~U[2026-10-03 19:00:00Z]
    # đúng mốc thì sang mốc sau
    assert Invasion.next_start(~U[2026-10-03 19:00:00Z]) == ~U[2026-10-03 21:00:00Z]
    # 23:10 giờ VN → 00:00 hôm sau giờ VN
    assert Invasion.next_start(~U[2026-10-04 16:10:00Z]) == ~U[2026-10-04 17:00:00Z]
    assert Invasion.next_start(~U[2026-10-04 16:10:00Z], 4) == ~U[2026-10-04 17:00:00Z]
  end

  test "quái vàng → hạ hết thì trùm vàng → hạ trùm thì kết thúc sớm; quái vàng không hồi sinh" do
    st = Invasion.start_now(%{@map => 2})
    assert st.active and st.maps == %{@map => "run"}
    assert [_, _] = golds()

    [a, b] = golds()
    kill(a, 1)
    assert [_] = golds()
    kill(b, 1)

    assert wait_status(&(&1.maps[@map] == "boss")).maps[@map] == "boss"
    assert [%{boss: true} = boss] = golds()
    kill(boss, 1)

    st = wait_status(&(not &1.active))
    refute st.active
    Process.sleep(50)
    assert golds() == []
  end

  test "hết giờ: quái vàng chưa ai đánh biến mất" do
    Invasion.start_now(%{@map => 3})
    assert length(golds()) == 3
    send(Invasion, :tick)
    refute wait_status(&(not &1.active)).active
    assert golds() == []
  end

  test "thưởng ×5 (sức mạnh không đổi bởi reward_mult), rơi ngọc theo jewel_chance" do
    spec = hd(Data.zone(0).monsters)
    plain = Engine.make_monster(spec, false)

    gold =
      Engine.make_monster(
        Map.merge(spec, %{reward_mult: 5, golden: true, jewel_chance: 0.1}),
        false
      )

    r = Data.rules().invasion.reward_mult
    # làm tròn một lần ở cuối nên lệch tối đa r
    assert abs(gold.xp - plain.xp * r) <= r and gold.maxHp == plain.maxHp and gold.golden
    assert gold.jewel_chance == 0.1
  end
end

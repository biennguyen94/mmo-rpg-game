defmodule HacLong.Game.BloodCastleTest do
  @moduledoc "Lâu Đài Máu (Phase 18 M2, docs/EVENTS_PHASE18.md)."
  use ExUnit.Case, async: false

  alias HacLong.Game.{BloodCastle, Chaos, Data, Engine, Gear, Tower}

  @r BloodCastle.rules()

  defp player do
    {:ok, p} = Engine.new_player("Thử", "dk")
    %{p | level: 42, gold: 200_000}
  end

  defp vn(h, m), do: DateTime.new!(~D[2026-10-10], Time.new!(h, m, 0)) |> DateTime.add(-7 * 3600)

  # vào lúc đang mở, cho lượt còn hạn so với giờ thật
  defp inside do
    {_, p} = BloodCastle.buy_ticket(player())
    {%{ok: true}, p} = BloodCastle.enter(p, vn(0, div(@r.offset_minutes, 1) + 1))
    put_in(p.tower.bc.ends_at, DateTime.to_unix(DateTime.utc_now()) + 600)
  end

  defp win(p, m) do
    b = %{over: true, result: "win", encounter: %{tower: m.id}, log: []}
    Tower.after_battle(%{p | battle: b}) |> Map.put(:battle, nil)
  end

  test "lịch: lệch offset_minutes, cho vào entry_minutes phút" do
    assert BloodCastle.open?(vn(0, @r.offset_minutes))
    refute BloodCastle.open?(vn(0, @r.offset_minutes + @r.entry_minutes))
    refute BloodCastle.open?(vn(1, @r.offset_minutes))
    assert BloodCastle.open?(vn(@r.every_hours, @r.offset_minutes + 1))
  end

  test "vào: cần cấp, vé; quân canh đúng số, cấp theo cấp người chơi" do
    {%{ok: false}, _} =
      BloodCastle.enter(%{player() | level: @r.min_level - 1}, vn(0, @r.offset_minutes))

    {%{ok: false, msg: m}, _} = BloodCastle.enter(player(), vn(0, @r.offset_minutes))
    assert m =~ "Vé"

    p = inside()
    assert p.pos.map == Tower.map_id() and p.tower.bc.stage == "guards"
    assert length(p.tower.monsters) == @r.guards

    assert Enum.all?(
             p.tower.monsters,
             &(&1.level == BloodCastle.tier_level(42) and &1.role == "guard")
           )

    refute Map.has_key?(p.inv, @r.ticket)
  end

  test "ba bước: hết quân canh → Cổng Thành (không đánh trả) → Hiệp Sĩ Máu → thắng có Lông Vũ Kền Kền" do
    p =
      Enum.reduce(inside().tower.monsters, inside(), fn _, p -> win(p, hd(p.tower.monsters)) end)

    assert p.tower.bc.stage == "gate" and p.tower.bc.killed == @r.guards
    [gate] = p.tower.monsters
    assert gate.role == "gate" and gate.name == @r.gate.name
    assert BloodCastle.battle_monster(gate).atk == 0

    # đứng trên ô cổng lúc hạ nó: trùm hiện ở ô khác (bước vào đánh được)
    p = win(Map.put(p, :pos, %{p.pos | x: gate.x, y: gate.y}), gate)
    assert p.tower.bc.stage == "boss"
    [boss] = p.tower.monsters
    assert {boss.x, boss.y} != {gate.x, gate.y}
    assert boss.role == "boss" and boss.elite

    g0 = p.gold
    p = win(p, boss)
    assert p.tower.bc.done and p.inv["condor_feather"] == 1 and p.gold > g0

    # bước đi tiếp: về Làng
    {%{ok: true}, out} = BloodCastle.leave(p)
    assert out.tower == nil and out.pos.map == "village"
  end

  test "không xong (tự ra / gục ngã): thưởng theo số quân canh đã hạ, không có lông vũ" do
    p = inside()
    p = win(p, hd(p.tower.monsters)) |> then(&win(&1, hd(&1.tower.monsters)))
    {%{ok: true, msg: m}, out} = BloodCastle.leave(p)
    assert m =~ "hạ 2 quân canh" and out.tower == nil and out.inv["condor_feather"] == nil
    assert out.gold - p.gold == BloodCastle.reward(p.tower.bc.level, 2, false).gold

    lost =
      Tower.after_battle(%{
        p
        | battle: %{over: true, result: "lose", encounter: %{tower: 1}, log: []}
      })

    assert lost.tower == nil and Enum.any?(lost.battle.log, &(&1.text =~ "Lâu Đài Máu kết thúc"))
  end

  test "cánh cấp 3 cần Lông Vũ Kền Kền" do
    r = Data.chaos("wing3")
    assert r.items["condor_feather"] == 1

    g = Gear.plain("wing_dk_2")

    p =
      %{player() | gear: [g]}
      |> Map.put(:upgrades, %{g.uid => 9})
      |> Engine.add_item("jewel_bless", 10)
      |> Engine.add_item("jewel_soul", 10)
      |> Engine.add_item("jewel_chaos", 3)
      |> Engine.add_item("jewel_life", 3)

    assert {%{ok: false, msg: m}, _} = Chaos.combine(p, "wing3", g.uid)
    assert m =~ "Lông Vũ Kền Kền"
  end

  test "bước vào quái trong Lâu Đài (World.move) mở trận Lâu Đài, không phải trận Tháp Vô Tận" do
    p = inside()
    [m | _] = p.tower.monsters
    p = Map.put(p, :pos, %{p.pos | x: m.x, y: m.y + 1})
    {%{ok: true}, q} = HacLong.World.move(p, 0, "up", true)
    assert q.battle.monster.bc == true and q.battle.encounter == %{tower: m.id}
  end
end

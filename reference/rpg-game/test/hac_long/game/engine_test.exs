defmodule HacLong.Game.EngineTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine, Rng, Simulator}

  setup do
    on_exit(&Rng.clear/0)
  end

  defp player(cls \\ "dk") do
    {:ok, p} = Engine.new_player("Thử", cls)
    p
  end

  test "chỉ số nhân vật mới" do
    p = player()
    # Kiếm Sĩ: chỉ số gốc như MU
    assert p.stats == %{str: 28, agi: 20, vit: 25, ene: 10}
    d = Engine.derived(p)
    # 40 + 1*10 + 25*10
    assert d.maxHp == 300 and p.hp == 300
    # 20 + 1*1 + 10*1
    assert d.maxMp == 31 and p.mp == 31
    # 28*2.8 + 20*0.5 + cấp 1 + gậy 3
    assert d.atk == 92
    assert Engine.points_per_level("dk") == 5 and Engine.points_per_level("mg") == 7
    assert Engine.xp_to_next(1) == 40
    assert Engine.xp_to_next(1) == 40
  end

  test "chỉ số quái tính từ cấp, trùm mạnh hơn" do
    Rng.put_sequence([0.5])
    z = Data.zone(0)
    m = Engine.make_monster(hd(z.monsters), false)
    b = Engine.make_monster(z.boss, true)
    assert m.maxHp == round((20 + 26 + 0.6) * 0.8)
    assert b.boss and b.maxHp > 10 * m.maxHp
    assert b.special.every == 3
  end

  test "chí mạng, né, sát thương theo dãy số cố định" do
    # Thứ tự gọi ngẫu nhiên mỗi lượt đánh: chí mạng?, trượt?, sát thương, rồi tới lượt quái.
    Rng.put_sequence([0.0])
    p = player()
    {%{ok: true}, p} = Engine.start_battle(p, 0, false)
    assert p.battle.monster.id == "bat"

    Rng.put_sequence([0.99])
    {%{ok: true}, p2} = Engine.act(p, "attack")
    [_, hit, _] = p2.battle.log
    assert hit.kind == "hit"
    assert p2.battle.monster.hp < p.battle.monster.hp

    Rng.put_sequence([0.0, 0.99, 0.5, 0.99])
    {_, p3} = Engine.act(p, "attack")
    assert Enum.at(p3.battle.log, 1).kind == "crit"

    # số thứ hai nhỏ hơn tỉ lệ trượt (1 − tỉ lệ trúng): đánh trượt
    Rng.put_sequence([0.99, 0.0, 0.99])
    {_, p4} = Engine.act(p, "attack")
    assert Enum.at(p4.battle.log, 1).text =~ "Trượt!"
    assert p4.battle.monster.hp == p.battle.monster.hp
  end

  test "kỹ năng có hồi chiêu" do
    Rng.put_sequence([0.5])
    p = %{player("elf") | hp: 50, level: 10}
    {_, p} = Engine.start_battle(p, 0, true)
    mp = p.mp
    {%{ok: true}, p} = Engine.act(p, "skill", "heal")
    assert Engine.cooldown(p, "heal") == 4
    # tốn 14 MP, hồi 5 % MP tối đa đầu lượt
    max_mp = Engine.derived(p).maxMp
    assert p.mp == min(max_mp, mp + round(max_mp * 0.05)) - 14
    assert Enum.any?(p.battle.log, &(&1.text =~ "Khiên Thánh hồi"))

    assert {%{ok: false, msg: "Hồi Sinh Lực hồi sau 4 lượt."}, ^p} =
             Engine.act(p, "skill", "heal")

    # hết MP thì không dùng được
    {_, q} = Engine.start_battle(%{player("elf") | mp: 0}, 0, false)
    assert {%{ok: false, msg: "Không đủ MP cho Tam Tiễn (cần 8)."}, _} = Engine.act(q, "skill")
  end

  test "kỹ năng mở theo cấp" do
    ids = fn p -> Enum.map(Engine.skills(p), & &1.id) end
    assert ids.(player()) == ["twisting_slash"]
    assert ids.(%{player() | level: 10}) == ["twisting_slash", "falling_slash"]
    assert ids.(%{player("elf") | level: 25}) == ["triple_shot", "heal", "greater_damage"]
    assert ids.(%{player("dw") | level: 25}) == ["fire_ball", "lightning", "soul_barrier"]
    assert ids.(%{player("mg") | level: 25}) == ["power_slash", "flame_strike", "gigantic_storm"]

    Rng.put_sequence([0.5])
    {_, p} = Engine.start_battle(player(), 0, false)

    assert {%{ok: false, msg: "Chưa học kỹ năng này."}, _} =
             Engine.act(p, "skill", "falling_slash")
  end

  # quái thường, không né, không chí mạng: dãy 0.99 cho mọi lần ngẫu nhiên
  defp fight(cls, level, zone \\ 0) do
    Rng.put_sequence([0.99])
    p = %{player(cls) | level: level, stats: %{str: 5, agi: 0, vit: 200, ene: 5}}
    p = %{p | hp: Engine.derived(p).maxHp}
    {_, p} = Engine.start_battle(p, zone, false)
    put_in(p.battle.monster.hp, 100_000) |> put_in([:battle, :monster, :maxHp], 100_000)
  end

  test "choáng làm quái mất lượt" do
    p = fight("dk", 10)
    hp = p.hp
    {%{ok: true}, p} = Engine.act(p, "skill", "falling_slash")
    assert Enum.any?(p.battle.log, &(&1.text =~ "bị choáng, không đánh được"))
    assert p.hp == hp
    # choáng chỉ một lượt
    {_, p} = Engine.act(p, "attack")
    assert p.hp < hp
  end

  test "tẩm độc: quái mất máu cuối mỗi lượt trong 3 lượt" do
    p = fight("mg", 10)
    {_, p} = Engine.act(p, "skill", "flame_strike")
    assert [%{id: "poison", turns: 2, power: per}] = p.battle.effects.monster
    hp = p.battle.monster.hp
    {_, p} = Engine.act(p, "attack")
    {_, p} = Engine.act(p, "attack")
    assert p.battle.effects.monster == []
    ticks = Enum.count(p.battle.log, &(&1.text =~ "mất #{per} máu vì độc"))
    assert ticks == 3
    assert p.battle.monster.hp < hp - per
  end

  test "trùm gây bỏng; bình máu giải bỏng" do
    Rng.put_sequence([0.99])
    p = %{player() | level: 20, stats: %{str: 5, agi: 0, vit: 300, ene: 5}}

    p = %{
      p
      | hp: Engine.derived(p).maxHp,
        inv: %{"potion_l" => 3},
        bosses: ["wolf", "orc_warrior"]
    }

    # Pháp Sư Bất Tử: Lửa Âm Phủ mỗi 3 lượt gây bỏng
    {_, p} = Engine.start_battle(p, 2, true)
    p = put_in(p.battle.monster.hp, 100_000)
    p = Enum.reduce(1..3, p, fn _, p -> elem(Engine.act(p, "attack"), 1) end)
    assert [%{id: "burn", power: per}] = p.battle.effects.player
    assert Enum.any?(p.battle.log, &(&1.text =~ "Bạn mất #{per} máu vì bị bỏng"))
    {_, p} = Engine.act(p, "potion")
    assert p.battle.effects.player == []
    assert Enum.any?(p.battle.log, &(&1.text == "Hết bị bỏng."))
  end

  test "hạ trùm mở vùng mới, gục ngã mất 10% vàng" do
    Rng.put_sequence([0.5])
    p = %{player() | level: 30, gold: 1000}
    refute Engine.zone_unlocked?(p, 1)
    {_, p} = Engine.start_battle(p, 0, true)
    p = put_in(p.battle.monster.hp, 1)
    {%{result: "win"}, won} = Engine.act(p, "attack")
    assert "wolf" in won.bosses
    assert Engine.zone_unlocked?(won, 1)
    assert List.last(won.battle.log).text =~ "Đã mở khu vực mới"

    p = %{p | hp: 1, stats: %{p.stats | agi: 0}}
    p = put_in(p.battle.monster.hp, 10_000)
    {%{result: "lose"}, lost} = Engine.act(p, "attack")
    assert lost.gold == 900 and lost.deaths == 1
    assert lost.hp == round(Engine.derived(lost).maxHp * 0.5)
  end

  test "lên cấp nhận điểm tiềm năng và hồi đầy máu" do
    p = %{player() | hp: 1}
    {levels, p} = Engine.gain_xp(p, 40 + Engine.xp_to_next(2))

    # Kiếm Sĩ 5 điểm / cấp, không tự tăng chỉ số; lên cấp hồi đầy máu và MP
    assert levels == 2 and p.level == 3 and p.points == 10
    assert p.stats.str == 28
    assert p.hp == Engine.derived(p).maxHp and p.mp == Engine.derived(p).maxMp
    {_, mg} = Engine.gain_xp(player("mg"), 40)
    assert mg.points == 7
  end

  test "Thợ Rèn nâng cấp đồ đang mặc bằng quặng và vàng" do
    p = %{player() | gold: 10_000}
    atk = Engine.derived(p).atk

    assert {%{ok: false, msg: "Thiếu nguyên liệu: Quặng Sắt 0/1."}, _} =
             Engine.upgrade(p, "weapon")

    p = Engine.add_item(p, "ore", 20)
    {%{ok: true, msg: "Đã nâng Gậy Gỗ lên +1."}, p} = Engine.upgrade(p, "weapon")
    # gậy gỗ tấn công 3: mỗi cấp ít nhất +1
    assert Engine.derived(p).atk == atk + 1
    assert p.inv["ore"] == 19 and p.gold == 10_000 - 8

    # lần nâng đầu tiên tách gậy đang mặc thành bản riêng (cấp nâng theo từng món)
    club = p.equip.weapon
    assert [%{uid: ^club, base: "club", rarity: 0}] = p.gear
    p = Enum.reduce(1..3, p, fn _, p -> elem(Engine.upgrade(p, "weapon"), 1) end)
    assert Engine.upgrade_level(p, club) == 4
    # +5 cần Vảy Cổ Long
    assert {%{ok: false, msg: "Thiếu nguyên liệu: Vảy Cổ Long 0/1."}, _} =
             Engine.upgrade(p, "weapon")

    {%{ok: true}, p} = p |> Engine.add_item("dragon_scale") |> Engine.upgrade("weapon")
    # +6 trở lên cần ngọc
    assert {%{ok: false, msg: "Thiếu nguyên liệu: Ngọc Phúc Lành 0/1."}, _} =
             Engine.upgrade(p, "weapon")

    assert Engine.view(p).bonus == %{club => 5}

    assert %{id: ^club, level: 5, cost: %{items: %{"jewel_bless" => 1}}} =
             Engine.view(p).forge.weapon

    # đồ cấp cao dùng Mithril; gậy mới mua là món khác, cấp 0
    assert %{gold: 600, items: %{"ore_rare" => 1}} = Engine.upgrade_cost("waraxe", 0)
    p = %{p | level: 10} |> Engine.add_item("broadsword") |> Engine.add_item("club")
    {_, p} = Engine.equip(p, "broadsword")
    assert Engine.upgrade_level(p, "broadsword") == 0
    {_, p} = Engine.equip(p, "club")
    assert Engine.derived(p).atk == Engine.derived(%{p | upgrades: %{}}).atk
    {_, p} = Engine.equip(p, club)
    assert Engine.derived(p).atk == Engine.derived(%{p | upgrades: %{}}).atk + 5

    # bán gậy thường không mất cấp của gậy đã nâng; bán gậy đã nâng thì mất
    {_, p} = Engine.equip(p, "broadsword")
    {_, p} = Engine.sell(p, "club")
    assert p.upgrades == %{club => 5}
    {_, p} = Engine.sell(p, club)
    assert p.upgrades == %{} and p.gear == []
    assert {%{ok: false, msg: "Chưa mặc đồ ở chỗ này."}, _} = Engine.upgrade(p, "shield")
  end

  test "chuyển sinh ở cấp tối đa: về cấp 1, giữ đồ và vàng, nhận điểm cộng thêm" do
    p = %{player() | gold: 5000, bosses: ["wolf"]}
    assert {%{ok: false, msg: "Cần đạt cấp 50 mới chuyển sinh được."}, _} = Engine.rebirth(p)

    p = %{p | level: 50, stats: %{str: 150, agi: 4, vit: 60, ene: 5}, points: 2}
    {%{ok: true, msg: msg}, q} = Engine.rebirth(p)
    assert msg =~ "Chuyển sinh lần 1"
    assert q.level == 1 and q.xp == 0 and q.rebirths == 1
    assert q.stats == %{str: 28, agi: 20, vit: 25, ene: 10}
    assert q.points == Engine.rebirth_points()
    assert q.gold == 5000 and q.bosses == ["wolf"] and q.equip == p.equip
    assert q.hp == Engine.derived(q).maxHp

    {_, q2} = Engine.rebirth(%{q | level: 50})
    assert q2.rebirths == 2 and q2.points == 2 * Engine.rebirth_points()
    assert {%{ok: false}, _} = Engine.rebirth(%{q2 | level: 50, rebirths: Engine.max_rebirths()})
  end

  test "bot chơi hết game với mỗi lớp nhân vật" do
    for cls <- ~w(dk dw elf mg) do
      r = Simulator.run(cls)
      assert r.victory, "#{cls} không thắng: #{inspect(r)}"
      assert r.fights in 300..700
    end
  end
end

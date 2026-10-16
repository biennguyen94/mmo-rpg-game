defmodule HacLong.Game.FormulaAuditTest do
  @moduledoc """
  Phase 8 (rà soát công thức, `docs/FORMULA_AUDIT.md`): mỗi dòng cộng thêm / thưởng phải đổi đúng chỉ số theo
  số trong `priv/game_data/` (không chép số vào đây: đọc từ RULES), và công thức sát thương đúng như mô tả.
  """
  use ExUnit.Case, async: true

  alias HacLong.Game.{Blessing, Commands, Data, Engine, Gear, Rng}

  @r Data.rules()
  @per_line @r.upgrade.life.per_line

  # Kiếm Sĩ cấp 50, chỉ số đủ mặc mọi món
  defp hero(cls \\ "dk") do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Rs#{cls}", "cls" => cls})

    %{
      p
      | level: 50,
        stats: %{str: 400, agi: 200, vit: 200, ene: 300},
        gear: [],
        equip: Engine.empty_equip()
    }
  end

  # mặc món `g` (bản riêng) vào ô `slot`, cấp ép `up`
  defp wear(p, slot, g, up \\ 0) do
    p = %{p | gear: p.gear ++ [g]} |> put_in([:equip, slot], g.uid)
    if up > 0, do: Map.put(p, :upgrades, Map.put(p[:upgrades] || %{}, g.uid, up)), else: p
  end

  defp d(p), do: Engine.derived(p)
  @sword "item_0_26"
  @armor "item_8_33"

  test "dòng cộng thêm (Ngọc Sinh Mệnh): vũ khí / dây chuyền + tấn công, đồ khác + phòng thủ, mỗi dòng per_line" do
    base = hero() |> wear(:weapon, Gear.new(@sword)) |> wear(:armor, Gear.new(@armor))
    opt = hero() |> wear(:weapon, Gear.new(@sword, 3)) |> wear(:armor, Gear.new(@armor, 2))
    assert d(opt).atk - d(base).atk == 3 * @per_line
    assert d(opt).def - d(base).def == 2 * @per_line

    p0 = hero() |> wear(:pendant, Gear.new("item_13_27"))
    p2 = hero() |> wear(:pendant, Gear.new("item_13_27", 2))
    assert d(p2).atk - d(p0).atk == 2 * @per_line

    r0 = hero() |> wear(:ring1, Gear.new("item_13_24"))
    r1 = hero() |> wear(:ring1, Gear.new("item_13_24", 1))
    assert d(r1).def - d(r0).def == @per_line
  end

  test "ép +N: mỗi cấp hiệu dụng + bonus_pct chỉ số món; từ double_from tính gấp đôi" do
    w = Data.item(@sword)
    step = max(1, round(w.atk * @r.upgrade.bonus_pct))
    p0 = hero() |> wear(:weapon, Gear.new(@sword))

    for up <- [1, 6, 9, 10, 11] do
      pu = hero() |> wear(:weapon, Gear.new(@sword), up)
      assert d(pu).atk - d(p0).atk == Engine.effective_level(up) * step
    end

    assert Engine.effective_level(9) == 9
    assert Engine.effective_level(11) == 11 + 11 - Data.upgrade().double_from + 1
  end

  test "Excellent: mỗi dòng đổi đúng chỉ số" do
    o = @r.excellent.options
    base = hero() |> wear(:weapon, Gear.new(@sword)) |> wear(:armor, Gear.new(@armor))
    b = d(base)

    exc = fn wl, al ->
      hero()
      |> wear(:weapon, Map.put(Gear.new(@sword), :exc, wl))
      |> wear(:armor, Map.put(Gear.new(@armor), :exc, al))
      |> d()
    end

    assert_in_delta exc.(["atk_pct"], []).atk, b.atk * (1 + o.weapon.atk_pct), 1
    assert_in_delta exc.(["crit"], []).crit, b.crit + o.weapon.crit, 1.0e-9
    assert_in_delta exc.(["atk_lvl"], []).atk, b.atk + o.weapon.atk_lvl * 50, 1
    assert_in_delta exc.(["ar_pct"], []).ar, b.ar * (1 + o.weapon.ar_pct), 1.0e-6
    assert_in_delta exc.([], ["hp_pct"]).maxHp, b.maxHp * (1 + o.armor.hp_pct), 1
    assert_in_delta exc.([], ["mp_pct"]).maxMp, b.maxMp * (1 + o.armor.mp_pct), 1
    assert_in_delta exc.([], ["def_rate"]).dodge, b.dodge * (1 + o.armor.def_rate), 1.0e-9
    assert exc.([], ["dmg_red"]).excAbsorb == o.armor.dmg_red
    assert exc.([], ["reflect"]).excReflect == o.armor.reflect

    # trần giảm sát thương / phản đòn khi nhiều món
    many =
      Enum.reduce(
        [:armor, :helm, :pants, :gloves, :boots, :shield, :ring1, :ring2],
        hero(),
        fn slot, p ->
          base_id =
            %{
              armor: @armor,
              helm: "item_7_33",
              pants: "item_9_33",
              gloves: "item_10_33",
              boots: "item_11_33",
              shield: "item_6_18",
              ring1: "item_13_24",
              ring2: "item_13_24"
            }[slot]

          wear(p, slot, Map.put(Gear.new(base_id), :exc, ["dmg_red", "reflect"]))
        end
      )

    assert d(many).excAbsorb == @r.excellent.max_dmg_red
    assert d(many).excReflect == @r.excellent.max_reflect
  end

  test "May mắn: vũ khí + chí mạng; giáp không; Kỹ năng: + sát thương chiêu" do
    ls = @r.luck_skill
    b = hero() |> wear(:weapon, Gear.new(@sword)) |> d()
    lw = hero() |> wear(:weapon, Map.merge(Gear.new(@sword), %{luck: true, skill: true})) |> d()

    la =
      hero()
      |> wear(:weapon, Gear.new(@sword))
      |> wear(:armor, Map.put(Gear.new(@armor), :luck, true))
      |> d()

    assert_in_delta lw.crit, b.crit + ls.luck_crit, 1.0e-9
    assert lw.skillDmg == ls.skill_dmg
    assert la.crit == b.crit
  end

  test "đồ Thần: phòng thủ món + piece_def_pct; mức bộ cộng dồn" do
    a = @r.ancient
    p0 = hero() |> wear(:armor, Gear.new(@armor))
    p1 = hero() |> wear(:armor, Map.put(Gear.new(@armor), :anc, true))
    it = Data.item(@armor)
    assert d(p1).def - d(p0).def == round(it.def * (1 + a.piece_def_pct)) - it.def

    two = p1 |> wear(:helm, Map.put(Gear.new("item_7_33"), :anc, true))
    lvl2 = Enum.find(a.bonus, &(&1.count == 2))
    assert Engine.ancient_bonus(two).atk_pct == lvl2.atk_pct
  end

  test "thưởng đủ bộ giáp: def_pct, atk_pct, máu hp_per_tier × bậc" do
    sb = @r.set_bonus

    pieces = [
      armor: @armor,
      helm: "item_7_33",
      pants: "item_9_33",
      gloves: "item_10_33",
      boots: "item_11_33"
    ]

    four =
      Enum.reduce(Enum.take(pieces, 4), hero(), fn {s, id}, p -> wear(p, s, Gear.new(id)) end)

    full = wear(four, :boots, Gear.new("item_11_33"))
    refute Engine.set_bonus(four).active
    assert %{active: true, tier: tier} = Engine.set_bonus(full)

    no_bonus_def =
      Enum.sum(for {_s, id} <- pieces, do: Data.item(id).def) + round(0.4 * 200 + 0.5 * 50)

    assert d(full).def == round(no_bonus_def * (1 + sb.def_pct))
    assert d(full).maxHp - d(four).maxHp == sb.hp_per_tier * tier
  end

  test "cánh: phòng thủ + ép, % sát thương / hấp thụ theo cấp ép, dòng phụ" do
    wid = "wing_dk_3"
    w = Data.item(wid)
    p0 = hero()
    p = hero() |> wear(:wing, Map.put(Gear.new(wid), :wopt, "hp"), 5)
    assert d(p).wingDmg == Float.round(w.dmg + @r.combat.wing_per_level * 5, 3)
    assert d(p).wingAbsorb == Float.round(w.absorb + @r.combat.wing_per_level * 5, 3)
    assert d(p).def - d(p0).def == w.def + 5 * max(1, round(w.def * @r.upgrade.bonus_pct))
    assert d(p).maxHp - d(p0).maxHp == Gear.wopt_value(w.tier, "hp")

    ig = hero() |> wear(:wing, Map.put(Gear.new(wid), :wopt, "ignore_def")) |> d()
    assert ig.ignoreDef == Gear.wopt_value(w.tier, "ignore_def")
  end

  test "nhẫn máu cộng máu tối đa; Đài Phúc Lành cộng % đúng chỉ số" do
    ring = hero() |> wear(:ring1, Gear.new("item_13_23"))
    assert d(ring).maxHp - d(hero()).maxHp == Data.item("item_13_23").hp

    b = d(hero())

    for k <- ~w(hp atk def) do
      p = Map.put(hero(), :blessing, %{map: "x", kind: k, left: 3})
      key = %{"hp" => :maxHp, "atk" => :atk, "def" => :def}[k]
      assert_in_delta Map.fetch!(d(p), key), Map.fetch!(b, key) * (1 + Blessing.rules().pct), 1
    end
  end

  test "sát thương: thủ kiểu đòn²/(đòn+thủ), sàn mềm, sàn cứng 1, × taken" do
    Rng.put_sequence([0.0, 1.0, 0.5])
    [lo, hi] = @r.combat.damage_spread

    for {atk, dfn} <- [{100, 0}, {100, 100}, {100, 10_000}, {1, 50}] do
      dmg = Engine.damage(atk, dfn)
      raw_lo = atk * lo
      raw_hi = atk * hi

      min_expected =
        max(1, round(max(raw_lo * raw_lo / (raw_lo + dfn), raw_lo * @r.combat.soft_floor)))

      max_expected =
        max(1, round(max(raw_hi * raw_hi / (raw_hi + dfn), raw_hi * @r.combat.soft_floor)))

      assert dmg in min_expected..max_expected
    end

    Rng.put_sequence([0.5])
    full = Engine.damage(1000, 100)
    half = Engine.damage(1000, 100, 1, 0.5)
    assert_in_delta half, full / 2, 1
    Rng.clear()
  end

  test "đối thủ là người (đấu trường, đồ sát): giảm sát thương của cánh + Excellent nằm ở taken, máu thật" do
    p =
      hero()
      |> wear(:wing, Gear.new("wing_dk_3"))
      |> wear(:armor, Map.put(Gear.new(@armor), :exc, ["dmg_red"]))

    dp = d(p)
    o = HacLong.Arena.opponent(p, 1)
    assert o.maxHp == dp.maxHp
    assert_in_delta o.taken, (1 - dp.wingAbsorb) * (1 - dp.excAbsorb), 1.0e-4
    assert o.crit_mult == dp.critMult
  end

  test "tỉ lệ trúng AR/(AR+DR) trong [min, max]" do
    h = @r.combat.hit
    assert Engine.hit_chance(1, 100) == h.min
    assert Engine.hit_chance(100_000, 1) == h.max
    assert_in_delta Engine.hit_chance(100, 50), 100 / (100 + 50 * h.monster_dr), 1.0e-9
  end

  test "B-28: né chặn max_total sau Excellent; ép nhẫn máu cộng máu; quái không né" do
    c = @r.combat.dodge

    pieces = %{
      armor: @armor,
      helm: "item_7_33",
      pants: "item_9_33",
      gloves: "item_10_33",
      boots: "item_11_33",
      shield: "item_6_18",
      ring1: "item_13_24",
      ring2: "item_13_24"
    }

    agile = %{hero() | stats: %{str: 400, agi: 400, vit: 200, ene: 300}}

    p =
      Enum.reduce(pieces, agile, fn {slot, id}, p ->
        wear(p, slot, Map.put(Gear.new(id), :exc, ["def_rate"]))
      end)

    assert d(p).dodge == c.max_total

    ring = "item_13_23"
    hp = Data.item(ring).hp
    r0 = hero() |> wear(:ring1, Gear.new(ring))
    r7 = hero() |> wear(:ring1, Gear.new(ring), 7)
    assert d(r7).maxHp - d(r0).maxHp == 7 * max(1, round(hp * @r.upgrade.bonus_pct))
    assert d(r7).def == d(r0).def

    assert Engine.make_monster(%{id: "x", name: "x", level: 30}, false).dodge == 0
  end
end

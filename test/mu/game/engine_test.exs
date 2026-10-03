defmodule Mu.Game.EngineTest do
  use ExUnit.Case, async: true

  alias Mu.Game.{Data, Engine, Rng}

  defp dk(attrs \\ %{}) do
    Map.merge(
      %{
        class: "DK",
        level: 1,
        experience: 0,
        strength: 28,
        agility: 20,
        vitality: 25,
        energy: 10,
        free_stat_points: 0
      },
      attrs
    )
  end

  @sword %{"attackMin" => 3, "attackMax" => 7, "speed" => 20}
  @armor %{"defense" => 10}
  @ring %{"hpBonus" => 20}

  describe "derived (§4.1 DK)" do
    test "DK cấp 1 không trang bị (số tính tay)" do
      d = Engine.derived(dk())
      # 28/4 = 7; 28/6 = 4.67 → 4; 20/4 = 5; 1×5 + 20×1.5 = 35; 20/3 → 6; 20/15 → 1
      assert d.attack_max == 7
      assert d.attack_min == 4
      assert d.defense == 5
      assert d.attack_rate == 35
      assert d.defense_rate == 6
      assert d.attack_speed == 1
      # 1000 / (1 + 1/100) = 990.1 → 990
      assert d.cooldown_ms == 990
      assert {d.hp_max, d.mp_max} == {185, 30}
    end

    test "cộng trang bị: vũ khí, giáp, tốc độ, hpBonus (G6)" do
      d = Engine.derived(dk(), [@sword, @armor, @ring])
      assert d.attack_max == 7 + 7
      assert d.attack_min == 4 + 3
      assert d.defense == 15
      # 20/15 + 20 = 21.33 → 21; 1000/1.21 = 826.4 → 826
      assert d.attack_speed == 21
      assert d.cooldown_ms == 826
      assert d.hp_max == 205
    end

    test "theo cấp và stat" do
      d = Engine.derived(dk(%{level: 10, agility: 30, vitality: 30, energy: 15}))
      assert d.attack_rate == 50 + 45
      assert d.defense_rate == 10
      assert d.hp_max == 110 + 9 * 3 + 30 * 3
      assert d.mp_max == 20 + 9 + 15
    end
  end

  test "cooldown §6: bảng ví dụ của KB" do
    assert Engine.cooldown_ms(0) == 1000
    assert Engine.cooldown_ms(50) == 666
    assert Engine.cooldown_ms(100) == 500
    assert Engine.cooldown_ms(200) == 333
    assert Engine.cooldown_ms(300) == 250
    assert Engine.cooldown_ms(1000) == 250
  end

  test "skill cooldown: basic theo attack speed (G2), twisting_slash 800" do
    d = Engine.derived(dk())
    assert Engine.skill_cooldown_ms(Data.skill("basic_attack"), d) == 990
    assert Engine.skill_cooldown_ms(Data.skill("twisting_slash"), d) == 800
  end

  test "hit chance §5 + clamp" do
    assert Engine.hit_chance(35, 3) == 35 / 38
    assert Engine.hit_chance(10, 6) == 10 / 16
    assert Engine.hit_chance(1000, 1) == 0.95
    assert Engine.hit_chance(1, 1000) == 0.05
    assert Engine.hit_chance(0, 0) == 0.95
  end

  describe "damage §4" do
    test "trừ defense, floor một lần ở cuối" do
      assert Engine.damage(%{raw_attack: 7, skill_multiplier: 1.0, target_defense: 1}) == 6
      # 7 × 1.2 = 8.4 − 1 = 7.4 → 7
      assert Engine.damage(%{raw_attack: 7, skill_multiplier: 1.2, target_defense: 1}) == 7
    end

    test "softFloor = 10% và hardFloor = 1" do
      # Spider 14 vào defense 15: max(−1, 1.4) → 1
      assert Engine.damage(%{raw_attack: 14, skill_multiplier: 1, target_defense: 15}) == 1
      # 50 vào defense 48: max(2, 5.0) → 5
      assert Engine.damage(%{raw_attack: 50, skill_multiplier: 1, target_defense: 48}) == 5
      assert Engine.damage(%{raw_attack: 1, skill_multiplier: 1, target_defense: 100}) == 1
    end

    test "chí mạng nhân trước khi trừ defense" do
      ctx = %{raw_attack: 10, skill_multiplier: 1, target_defense: 5}
      assert Engine.damage(Map.merge(ctx, %{critical?: true, critical_multiplier: 1.5})) == 10
    end

    test "Spider vào DK cấp 1 (defense 5) gây 3–9 (KB_CONFIG §4)" do
      dmgs =
        for raw <- 8..14,
            do: Engine.damage(%{raw_attack: raw, skill_multiplier: 1, target_defense: 5})

      assert Enum.min(dmgs) == 3 and Enum.max(dmgs) == 9
    end
  end

  describe "roll_attack với seed" do
    test "lặp lại được; trượt thì dmg 0; crit tắt (G1)" do
      a = Engine.derived(dk())
      spider = Engine.monster_stats(Data.monster("spider"))

      run = fn seed ->
        Enum.map_reduce(1..200, Rng.new(seed), fn _, r -> Engine.roll_attack(r, a, spider) end)
        |> elem(0)
      end

      assert run.(7) == run.(7)
      results = run.(7)
      assert Enum.all?(results, &(not &1.crit))
      assert Enum.all?(results, &(&1.hit or &1.dmg == 0))
      hits = Enum.filter(results, & &1.hit)
      # raw 4..7 − defense 1 → 3..6
      assert Enum.all?(hits, &(&1.dmg in 3..6))
      # tỉ lệ trúng ≈ 35/38 = 0.92
      assert_in_delta length(hits) / 200, 35 / 38, 0.06
    end
  end

  describe "EXP & level (§3, G19)" do
    test "expRequired = round(100 × level^1.5)" do
      assert Engine.exp_required(1) == 100
      assert Engine.exp_required(2) == 283
      assert Engine.exp_required(9) == 2700

      # Số Spider (10 EXP) tới cấp 2 / 5 / 10: KB_CONFIG ghi 10 / 170 / 1110 (không làm tròn
      # từng cấp); làm tròn từng cấp (G19) cho 10 / 171 / 1111 — lệch ≤ 1 con.
      total = fn lv -> Enum.sum(for l <- 1..(lv - 1), do: Engine.exp_required(l)) end
      kills = fn lv -> div(total.(lv) + 9, 10) end
      assert {kills.(2), kills.(5), kills.(10)} == {10, 171, 1111}
    end

    test "lên cấp: điểm tự do +5, EXP dư chuyển sang cấp sau, lên nhiều cấp một lần" do
      {c, 1} = Engine.add_exp(dk(%{experience: 95}), 10)
      assert {c.level, c.experience, c.free_stat_points} == {2, 5, 5}

      {c, 3} = Engine.add_exp(dk(), 100 + 283 + 520 + 1)
      assert {c.level, c.experience, c.free_stat_points} == {4, 1, 15}
    end

    test "maxLevel 30 (P2-2): EXP dừng ở 0" do
      {c, 1} = Engine.add_exp(dk(%{level: 29, experience: 15_617 - 10}), 50)
      assert {c.level, c.experience} == {30, 0}
      {c, 0} = Engine.add_exp(c, 500)
      assert {c.level, c.experience} == {30, 0}
    end

    test "EXP Spider: không penalty ở Phase 1; penalty giảm tới minExpRatio (G23)" do
      assert Engine.exp_gain(10, 1, 2) == 10
      assert Engine.exp_gain(10, 10, 2) == 10
      assert Engine.exp_gain(10, 12, 2) == 10
      assert Engine.exp_gain(10, 13, 2) == 9
      assert Engine.exp_gain(100, 17, 2) == 50
      assert Engine.exp_gain(100, 50, 2) == 10
      assert Engine.exp_gain(1, 50, 2) == 1
    end
  end

  describe "alloc (§1)" do
    test "cộng đúng, trừ điểm tự do; tổng đã cộng ≤ điểm kiếm được" do
      c = dk(%{level: 3, free_stat_points: 10})
      assert {:ok, c} = Engine.alloc(c, "vitality", 4)
      assert {c.vitality, c.free_stat_points} == {29, 6}

      assert Engine.allocated_points(c) + c.free_stat_points ==
               Mu.Game.Stats.earned_points("DK", 3)

      assert {:error, "REQUIREMENT_NOT_MET"} = Engine.alloc(c, "strength", 7)
    end

    test "không cho giảm, không stat lạ, không số lạ" do
      c = dk(%{free_stat_points: 5})

      for {stat, pts} <- [
            {"strength", 0},
            {"strength", -1},
            {"strength", 1.5},
            {"luck", 1},
            {"level", 1},
            {"strength", "2"}
          ] do
        assert {:error, "FORBIDDEN"} = Engine.alloc(c, stat, pts), inspect({stat, pts})
      end
    end
  end

  test "skill học theo class + level (§7)" do
    assert Engine.skills(dk()) == ["basic_attack"]

    assert Enum.sort(Engine.skills(dk(%{level: 10}))) ==
             ["basic_attack", "falling_slash", "twisting_slash"]

    assert {:error, "REQUIREMENT_NOT_MET"} = Engine.can_use_skill(dk(), "twisting_slash")
    assert :ok = Engine.can_use_skill(dk(%{level: 10}), "twisting_slash")
    assert {:error, "INVALID_TARGET"} = Engine.can_use_skill(dk(), "fireball")
  end

  describe "P2-M3: skill theo class, heal, buff, hồi MP" do
    test "skill học theo class + requiredLevel" do
      assert Enum.sort(Engine.skills(dk(%{level: 30}))) ==
               ~w(basic_attack death_stab falling_slash twisting_slash)

      dw = %{dk(%{level: 1}) | class: "DW"}
      assert Enum.sort(Engine.skills(dw)) == ~w(basic_attack energy_ball)

      assert Enum.sort(Engine.skills(%{dw | level: 18})) ==
               ~w(basic_attack energy_ball fire_ball flame lightning teleport)

      elf = %{dk(%{level: 12}) | class: "ELF"}

      assert Enum.sort(Engine.skills(elf)) ==
               ~w(basic_attack greater_damage greater_defense heal triple_shot)
    end

    test "heal / buff theo energy (đề xuất §5.3)" do
      assert Engine.effect_value(Data.skill("heal")["effect"], 15) == 13
      assert Engine.effect_value(Data.skill("greater_defense")["effect"], 15) == 3
      assert Engine.effect_value(Data.skill("greater_damage")["effect"], 15) == 5
      assert Engine.effect_value(Data.skill("greater_damage")["effect"], 70) == 13
    end

    test "buff: cùng loại làm mới thời gian + giữ giá trị lớn hơn; khác loại cộng dồn; hết hạn" do
      b = Engine.add_buff(%{}, "greater_defense", "defense", 5, 1000)
      b = Engine.add_buff(b, "greater_defense", "defense", 3, 2000)
      assert b["greater_defense"] == %{stat: "defense", value: 5, until: 2000}
      b = Engine.add_buff(b, "greater_damage", "damageBonus", 4, 1500)

      stats = Engine.with_buffs(%{defense: 10, attack_min: 1}, b)
      assert {stats.defense, stats.damage_bonus} == {15, 4}

      assert {%{"greater_defense" => _} = kept, true} = Engine.expire_buffs(b, 1500)
      assert map_size(kept) == 1
      assert {^kept, false} = Engine.expire_buffs(kept, 1999)
    end

    test "Greater Damage cộng phẳng ở bước 3 của §4" do
      a = %{attack_min: 10, attack_max: 10, attack_rate: 1000, damage_bonus: 5}
      d = %{defense: 0, defense_rate: 0}

      hits =
        for seed <- 1..20,
            {%{hit: true, dmg: dmg}, _} <- [Engine.roll_attack(Rng.new(seed), a, d, 2.0)],
            do: dmg

      assert hits != [] and Enum.all?(hits, &(&1 == 25))
    end

    test "hồi MP energy/40 mỗi giây" do
      assert Engine.mp_regen(30, 1000) == 0.75
      assert Engine.mp_regen(10, 2000) == 0.5
    end
  end
end

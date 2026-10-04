defmodule HacLong.Game.CombatFormulaTest do
  # Phase 3 (INTEGRATION_PLAN §11): sát thương nhiều bước, tỉ lệ trúng, phạt EXP chênh cấp.
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine, Rng}

  setup do
    on_exit(&Rng.clear/0)
  end

  describe "damage/4" do
    test "đòn thấp ~ cao theo damage_spread, trừ thủ đòn²/(đòn + thủ)" do
      [lo, hi] = Data.rules().combat.damage_spread
      Rng.put_sequence([0.0])
      assert Engine.damage(100, 0) == round(100 * lo)
      Rng.put_sequence([0.999999])
      assert Engine.damage(100, 0) == round(100 * hi)
      Rng.put_sequence([0.5])
      raw = 100 * (lo + 0.5 * (hi - lo))
      assert Engine.damage(100, 50) == round(raw * raw / (raw + 50))
    end

    test "hệ số nhân trước khi trừ thủ; thủ thế / hấp thụ nhân sau" do
      Rng.put_sequence([0.5])
      raw = 100 * 2.0
      assert Engine.damage(100, 40, 2.0) == round(raw * raw / (raw + 40))
      Rng.put_sequence([0.5])
      assert Engine.damage(100, 40, 2.0, 0.5) == round(raw * raw / (raw + 40) * 0.5)
    end

    test "sàn mềm 20 % đòn gốc khi thủ quá cao; sàn cứng 1" do
      floor = Data.rules().combat.soft_floor
      Rng.put_sequence([0.5])
      assert Engine.damage(100, 100_000) == round(100 * floor)
      Rng.put_sequence([0.5])
      assert Engine.damage(1, 100_000) == 1
      assert Engine.damage(0, 10) == 1
    end
  end

  describe "hit_chance/2" do
    test "AR / (AR + DR), chặn 5 % ~ 95 %" do
      h = Data.rules().combat.hit
      assert_in_delta Engine.hit_chance(80, 10), 80 / (80 + 10 * h.monster_dr), 1.0e-9
      assert Engine.hit_chance(100_000, 1) == h.max
      assert Engine.hit_chance(1, 1000) == h.min
    end

    test "bảng nhân vật có tỉ lệ trúng quái cùng cấp, đòn thấp ~ cao" do
      {:ok, p} = Engine.new_player("Thử", "elf")
      d = Engine.derived(p)
      assert d.ar == p.level * 5 + p.stats.agi * 1.5
      assert d.hitRate == Engine.hit_chance(d.ar, p.level)
      assert d.atkMin < d.atk and d.atk < d.atkMax
    end
  end

  describe "phạt EXP chênh cấp (A4)" do
    test "chênh tới 10 cấp không phạt; mỗi cấp hơn −10 %, tối thiểu 10 %" do
      assert Engine.xp_factor(20, 10) == 1
      assert_in_delta Engine.xp_factor(21, 10), 0.9, 1.0e-9
      assert_in_delta Engine.xp_factor(25, 10), 0.5, 1.0e-9
      assert Engine.xp_factor(50, 1) == 0.1
    end

    test "hạ quái thường thấp hơn nhiều cấp: EXP bị bớt, nhật ký ghi lý do; trùm không bị phạt" do
      {:ok, p} = Engine.new_player("Thử", "dk")
      p = %{p | level: 25, stats: %{p.stats | str: 500}}

      win = fn boss? ->
        {_, q} = Engine.start_battle(p, 0, boss?)
        m = q.battle.monster
        q = put_in(q.battle.monster.hp, 1)
        Rng.put_sequence([0.99])
        {_, q} = Engine.act(q, "attack")
        Rng.clear()
        {m, q}
      end

      {m, q} = win.(false)
      assert q.battle.result == "win"
      factor = Engine.xp_factor(25, m.level)
      assert factor < 1
      assert q.battle.reward.xp == round(m.xp * factor)
      assert Enum.any?(q.battle.log, &(&1.text =~ "vì cao hơn quái"))

      {b, q} = win.(true)
      assert q.battle.result == "win"
      assert q.battle.reward.xp == b.xp
    end
  end
end

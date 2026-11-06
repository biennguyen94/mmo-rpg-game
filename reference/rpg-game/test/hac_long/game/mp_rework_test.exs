defmodule HacLong.Game.MpReworkTest do
  # Phase 12: MP kỹ năng theo cấp, hồi MP theo Năng lượng, bình máu / mana hồi theo %, giá bình theo cấp
  use ExUnit.Case, async: true

  alias HacLong.Game.{Engine, Rng}

  defp player(cls \\ "dw") do
    {:ok, p} = Engine.new_player("Thử", cls)
    HacLong.Game.Mastery.maxed(p)
  end

  test "MP kỹ năng tăng theo cấp" do
    p = player()
    fb = hd(Engine.skills(p))
    assert Engine.skill_mp(p, fb) == fb.mp
    per = HacLong.Game.Data.rules().combat.skill_mp_per_level
    assert Engine.skill_mp(%{p | level: 26}, fb) == round(fb.mp * (1 + per * 25))
  end

  test "hồi MP mỗi lượt theo MP tối đa và Năng lượng" do
    p = player()
    d = Engine.derived(p)
    assert Engine.mp_regen(p) == max(1, round(d.maxMp * 0.03 + p.stats.ene * 0.1))
    q = put_in(p.stats.ene, p.stats.ene + 100)
    assert Engine.mp_regen(q) > Engine.mp_regen(p)
  end

  # DECISIONS "Bình máu / mana hồi số": hồi số cố định, không theo % máu / MP tối đa
  test "bình máu và bình mana hồi số cố định, không vượt máu / MP tối đa" do
    hp = fn id -> HacLong.Game.Data.item(id).heal end
    mana = fn id -> HacLong.Game.Data.item(id).mana end
    p = player() |> Map.put(:level, 30)
    d = Engine.derived(p)
    assert Engine.potion_amount(p, "potion_m") == {:hp, hp.("potion_m")}
    assert Engine.potion_amount(Map.put(p, :level, 1), "potion_m") == {:hp, hp.("potion_m")}
    assert Engine.potion_amount(p, "mana_l") == {:mp, mana.("mana_l")}
    assert hp.("potion_s") < hp.("potion_m") and hp.("potion_m") < hp.("potion_l")
    assert mana.("mana_s") < mana.("mana_m") and mana.("mana_m") < mana.("mana_l")

    p = %{
      p
      | hp: 1,
        mp: 0,
        inv: Map.merge(p.inv, %{"mana_s" => 1, "potion_s" => 1, "potion_l" => 1})
    }

    {%{ok: true}, q} = Engine.use_potion(p, "mana_s")
    assert q.mp == min(d.maxMp, mana.("mana_s"))
    assert Map.get(q.inv, "mana_s", 0) == 0
    {%{ok: true}, q} = Engine.use_potion(q, "potion_s")
    assert q.hp == 1 + hp.("potion_s")
    {%{ok: true}, q} = Engine.use_potion(q, "potion_l")
    assert q.hp == min(d.maxHp, 1 + hp.("potion_s") + hp.("potion_l"))
  end

  test "uống mana trong trận mất một lượt và hồi MP" do
    Rng.put_sequence([0.5])
    p = %{player() | mp: 0, inv: %{"mana_m" => 2}}
    {_, p} = Engine.start_battle(p, 0, true)
    {%{ok: true}, q} = Engine.act(p, "mana")
    assert q.mp > 0
    assert q.inv["mana_m"] == 1
    assert Enum.any?(q.battle.log, &(&1.text =~ "hồi"))

    assert {%{ok: false, msg: "Hết bình mana."}, _} =
             Engine.act(%{q | inv: %{}, mp: 0}, "mana")
  end

  test "giá bình tăng theo cấp, giá bán lại theo giá gốc" do
    p = player()
    assert Engine.price(p, "potion_s") == 15
    assert Engine.price(%{p | level: 11}, "mana_s") == 30
    assert Engine.price(%{p | level: 11}, "dagger") == HacLong.Game.Data.item("dagger").price
    p = %{p | level: 11, gold: 100}
    {%{ok: true}, q} = Engine.buy(p, "potion_s")
    assert q.gold == 70
    assert Engine.sell_price("potion_s") == floor(15 * 0.4)
  end
end

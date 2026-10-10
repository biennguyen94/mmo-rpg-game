defmodule HacLong.Game.MpReworkTest do
  # Phase 12: MP kỹ năng theo cấp, hồi MP theo Năng lượng, bình máu / mana hồi theo %, giá bình theo cấp
  use ExUnit.Case, async: true

  alias HacLong.Game.{Engine, Rng}

  defp player(cls \\ "dw") do
    {:ok, p} = Engine.new_player("Thử", cls)
    p
  end

  test "MP kỹ năng tăng theo cấp" do
    p = player()
    fb = hd(Engine.skills(p))
    assert Engine.skill_mp(p, fb) == fb.mp
    assert Engine.skill_mp(%{p | level: 26}, fb) == round(fb.mp * 2)
  end

  test "hồi MP mỗi lượt theo MP tối đa và Năng lượng" do
    p = player()
    d = Engine.derived(p)
    assert Engine.mp_regen(p) == max(1, round(d.maxMp * 0.03 + p.stats.ene * 0.1))
    q = put_in(p.stats.ene, p.stats.ene + 100)
    assert Engine.mp_regen(q) > Engine.mp_regen(p)
  end

  test "bình máu và bình mana hồi theo phần trăm" do
    p = player() |> Map.put(:level, 30)
    d = Engine.derived(p)
    assert Engine.potion_amount(p, "potion_m") == {:hp, round(d.maxHp * 0.4)}
    assert Engine.potion_amount(p, "mana_l") == {:mp, round(d.maxMp * 0.7)}

    p = %{p | hp: 1, mp: 0, inv: Map.merge(p.inv, %{"mana_s" => 1, "potion_s" => 1})}
    {%{ok: true}, q} = Engine.use_potion(p, "mana_s")
    assert q.mp == round(d.maxMp * 0.2)
    assert Map.get(q.inv, "mana_s", 0) == 0
    {%{ok: true}, q} = Engine.use_potion(q, "potion_s")
    assert q.hp == 1 + round(d.maxHp * 0.2)
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

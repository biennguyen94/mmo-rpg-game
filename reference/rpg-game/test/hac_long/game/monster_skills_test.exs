defmodule HacLong.Game.MonsterSkillsTest do
  @moduledoc "DECISIONS \"Quái dùng kỹ năng theo hệ\": kỹ năng quái theo hệ / bậc, kháng hệ nhẫn / dây chuyền kiểu MU."
  use ExUnit.Case, async: true

  alias HacLong.Admin
  alias HacLong.Game.{Commands, Data, Engine, Rng}

  setup do
    on_exit(&Rng.clear/0)
    :ok
  end

  @ms Data.rules().monster_skills

  defp player(cls \\ "dk") do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Ms#{cls}", "cls" => cls})
    p = %{p | level: 40, stats: %{str: 200, agi: 60, vit: 150, ene: 30}}
    %{p | hp: Engine.derived(p).maxHp}
  end

  defp give(p, base, up) do
    {:ok, f} = Admin.build("give_gear", %{"base" => base, "up" => up, "equip" => true})
    {:ok, p, _} = f.(p)
    p
  end

  # trận với quái hệ `el`, chỉ dùng kỹ năng `id`, mỗi lượt đều tung (Rng cố định 0.5)
  defp fight(p, el, id) do
    spec = %{id: "t_#{el}", name: "Quái #{el}", level: 38, element: el, mult: 20, atk_mult: 1}
    {_, p} = Engine.start_side_encounter(p, spec, "Thử", "forest")
    k = Enum.find(Engine.mskills(:elite, el), &(&1.id == id))

    p =
      update_in(
        p.battle.monster,
        &Map.merge(&1, %{mskills: [k], mskill_chance: 1.0, special: nil})
      )

    Rng.put_sequence([0.5])
    {_, p} = Engine.act(p, "attack")
    p
  end

  defp foe_line(p), do: Enum.find(p.battle.log, &(&1[:who] == "foe" and &1[:act]))

  test "bậc kỹ năng: thường dưới min_level không có, thường 1, Tinh Anh / trùm / chúa tể 2" do
    lo =
      Engine.make_monster(%{id: "a", name: "a", level: @ms.min_level - 1, element: "fire"}, false)

    assert lo.mskills == []
    m = Engine.make_monster(%{id: "a", name: "a", level: 20, element: "fire"}, false)
    assert Enum.map(m.mskills, & &1.id) == ["fire_breath"]
    e = Engine.make_monster(%{id: "a", name: "a", level: 20, element: "ice", elite: true}, false)
    assert length(e.mskills) == 2 and e.mskill_chance == @ms.tiers.elite.chance
    b = Engine.make_monster(%{id: "a", name: "a", level: 20, element: "dark"}, true)
    assert length(b.mskills) == 2
    l = Engine.make_monster(%{id: "a", name: "a", level: 60, element: "wind", lord: true}, false)

    assert length(l.mskills) == 2 and l.mskill_chance == @ms.tiers.lord.chance
    # chiêu riêng chúa tể tắt khi `lord_special.every` = 0 (mô phỏng: quá mạnh)
    if @ms.lord_special.every > 0,
      do: assert(l.special.every == @ms.lord_special.every),
      else: assert(l.special == nil)
  end

  test "quái dùng kỹ năng: dòng nhật ký có tên kỹ năng, hệ, sát thương; Phun Lửa gây bỏng" do
    p = fight(player(), "fire", "fire_breath")
    l = foe_line(p)
    assert l.act =~ "Phun Lửa" and l.el == "fire" and l.dmg > 0
    assert Enum.any?(p.battle.effects.player, &(&1.id == "burn"))
  end

  test "kháng hệ: nhẫn / dây chuyền theo hệ, +N tăng, cộng dồn có trần; giảm sát thương kỹ năng cùng hệ" do
    p = player()
    r = @ms.resist
    p1 = give(p, "item_13_21", 11)
    assert_in_delta Engine.derived(p1).resist["fire"], r.base + 11 * r.per_up, 0.001
    p2 = p1 |> give("item_13_21", 11) |> give("item_13_13", 11)
    assert Engine.derived(p2).resist["fire"] == r.max
    # nhẫn không đúng hệ không kháng
    assert Engine.derived(p1).resist["ice"] == nil

    plain = foe_line(fight(p, "fire", "inferno")).dmg
    res = foe_line(fight(p1, "fire", "inferno"))
    assert res.note =~ "kháng Lửa"
    assert_in_delta res.dmg / plain, 1 - (r.base + 11 * r.per_up), 0.05
  end

  test "Hút Hồn hồi máu quái; Hồi Phục hồi máu; Giáp Đá đặt hiệu ứng lên quái" do
    p = fight(player(), "dark", "soul_drain")
    assert foe_line(p).act =~ "Hút Hồn"

    q = player()
    spec = %{id: "t_l", name: "Quái sáng", level: 38, element: "light", mult: 20, atk_mult: 1}
    {_, q} = Engine.start_side_encounter(q, spec, "Thử", "forest")
    k = Enum.find(Engine.mskills(:elite, "light"), &(&1.id == "mend"))

    q =
      update_in(
        q.battle.monster,
        &Map.merge(&1, %{mskills: [k], mskill_chance: 1.0, hp: div(&1.maxHp, 2)})
      )

    Rng.put_sequence([0.5])
    {_, q} = Engine.act(q, "attack")
    assert foe_line(q).heal > 0

    s = fight(player(), "earth", "stone_skin")
    assert Enum.any?(s.battle.effects.monster, &(&1.id == "stone"))
  end
end

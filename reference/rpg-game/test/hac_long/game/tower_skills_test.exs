defmodule HacLong.Game.TowerSkillsTest do
  @moduledoc "Phase 3 (B-29): kỹ năng tháp mở theo kỷ lục tháp, bộ kỹ năng mang vào trận, nguyên tố, tác dụng mới."
  use ExUnit.Case, async: true

  alias HacLong.Game.{Commands, Data, Elements, Engine, Rng}

  setup do
    on_exit(&Rng.clear/0)
  end

  defp hero(best) do
    {:ok, p} = Engine.new_player("Tháp", "dk")

    Map.merge(p, %{
      level: 50,
      stats: %{str: 300, agi: 100, vit: 200, ene: 200},
      mp: 5000,
      tower_best: best
    })
  end

  defp tskill(cls, n), do: Enum.at(Data.class(cls).tower_skills, n - 1)

  # trận với quái cấp `lv`, nguyên tố `el` (nil: theo cấp), máu rất nhiều để không chết
  defp fight(p, lv, el \\ nil, hp \\ 1_000_000) do
    {_, p} = Engine.start_battle(p, 0, false)
    m = Engine.make_monster(%{id: "x", name: "Bia", level: lv, element: el}, false)
    put_in(p.battle.monster, Map.merge(m, %{maxHp: hp, hp: hp}))
  end

  test "mỗi lớp 10 kỹ năng tháp, tầng 10…100, hệ số tăng dần, nguyên tố hợp lệ" do
    for {cls, c} <- Data.classes() do
      ts = c.tower_skills
      assert Enum.map(ts, & &1.floor) == Enum.map(1..10, &(&1 * 10)), cls

      assert ts
             |> Enum.map(& &1.mult)
             |> Enum.chunk_every(2, 1, :discard)
             |> Enum.all?(fn [a, b] -> b > a end)

      assert Enum.all?(ts ++ c.skills, &(&1.element in Elements.list()))
    end
  end

  test "mở theo kỷ lục tháp; mặc định RULES.tower_skills.loadout (5) kỹ năng mạnh nhất; chọn bộ kỹ năng" do
    assert length(Engine.available_skills(hero(0))) == 3
    p = hero(35)
    ids = Enum.map(Engine.available_skills(p), & &1.id)
    assert length(ids) == 6
    loadout = HacLong.Game.Data.rules().tower_skills.loadout
    assert loadout == 5
    assert Enum.map(Engine.skills(p), & &1.id) == Enum.take(ids, -loadout)

    pick = [tskill("dk", 1).id, "twisting_slash"]
    assert {%{ok: true}, p2} = Commands.run(p, %{"act" => "skill_set", "ids" => pick})
    assert Enum.map(Engine.skills(p2), & &1.id) == pick
    assert Engine.view(p2).skillSet == pick

    assert {%{ok: false}, _} = Engine.set_skills(p, [tskill("dk", 5).id])
    assert {%{ok: false}, _} = Engine.set_skills(p, ids |> Enum.take(loadout + 1))
    assert {%{ok: false}, _} = Engine.set_skills(p, ["twisting_slash", "twisting_slash"])
    # chỉ dùng được kỹ năng trong bộ
    p3 = fight(p2, 50)
    assert {%{ok: false}, _} = Engine.act(p3, "skill", "falling_slash")
  end

  test "nguyên tố: khắc +strong, bị khắc −weak, quái mang nguyên tố theo cấp" do
    r = Elements.rules()
    assert Elements.mult("fire", "ice") == {1 + r.strong, :strong}
    assert Elements.mult("ice", "fire") == {1 - r.weak, :weak}
    assert Elements.mult("ice", "earth") == {1, nil}
    assert Elements.mult("lightning", "fire") == {1 + r.strong, :strong}
    assert Elements.mult("fire", "lightning") == {1 - r.weak, :weak}
    assert Engine.make_monster(%{id: "x", name: "x", level: 1}, false).element == "earth"

    # cùng kỹ năng gió (Phong Trảm): đánh quái Đất (khắc) mạnh hơn quái Băng (bị khắc)
    p = hero(10)

    {:ok, p} =
      then(Engine.set_skills(p, [tskill("dk", 1).id]), fn {%{ok: true}, p} -> {:ok, p} end)

    dmg = fn el ->
      Rng.put_sequence([0.99, 0.5])
      q = fight(p, 50, el)
      {_, q} = Engine.act(q, "skill", tskill("dk", 1).id)
      1_000_000 - q.battle.monster.hp
    end

    strong = dmg.("earth")
    weak = dmg.("ice")
    assert strong > weak
    assert_in_delta strong / weak, (1 + r.strong) / (1 - r.weak), 0.1
  end

  test "khiên hấp thụ sát thương; bất tử cứu một lần; phá giáp; hút máu; nhiều đòn" do
    # Hộ Thể (khiên = 100% máu tối đa)
    p = hero(100)

    {_, p} =
      Engine.set_skills(p, [
        tskill("dk", 3).id,
        tskill("dk", 9).id,
        tskill("dk", 2).id,
        tskill("dk", 7).id
      ])

    d = Engine.derived(p)
    Rng.put_sequence([0.99, 0.5])
    q = fight(p, 50)
    hp0 = q.hp
    {_, q} = Engine.act(q, "skill", tskill("dk", 3).id)
    assert q.hp == hp0
    assert Enum.any?(q.battle.log, &(&1.text =~ "Khiên đỡ"))

    # Bất Tử: máu 1, quái đánh chết → đứng dậy
    Rng.put_sequence([0.99, 0.5])
    q = %{fight(p, 50) | hp: 1}
    {_, q} = Engine.act(q, "skill", tskill("dk", 9).id)
    assert q.hp == round(d.maxHp * tskill("dk", 9).buff.power)
    refute q.battle.over

    # Đâm Xuyên Giáp: quái bị phá giáp
    Rng.put_sequence([0.99, 0.5])
    {_, q} = Engine.act(fight(p, 50), "skill", tskill("dk", 2).id)
    assert Enum.any?(q.battle.effects.monster, &(&1.id == "sunder"))

    # Long Huyết: hút máu
    Rng.put_sequence([0.99, 0.5])
    q = %{fight(p, 50) | hp: 10}
    {_, q} = Engine.act(q, "skill", tskill("dk", 7).id)
    assert Enum.any?(q.battle.log, &(&1.text =~ "Hút"))

    # Song Phong Kiếm: 2 đòn
    {_, p} = Engine.set_skills(p, [tskill("dk", 6).id])
    Rng.put_sequence([0.99, 0.5])
    {_, q} = Engine.act(fight(p, 50), "skill", tskill("dk", 6).id)
    assert Enum.any?(q.battle.log, &(&1.text =~ "(2 đòn)"))
  end
end

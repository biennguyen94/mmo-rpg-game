defmodule HacLong.Bots.BrainSkillTest do
  # DECISIONS "Bot leo Tháp, đột phá, bộ kỹ năng"
  use ExUnit.Case, async: true

  alias HacLong.Bots.Brain
  alias HacLong.Game.{Data, Engine, Mastery}

  @f Data.rules().bots.forge
  @m Mastery.rules()

  defp player(attrs \\ %{}) do
    {:ok, p} = Engine.new_player("Bot", "dw")
    p = Map.merge(p, Map.merge(%{level: 50, gold: 1_000_000}, attrs))
    %{p | hp: Engine.derived(p).maxHp}
  end

  # mọi kỹ năng đang mang: cấp 4, đủ điểm lên 5 (kẹt ở mốc đột phá)
  defp stuck(p) do
    m = Map.new(Engine.skills(p), &{&1.id, %{lv: 4, xp: Mastery.need(5) + 10}})
    Map.put(p, :skill_mastery, m)
  end

  test "kẹt ở mốc đột phá: có Bí Kíp thì dùng Bí Kíp, không thì Ngọc Tâm Linh khi còn dư" do
    p = player() |> stuck()
    cost = Mastery.break_cost(5)
    assert Brain.skill_job(%{p | inv: %{}}) == nil

    assert {nil, %{"act" => "skill_break", "pay" => "item"}} =
             Brain.skill_job(%{p | inv: %{@m.item => cost.cost, @m.alt_item => 99}})

    assert {nil, %{"act" => "skill_break", "pay" => "alt"}} =
             Brain.skill_job(%{p | inv: %{@m.alt_item => cost.alt + @f.spare}})

    # không dư Ngọc Tâm Linh (để dành ép đồ): chưa đột phá
    assert Brain.skill_job(%{p | inv: %{@m.alt_item => cost.alt}}) == nil

    # đột phá thật: lên cấp
    {r, p2} =
      Engine.set_skills(p, Enum.map(Engine.skills(p), & &1.id))
      |> elem(1)
      |> then(&%{&1 | inv: %{@m.item => cost.cost}})
      |> then(fn q ->
        {nil, cmd} = Brain.skill_job(q)
        HacLong.Game.Commands.run(q, cmd)
      end)

    assert r.ok
    assert Enum.any?(Engine.skills(p2), &(Mastery.level(p2, &1.id) >= 5))
  end

  test "mở kỹ năng Tháp: đổi bộ kỹ năng theo loadout (giữ kỹ năng hồi máu / hút máu nếu có)" do
    p = player()
    assert Brain.skill_job(p) == nil or match?({nil, %{"act" => "skill_set"}}, Brain.skill_job(p))
    p = Map.put(p, :tower_best, 100)
    ids = Brain.loadout(p, Data.rules().tower_skills.loadout)
    assert {nil, %{"act" => "skill_set", "ids" => ^ids}} = Brain.skill_job(p)
    tower = Enum.map(Data.class("dw").tower_skills, & &1.id)
    assert Enum.any?(ids, &(&1 in tower))

    # đã đổi rồi: thôi
    {_, p} = Engine.set_skills(p, ids)
    assert Brain.skill_job(p) == nil
  end

  test "tới lượt leo Tháp: đi trước câu cá lúc rảnh" do
    # cấp 45 (cấp tối đa thì đi chuyển sinh trước); 0 vàng: không đi mua vé sự kiện đang mở (kết quả không theo giờ chạy test)
    p =
      player(%{
        level: 45,
        gold: 0,
        inv: %{"potion_l" => 50, "mana_l" => 50},
        pos: %{map: "village", x: 20, y: 8}
      })

    p = Engine.set_skills(p, Brain.loadout(p, 5)) |> elem(1)
    %{at: {x, y}} = Enum.find(HacLong.World.Maps.get("village").npcs, &(&1.role == "tower"))
    p = %{p | pos: %{map: "village", x: x, y: y + 1}}
    assert %{"act" => "tower_enter"} = Brain.decide(p, nil, %{tower_due: true, seed: 2})
  end
end

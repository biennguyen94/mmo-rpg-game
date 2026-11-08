defmodule HacLong.Game.QuickFightTest do
  @moduledoc "DECISIONS \"Đánh nhanh theo combo\": combo danh sách ưu tiên, bước once, uống bình, rời trận khi xong."
  use ExUnit.Case, async: true

  alias HacLong.Game.{Commands, Engine, QuickFight, Rng}

  setup do
    on_exit(&Rng.clear/0)
    :ok
  end

  defp player do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Qf", "cls" => "dk"})
    p = %{p | level: 40, stats: %{str: 200, agi: 60, vit: 150, ene: 30}}
    d = Engine.derived(p)
    p |> Map.put(:hp, d.maxHp) |> Map.put(:mp, d.maxMp)
  end

  defp fight(p) do
    spec = %{id: "t_q", name: "Quái thử", level: 20, element: "earth", mult: 30, atk_mult: 0.1}
    {_, p} = Engine.start_side_encounter(p, spec, "Thử", "forest")
    p
  end

  defp skills(p), do: Enum.map(Engine.skills(p), & &1.id)

  test "lưu combo: chỉ đòn thường / kỹ năng đang mang, tối đa max_steps; bật / tắt lưu trong auto_cfg" do
    p = player()
    [k | _] = skills(p)

    {%{ok: true}, p} =
      QuickFight.set_combo(p, [%{"id" => k, "once" => true}, %{"id" => "attack"}])

    assert QuickFight.combo(p) == [
             %{"id" => k, "once" => true},
             %{"id" => "attack", "once" => false}
           ]

    assert {%{ok: false}, _} = QuickFight.set_combo(p, [%{"id" => "khong_co"}])
    too_many = for _ <- 1..(QuickFight.max_steps() + 1), do: %{"id" => "attack"}
    assert {%{ok: false}, _} = QuickFight.set_combo(p, too_many)

    refute QuickFight.on?(p)
    {_, p} = QuickFight.toggle(p, true)
    assert QuickFight.on?(p) and p.auto_cfg["combo"] != nil
  end

  test "chỉ chạy khi bật, đang trận với quái, chưa bấm Đánh tay, không bật Tự đánh" do
    p = player()
    {_, on} = QuickFight.toggle(p, true)
    refute QuickFight.active?(on)
    b = fight(on)
    assert QuickFight.active?(b)
    {_, m} = QuickFight.manual(b)
    refute QuickFight.active?(m)
    refute QuickFight.active?(Map.put(b, :auto, %{}))
    {_, off} = QuickFight.toggle(b, false)
    refute QuickFight.active?(off)
  end

  test "danh sách ưu tiên: bước đầu dùng được; hồi chiêu thì sang bước sau; trận xong thì rời" do
    p = player()
    [k1, k2 | _] = skills(p)
    {_, p} = QuickFight.set_combo(p, [%{"id" => k1}, %{"id" => k2}, %{"id" => "attack"}])
    {_, p} = QuickFight.toggle(p, true)
    b = fight(p)
    assert QuickFight.decide(b) == %{"act" => "skill", "skill" => k1}

    Rng.put_sequence([0.5])
    {_, b2} = Engine.act(b, "skill", k1)

    if Engine.cooldown(b2, k1) > 0,
      do: assert(QuickFight.decide(b2) == %{"act" => "skill", "skill" => k2})

    assert QuickFight.decide(put_in(b.battle.over, true)) == %{"act" => "leave"}
  end

  test "bước once bỏ qua khi hiệu ứng buff còn; máu thấp thì uống bình" do
    p = player()
    buff = Enum.find(Engine.skills(p), &(&1[:effect] in ~w(war_cry guard shadow_step)))

    if buff do
      {_, p} = QuickFight.set_combo(p, [%{"id" => buff.id, "once" => true}, %{"id" => "attack"}])
      b = fight(p)
      assert QuickFight.decide(b)["skill"] == buff.id
      Rng.put_sequence([0.5])
      {_, b2} = Engine.act(b, "skill", buff.id)
      # còn hiệu ứng (kể cả đã hết hồi chiêu) thì không buff lại
      b2 = put_in(b2.battle.cds, [])
      if Engine.buff_active?(b2, buff), do: assert(QuickFight.decide(b2) == %{"act" => "attack"})
    end

    low = fight(Engine.add_item(%{p | hp: 10}, "potion_l", 3))
    assert QuickFight.decide(low) == %{"act" => "potion"}
  end
end

defmodule HacLong.Game.MasteryTest do
  # DECISIONS "Thông thạo kỹ năng": cấp 1..10, thông số trong dữ liệu là của cấp 10
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine, Mastery, Rng}

  @r Data.rules().skill_mastery

  setup do
    on_exit(&Rng.clear/0)
  end

  defp player(cls \\ "dk") do
    {:ok, p} = Engine.new_player("Luyện", cls)
    %{p | level: 30}
  end

  defp sk(p, id), do: Enum.find(Engine.available_skills(p), &(&1.id == id))

  test "cấp 1 yếu hơn cấp 10: hệ số, MP, hồi chiêu" do
    p = player()
    k = sk(p, "twisting_slash")
    full = Mastery.maxed(p)
    assert Mastery.level(p, k.id) == 1 and Mastery.level(full, k.id) == @r.max
    assert Mastery.mult(1) == @r.mult_min and Mastery.mult(@r.max) == 1
    assert Engine.skill_mp(p, k) == round(Engine.skill_mp(full, k) * @r.mp_low)
    assert Engine.skill_cd(p, k) == k.cooldown + @r.cd_low
    assert Engine.skill_cd(full, k) == k.cooldown

    # cùng một đòn (cùng số ngẫu nhiên) vào quái máu rất nhiều: cấp 1 ≈ 75 % cấp 10
    hit = fn p ->
      {_, p} = Engine.start_battle(p, 0, false)

      p =
        put_in(p.battle.monster, %{
          p.battle.monster
          | hp: 10_000_000,
            maxHp: 10_000_000,
            level: 30
        })

      Rng.put_sequence([0.99, 0.5])
      {_, q} = Engine.act(%{p | mp: 9_999}, "skill", "twisting_slash")
      10_000_000 - q.battle.monster.hp
    end

    assert_in_delta hit.(p) / hit.(full), @r.mult_min, 0.03
  end

  test "luyện bằng đánh quái: điểm theo cấp quái, trùm nhiều hơn, tự đánh một nửa, đánh người không tính" do
    p = player() |> Map.put(:battle, %{log: []})
    k = sk(p, "twisting_slash")
    m = %{level: 30, boss: false}
    assert Mastery.entry(Mastery.gain(p, k, m), k.id).xp == @r.points
    assert Mastery.entry(Mastery.gain(Map.put(p, :auto, true), k, m), k.id).xp == @r.points_auto

    assert Mastery.entry(Mastery.gain(p, k, %{m | boss: true}), k.id).xp ==
             @r.points * @r.boss_mult

    assert Mastery.entry(Mastery.gain(p, k, %{m | level: 30 - @r.level_gap - 1}), k.id).xp == 0
    assert Mastery.entry(Mastery.gain(p, k, Map.put(m, :pvp, 2)), k.id).xp == 0

    # đủ điểm thì lên cấp, có dòng nhật ký
    p = Enum.reduce(1..div(hd(@r.need), @r.points), p, fn _, p -> Mastery.gain(p, k, m) end)
    assert Mastery.level(p, k.id) == 2
    assert Enum.any?(p.battle.log, &(&1.text =~ "#{k.name} lên cấp 2"))
  end

  test "dùng kỹ năng trong trận thật cộng điểm" do
    p = player()
    {_, p} = Engine.start_battle(p, 0, false)

    p =
      put_in(p.battle.monster, %{p.battle.monster | hp: 10_000_000, maxHp: 10_000_000, level: 30})

    {%{ok: true}, q} = Engine.act(%{p | mp: 9_999}, "skill", "twisting_slash")
    assert Mastery.entry(q, "twisting_slash").xp == @r.points
  end

  test "đột phá cấp 5 bằng Bí Kíp hoặc Ngọc Tâm Linh" do
    p = player() |> Map.put(:battle, %{log: []})
    k = sk(p, "twisting_slash")
    m = %{level: 30, boss: false}
    need5 = Mastery.need(5)
    p = Enum.reduce(1..div(need5, @r.points), p, fn _, p -> Mastery.gain(p, k, m) end)
    # đủ điểm cấp 5 nhưng dừng ở 4 chờ đột phá
    assert Mastery.level(p, k.id) == 4
    assert Mastery.view(p)[k.id].brk == %{cost: 1, alt: 5}
    assert {%{ok: false}, _} = Mastery.break_through(p, k.id, "item")

    {%{ok: true}, q} =
      Mastery.break_through(%{p | inv: Map.put(p.inv, "bi_kip", 1)}, k.id, "item")

    assert Mastery.level(q, k.id) == 5 and q.inv["bi_kip"] == nil

    {%{ok: true}, q} =
      Mastery.break_through(%{p | inv: Map.put(p.inv, "jewel_soul", 6)}, k.id, "alt")

    assert Mastery.level(q, k.id) == 5 and q.inv["jewel_soul"] == 1

    # chưa tới mốc thì không đột phá được
    assert {%{ok: false}, _} =
             Mastery.break_through(%{player() | inv: %{"bi_kip" => 3}}, k.id, "item")
  end

  test "nhân vật cũ (chưa có dữ liệu): kỹ năng đang có lên cấp tối đa; nạp lại giữ cấp" do
    p = %{player() | skill_mastery: nil}
    q = Mastery.legacy(p)
    for k <- Engine.available_skills(p), do: assert(Mastery.level(q, k.id) == @r.max)
    assert Mastery.legacy(player()).skill_mastery == %{}

    saved = q.skill_mastery |> Jason.encode!() |> Jason.decode!()
    assert Mastery.load(saved) == q.skill_mastery
  end

  test "trùm rơi Bí Kíp (tỉ lệ drop.boss)" do
    {:ok, p} = Engine.new_player("Trum", "dk")
    p = %{p | level: 50, stats: Map.new(p.stats, fn {k, v} -> {k, v * 20} end)}

    got =
      for _ <- 1..300 do
        {_, b} = Engine.start_battle(p, 0, true)
        b = put_in(b.battle.monster, %{b.battle.monster | hp: 1})

        q =
          Enum.reduce_while(1..10, b, fn _, b ->
            if b.battle.over, do: {:halt, b}, else: {:cont, elem(Engine.act(b, "attack"), 1)}
          end)

        assert q.battle.result == "win"
        Map.get(q.inv, "bi_kip", 0)
      end

    rate = Enum.sum(got) / 300
    assert_in_delta rate, @r.drop.boss, 0.1
  end
end

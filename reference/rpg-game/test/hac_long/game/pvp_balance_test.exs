defmodule HacLong.Game.PvpBalanceTest do
  # DECISIONS "Cân bằng đánh người": RULES.pvp khi đối thủ là người
  use ExUnit.Case, async: true

  alias HacLong.Arena
  alias HacLong.Game.{Commands, Engine, Rng}

  setup do
    on_exit(&Rng.clear/0)
  end

  defp hero(name, cls) do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => cls})
    # thông số kỹ năng trong dữ liệu là của cấp thông thạo tối đa
    %{p | level: 40, stats: Map.new(p.stats, fn {k, v} -> {k, v * 4} end)}
    |> HacLong.Game.Mastery.maxed()
  end

  # một đòn của `p` vào bản sao `foe` (pvp: uid hoặc nil = coi như quái); không né, không chí mạng
  defp hit(p, foe, pvp, act, skill) do
    m = %{foe | pvp: pvp, dodge: 0.0, crit: 0.0, hp: 1_000_000, maxHp: 1_000_000}
    {_, p} = Engine.start_with_monster(%{p | pet: nil, mp: 9_999}, 1, m)
    {_, p} = Engine.act(p, act, skill)
    1_000_000 - p.battle.monster.hp
  end

  test "chí mạng, né thu nhỏ theo tỉ lệ (không chặn trần)" do
    r = Engine.pvp_rules()
    assert Engine.pvp_crit(0.7) == 0.7 * r.crit_rate_mult
    assert Engine.pvp_crit(0.6) > Engine.pvp_crit(0.4)
    assert_in_delta Engine.pvp_crit_mult(2.5), 1 + 1.5 * r.crit_bonus_mult, 1.0e-9
  end

  test "đòn thường và kỹ năng lên người × dmg_mult" do
    a = hero("Atk", "dk")
    foe = Arena.opponent(hero("Def", "dk"), 2)
    k = hd(Engine.skills(a)).id

    for {act, skill} <- [{"attack", nil}, {"skill", k}] do
      Rng.put_sequence([0.99, 0.5])
      monster = hit(a, foe, nil, act, skill)
      Rng.put_sequence([0.99, 0.5])
      person = hit(a, foe, 2, act, skill)
      # đối thủ Kiếm Sĩ: dmg_mult × class_taken.dk
      assert_in_delta person / monster, Engine.pvp_taken("dk"), 0.02
    end
  end

  test "vừa thoát choáng thì kháng choáng stun_immune lượt; tự đánh chọn kỹ năng mạnh nhất" do
    a = hero("Choang", "dk")
    foe = %{Arena.opponent(hero("Bia", "dk"), 2) | dodge: 0.0, hp: 1_000_000, maxHp: 1_000_000}
    {_, p} = Engine.start_with_monster(%{a | pet: nil, mp: 9_999}, 1, foe)
    Rng.put_sequence([0.99])

    # Trảm Choáng: quái mất lượt, lượt sau đánh lại thì kháng
    {_, p} = Engine.act(p, "skill", "falling_slash")
    assert Enum.any?(p.battle.log, &(&1.text =~ "bị choáng, không đánh được"))
    p = p |> put_in([:battle, :cds], []) |> Map.put(:mp, 9_999)
    {_, p} = Engine.act(p, "skill", "falling_slash")
    assert List.last(Enum.filter(p.battle.log, &(&1.kind == "info"))).text =~ "kháng được"

    assert {"skill", _} = Engine.auto_strike(%{p | mp: 9_999} |> put_in([:battle, :cds], []))
    assert {"attack", nil} = Engine.auto_strike(%{p | mp: 0})
  end

  test "hệ số theo lớp: lớp ít máu nhận ít hơn" do
    assert Engine.pvp_taken("mg") < Engine.pvp_taken("dw")
    assert Engine.pvp_taken("dw") < Engine.pvp_taken("dk")
    assert Engine.pvp_taken(nil) == Engine.pvp_rules().dmg_mult
  end

  test "đấu trường: đối thủ máy đánh bằng kỹ năng thật, có thể gây choáng, trận kết thúc bình thường" do
    a = hero("Khach", "dk")
    b = hero("Chu", "dk")
    {_, p} = Engine.start_with_monster(%{a | pet: nil}, 1, Arena.opponent(b, 2))
    p = put_in(p.battle[:mirror], Engine.mirror(%{b | pet: nil}, Arena.opponent(a, 1)))

    p =
      Enum.reduce_while(1..60, p, fn _, p ->
        if p.battle.over do
          {:halt, p}
        else
          {act, k} = Engine.auto_strike(p)
          {:cont, elem(Engine.act(p, act, k), 1)}
        end
      end)

    assert p.battle.over and p.battle.result in ~w(win lose)
    assert Enum.any?(p.battle.log, &(&1.text =~ "✨ Chu dùng"))
  end
end

defmodule Mu.World.BossTest do
  @moduledoc """
  P6-M5 trong MapServer riêng (tick tay, RNG seed): quái event sinh / thu theo nhãn, không hồi
  sinh; boss đánh vùng (bán kính 2, tối đa 6 người, nhịp 3 s); boss chết → EXP / Zen chia theo
  phần sát thương (≥ 1 %), top 3 mỗi người 1 jewel dưới đất thuộc riêng mình; quái vàng × 5.
  """
  use ExUnit.Case, async: true

  alias Mu.Game.{Data, Engine}
  alias Mu.World.MapServer

  setup do
    topic = "boss_test:#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(Mu.PubSub, topic)

    pid =
      start_supervised!(
        {MapServer,
         map_id: "lorencia",
         name: nil,
         tick: :manual,
         topic: topic,
         seed: 7,
         spawn_monsters: false},
        id: :boss_map
      )

    %{s: pid}
  end

  defp join(s, id, {x, y}) do
    c = %{class: "DK", level: 20, strength: 80, agility: 30, vitality: 60, energy: 10}
    stats = Engine.derived(c)

    {:ok, _} =
      MapServer.join(
        s,
        %{
          character_id: id,
          name: id,
          class: "DK",
          level: 20,
          hp: stats.hp_max,
          mp: stats.mp_max,
          x: x,
          y: y,
          stats: stats,
          skills: Engine.skills(c)
        },
        self()
      )
  end

  defp st(s), do: MapServer.debug_state(s)

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end

  test "quái vàng: HP / EXP / Zen × 5 so với quái gốc, rơi jewel 10 %" do
    g = Data.monster("golden_budge_dragon")
    b = Data.monster("budge_dragon")

    assert {g["hp"], g["experience"], g["zenMax"]} ==
             {b["hp"] * 5, b["experience"] * 5, b["zenMax"] * 5}

    assert g["golden"] and g["event"]

    jewels = Data.drops("golden_goblin")["groups"] |> Enum.find(&(&1["id"] == "jewels"))
    assert jewels["chance"] == 0.10
  end

  test "sinh / thu theo nhãn; quái event chết không hồi sinh", %{s: s} do
    area = %{"x" => 40, "y" => 2, "w" => 22, "h" => 14}
    {:ok, ids} = MapServer.spawn_event(s, "golden_invasion", "golden_budge_dragon", 8, area)
    assert length(ids) == 8
    ms = st(s).monsters
    assert Enum.all?(ids, &(ms[&1].event == "golden_invasion" and ms[&1].hp == 330))
    assert_receive {:map_event, "spawn", %{golden: true, boss: false}}

    [id | _] = ids
    {x, y} = {ms[id].x, ms[id].y}
    join(s, "a", {x - 1, y})
    MapServer.debug_update(s, fn st -> update_in(st.monsters[id], &%{&1 | hp: 1}) end)

    Enum.find(1..40, fn _ ->
      MapServer.use_skill(s, "a", "basic_attack", id, "r")
      st(s).monsters[id].state == "dead" or (MapServer.tick(s, 20) && false)
    end) || flunk("không hạ được")

    assert_receive {:map_reward, %{exp: _, template: "golden_budge_dragon"}}
    assert st(s).monsters[id].respawn_at == nil
    MapServer.tick(s, 400)
    assert st(s).monsters[id].state == "dead"

    {:ok, 8} = MapServer.despawn_event(s, "golden_invasion")
    assert st(s).monsters == %{}
  end

  test "boss đánh vùng: trúng mọi người trong bán kính 2 (tối đa 6), mỗi 3 s", %{s: s} do
    {:ok, [bid]} =
      MapServer.spawn_event(s, "boss_t", "bull_fighter_lord", 1, %{x: 34, y: 24, w: 1, h: 1})

    for {id, i} <- Enum.with_index(~w(a b c d e f g h)), do: join(s, id, {35 + rem(i, 3), 24})
    # người ở xa (ngoài bán kính 2) không bị trúng
    join(s, "far", {45, 24})
    MapServer.debug_update(s, fn st -> update_in(st.monsters[bid], &%{&1 | target: "a"}) end)
    flush()
    MapServer.tick(s, 4)

    hits = for {:map_event, "combat", %{attacker: ^bid, target: t}} <- drain(), do: t
    assert length(hits) == 6
    refute "p_far" in hits

    # trong 3 s tiếp theo (60 tick) không đánh lần nữa, sau đó đánh tiếp
    MapServer.tick(s, 50)
    assert for({:map_event, "combat", %{attacker: ^bid}} <- drain(), do: 1) == []
    MapServer.tick(s, 20)
    assert for({:map_event, "combat", %{attacker: ^bid}} <- drain(), do: 1) != []
  end

  test "boss chết: chia EXP 6000 / Zen 30000 theo sát thương (≥ 1 %), top 3 có jewel riêng",
       %{s: s} do
    {:ok, [bid]} =
      MapServer.spawn_event(s, "boss_t", "bull_fighter_lord", 1, %{x: 34, y: 24, w: 1, h: 1})

    for {id, x} <- [{"a", 35}, {"b", 33}, {"c", 34}, {"d", 36}], do: join(s, id, {x, 25})

    MapServer.debug_update(s, fn st ->
      update_in(
        st.monsters[bid],
        &%{&1 | hp: 1, damage_by: %{"a" => 10_000, "b" => 6_000, "c" => 3_900, "d" => 100}}
      )
    end)

    flush()

    Enum.find(1..40, fn _ ->
      MapServer.use_skill(s, "a", "basic_attack", bid, "r")
      st(s).monsters[bid].state == "dead" or (MapServer.tick(s, 20) && false)
    end) || flunk("không hạ được")

    rewards = for {:map_reward, r} <- drain(), do: {r.exp, r.zen}
    # a ≈ 50 %, b 30 %, c 19,5 %; d 0,5 % < 1 % → không có
    assert length(rewards) == 3
    {top_exp, _} = Enum.max(rewards)
    assert top_exp in 2999..3000
    assert Enum.sum(Enum.map(rewards, &elem(&1, 1))) <= 30_000

    jewels =
      for {_, g} <- st(s).ground, String.starts_with?(g.template_id, "jewel_"), do: g.owner

    assert Enum.sort(jewels) |> Enum.uniq() |> length() >= 3
    assert "p_d" not in jewels and "d" not in jewels
  end

  defp drain(acc \\ []) do
    receive do
      m -> drain([m | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end

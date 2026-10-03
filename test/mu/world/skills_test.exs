defmodule Mu.World.SkillsTest do
  @moduledoc "P2-M3: skill theo class trong MapServer (tick tay, RNG seed cố định)."
  use ExUnit.Case, async: true

  alias Mu.Game.{Data, Engine}
  alias Mu.World.{Maps, MapServer}

  setup do
    topic = "skills_test:#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(Mu.PubSub, topic)

    pid =
      start_supervised!(
        {MapServer, map_id: "lorencia", name: nil, tick: :manual, topic: topic, seed: 7},
        id: :skills_map
      )

    %{s: pid}
  end

  defp char(class, level) do
    c = Data.class(class)

    %{
      class: class,
      level: level,
      strength: c["strength"],
      agility: c["agility"],
      vitality: c["vitality"],
      energy: c["energy"]
    }
  end

  defp join(s, id, class, {x, y}, opts \\ []) do
    c = char(class, Keyword.get(opts, :level, 30))
    stats = Engine.derived(c)

    {:ok, _} =
      MapServer.join(
        s,
        %{
          character_id: id,
          name: id,
          class: class,
          level: c.level,
          hp: Keyword.get(opts, :hp, stats.hp_max),
          mp: Keyword.get(opts, :mp, stats.mp_max),
          x: x,
          y: y,
          stats: stats,
          skills: Engine.skills(c)
        },
        self()
      )

    :ok
  end

  defp place(s, placed) do
    MapServer.debug_update(s, fn st ->
      monsters =
        for {id, {x, y}} <- placed, into: %{} do
          {id, %{st.monsters[id] | x: x, y: y, home: {x, y}, hp: 1000, hp_max: 1000}}
        end

      %{st | monsters: monsters}
    end)
  end

  defp st(s), do: MapServer.debug_state(s)
  defp skill(s, id, sk, target), do: MapServer.use_skill(s, id, sk, target, "r-#{sk}")

  defp ready(s, id),
    do: MapServer.debug_update(s, fn st -> put_in(st.players[id].cooldowns, %{}) end)

  defp hits(acc \\ []) do
    receive do
      {:map_event, "combat", %{dmg: d} = c}
      when not is_map_key(c, :heal) and not is_map_key(c, :buff) ->
        hits([{c.target, d} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "DW: energy_ball tầm 4, tốn 1 MP; ngoài tầm OUT_OF_RANGE; chưa học → REQUIREMENT_NOT_MET",
       %{s: s} do
    :ok = join(s, "w", "DW", {45, 36}, level: 1)
    place(s, %{"m_1" => {49, 36}})
    mp = st(s).players["w"].mp
    assert :ok = skill(s, "w", "energy_ball", "m_1")
    assert st(s).players["w"].mp == mp - 1
    MapServer.debug_update(s, fn st -> put_in(st.monsters["m_1"].x, 50) end)
    ready(s, "w")
    assert {:error, "OUT_OF_RANGE"} = skill(s, "w", "energy_ball", "m_1")
    assert {:error, "REQUIREMENT_NOT_MET"} = skill(s, "w", "fire_ball", "m_1")
  end

  test "ELF triple_shot: mục tiêu + tối đa 2 quái gần nhất trong 1 ô quanh mục tiêu", %{s: s} do
    :ok = join(s, "e", "ELF", {40, 36})

    place(s, %{
      "m_1" => {45, 36},
      "m_2" => {46, 36},
      "m_3" => {45, 37},
      "m_4" => {44, 35},
      "m_5" => {47, 36}
    })

    assert :ok = skill(s, "e", "triple_shot", "m_1")
    targets = hits() |> Enum.map(&elem(&1, 0))
    assert length(targets) == 3 and hd(targets) == "m_1"
    refute "m_5" in targets
    assert {:error, "INVALID_TARGET"} = skill(s, "e", "triple_shot", {45, 36})
  end

  test "DW flame tại ô: mọi quái trong 2 ô quanh ô chọn", %{s: s} do
    :ok = join(s, "w", "DW", {40, 36})
    place(s, %{"m_1" => {44, 36}, "m_2" => {46, 38}, "m_3" => {47, 36}})
    assert :ok = skill(s, "w", "flame", {44, 37})
    assert hits() |> Enum.map(&elem(&1, 0)) |> Enum.sort() == ["m_1", "m_2"]
  end

  test "DW teleport: tới ô đi được trong tầm 6; tường / xa → lỗi; dùng được trong safe zone", %{
    s: s
  } do
    map = Maps.get("lorencia")
    {sx, sy} = map.player_spawn
    :ok = join(s, "w", "DW", {sx, sy})
    assert Maps.safe?(map, sx, sy)
    assert :ok = skill(s, "w", "teleport", {sx + 3, sy})
    assert {st(s).players["w"].x, st(s).players["w"].y} == {sx + 3, sy}
    ready(s, "w")
    assert {:error, "OUT_OF_RANGE"} = skill(s, "w", "teleport", {sx + 3 + 7, sy})

    {wx, wy} =
      Enum.find(
        for(x <- 0..63, y <- 0..63, do: {x, y}),
        &(not Maps.walkable?(map, elem(&1, 0), elem(&1, 1)))
      )

    assert {:error, "INVALID_TARGET"} = skill(s, "w", "teleport", {wx, wy})
    assert {:error, "INVALID_TARGET"} = skill(s, "w", "teleport", "m_1")
  end

  test "đánh quái trong safe zone bị cấm; heal trong safe zone được", %{s: s} do
    {sx, sy} = Maps.get("lorencia").player_spawn
    :ok = join(s, "e", "ELF", {sx, sy}, hp: 50)
    place(s, %{"m_1" => {sx + 2, sy}})
    assert {:error, "FORBIDDEN"} = skill(s, "e", "basic_attack", "m_1")
    assert :ok = skill(s, "e", "heal", nil)
    assert st(s).players["e"].hp == 50 + 13 + div(0, 1)
  end

  test "ELF heal: bản thân / người khác, không vượt hpMax, combat có heal; quái → INVALID_TARGET",
       %{s: s} do
    :ok = join(s, "e", "ELF", {40, 36}, level: 3)
    :ok = join(s, "k", "DK", {42, 36}, hp: 100)
    assert :ok = skill(s, "e", "heal", "p_k")
    assert_receive {:map_event, "combat", %{target: "p_k", heal: 13, hp: 113, attacker: "p_e"}}
    assert st(s).players["k"].hp == 113
    ready(s, "e")

    MapServer.debug_update(s, fn st ->
      put_in(st.players["k"].hp, st.players["k"].stats.hp_max - 2)
    end)

    assert :ok = skill(s, "e", "heal", "p_k")
    assert_receive {:map_event, "combat", %{target: "p_k", heal: 2}}
    ready(s, "e")
    place(s, %{"m_1" => {44, 36}})
    assert {:error, "INVALID_TARGET"} = skill(s, "e", "heal", "m_1")
    MapServer.debug_update(s, fn st -> put_in(st.players["k"].x, 49) end)
    assert {:error, "OUT_OF_RANGE"} = skill(s, "e", "heal", "p_k")
  end

  test "buff: Greater Defense giảm sát thương quái, báo Session chủ, hết hạn, mất khi chết", %{
    s: s
  } do
    :ok = join(s, "e", "ELF", {40, 36}, level: 12)
    assert :ok = skill(s, "e", "greater_defense", nil)

    assert_receive {:map_buffs, "e",
                    [%{id: "greater_defense", stat: "defense", value: 3, expiresAt: at}]}

    assert_in_delta at, System.os_time(:millisecond) + 60_000, 2_000
    ready(s, "e")
    assert :ok = skill(s, "e", "greater_damage", nil)
    assert_receive {:map_buffs, "e", [_, _]}
    assert map_size(st(s).players["e"].buffs) == 2

    # hết hạn sau durationMs (60 s = 1200 tick); quái để xa
    place(s, %{"m_1" => {57, 43}})
    MapServer.tick(s, 1205)
    assert st(s).players["e"].buffs == %{}
    assert_receive {:map_buffs, "e", []}

    # chết thì mất buff
    ready(s, "e")
    assert :ok = skill(s, "e", "greater_defense", nil)
    assert_receive {:map_buffs, "e", [_]}

    MapServer.debug_update(s, fn st ->
      st
      |> put_in([:monsters, "m_1"], %{st.monsters["m_1"] | x: 41, y: 36, home: {41, 36}})
      |> put_in([:players, "e", :hp], 1)
    end)

    Enum.find(1..200, fn _ ->
      MapServer.tick(s, 1)
      st(s).players["e"].state == "dead"
    end) || flunk("không chết")

    assert st(s).players["e"].buffs == %{}
    assert_receive {:map_buffs, "e", []}
  end

  test "Greater Damage: sát thương tăng đúng giá trị buff" do
    eff = Data.skill("greater_damage")["effect"]

    stats =
      Engine.with_buffs(%{defense: 0}, Engine.add_buff(%{}, "greater_damage", eff["stat"], 5, 1))

    assert stats.damage_bonus == 5
  end

  test "hồi MP energy/40 mỗi giây, có snapshot mp; đã chết không hồi", %{s: s} do
    # DW cấp 1 ENE 30 → 0,75 MP/s
    :ok = join(s, "w", "DW", {40, 36}, level: 1, mp: 10)
    MapServer.debug_update(s, fn st -> %{st | monsters: %{}} end)
    MapServer.tick(s, 20)
    assert st(s).players["w"].mp == 10
    MapServer.tick(s, 20)
    assert st(s).players["w"].mp == 11
    # 6 s × 0,75 = 4,5 → +4
    MapServer.tick(s, 80)
    assert st(s).players["w"].mp == 14

    snaps =
      Stream.repeatedly(fn ->
        receive do
          {:map_event, "snapshot", %{entities: es}} -> es
        after
          0 -> nil
        end
      end)
      |> Enum.take_while(& &1)
      |> List.flatten()

    assert Enum.any?(snaps, &match?(%{id: "p_w", mp: 14}, &1))

    MapServer.debug_update(s, fn st ->
      put_in(st.players["w"].state, "dead") |> put_in([:players, "w", :dead_at], 10_000_000)
    end)

    MapServer.tick(s, 40)
    assert st(s).players["w"].mp == 14
  end
end

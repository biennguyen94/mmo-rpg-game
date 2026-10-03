defmodule Mu.World.CombatTest do
  @moduledoc "Chiến đấu trong MapServer (tick tay, RNG seed cố định)."
  use ExUnit.Case, async: true

  alias Mu.Game.{Config, Engine}
  alias Mu.World.{Maps, MapServer}

  @map Maps.get("lorencia")

  setup do
    topic = "combat_test:#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(Mu.PubSub, topic)

    pid =
      start_supervised!(
        {MapServer, map_id: "lorencia", name: nil, tick: :manual, topic: topic, seed: 42},
        id: :combat_map
      )

    %{s: pid}
  end

  defp dk(level),
    do: %{class: "DK", level: level, strength: 28, agility: 20, vitality: 25, energy: 10}

  defp join(s, id, {x, y}, opts \\ []) do
    c = dk(Keyword.get(opts, :level, 1))
    stats = Engine.derived(c)

    {:ok, info} =
      MapServer.join(
        s,
        %{
          character_id: id,
          name: id,
          class: "DK",
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

    info
  end

  # chỉ giữ các quái `placed` (id → ô), đặt đúng chỗ: test không bị quái khác xen vào
  defp place(s, placed) do
    MapServer.debug_update(s, fn st ->
      monsters =
        for {id, {x, y}} <- placed, into: %{} do
          {id, %{st.monsters[id] | x: x, y: y, home: {x, y}}}
        end

      %{st | monsters: monsters}
    end)
  end

  defp monster(s, id), do: MapServer.debug_state(s).monsters[id]
  defp player(s, id), do: MapServer.debug_state(s).players[id]

  defp set_monster(s, id, changes),
    do:
      MapServer.debug_update(s, fn st -> update_in(st.monsters[id], &Map.merge(&1, changes)) end)

  defp set_player(s, id, changes),
    do: MapServer.debug_update(s, fn st -> update_in(st.players[id], &Map.merge(&1, changes)) end)

  defp attack(s, id, target, rid \\ "r"),
    do: MapServer.use_skill(s, id, "basic_attack", target, rid)

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end

  test "10 Spider sinh trong vùng, ngoài safe zone, ô đi được (G16)" do
    %{monsters: ms} =
      MapServer.debug_state(
        start_supervised!(
          {MapServer, map_id: "lorencia", name: nil, tick: :manual, topic: "x", seed: 1},
          id: :fresh
        )
      )

    assert map_size(ms) == 10
    [%{area: a}] = @map.spawns

    for {id, m} <- ms do
      assert "m_" <> _ = id
      assert m.x in a.x..(a.x + a.w - 1) and m.y in a.y..(a.y + a.h - 1)
      assert Maps.walkable?(@map, m.x, m.y)
      refute Maps.safe?(@map, m.x, m.y)
      assert {m.hp, m.state, m.template_id} == {30, "idle", "spider"}
    end
  end

  test "quái ngủ khi map không có người: không đổi gì, không snapshot", %{s: s} do
    before = MapServer.debug_state(s).monsters
    MapServer.tick(s, 200)
    assert MapServer.debug_state(s).monsters == before
    refute_receive {:map_event, "snapshot", _}, 20
  end

  test "đánh thường: combat {rid, attacker, target, dmg, crit, hp}; cooldown; tầm; mục tiêu sai",
       %{s: s} do
    place(s, %{"m_1" => {50, 36}, "m_2" => {54, 36}})
    join(s, "a", {49, 36})
    flush()

    assert :ok = attack(s, "a", "m_1", "r1")

    assert_receive {:map_event, "combat",
                    %{rid: "r1", attacker: "p_a", target: "m_1", dmg: dmg, crit: false, hp: hp}}

    # DK cấp 1: raw 4..7 − defense 1 → 3..6; trượt = 0
    assert dmg == 0 or dmg in 3..6
    assert hp == 30 - dmg
    # tầm kiểm trước cooldown: m_2 cách 5 ô
    assert {:error, "OUT_OF_RANGE"} = attack(s, "a", "m_2")

    # cooldown 990 ms (G2/§6)
    assert {:error, "COOLDOWN"} = attack(s, "a", "m_1")
    MapServer.tick(s, 19)
    assert {:error, "COOLDOWN"} = attack(s, "a", "m_1")
    MapServer.tick(s, 1)
    assert :ok = attack(s, "a", "m_1")

    MapServer.tick(s, 20)
    assert {:error, "INVALID_TARGET"} = attack(s, "a", "m_99")
    assert {:error, "INVALID_TARGET"} = attack(s, "a", "p_a")
    assert {:error, "INVALID_TARGET"} = attack(s, "khong_co", "m_1")
    # đánh tại chỗ: đang đi thì dừng
    :ok = MapServer.move_to(s, "a", 45, 36)
    assert :ok = attack(s, "a", "m_1")
    assert player(s, "a").path == []
  end

  test "trong safe zone không đánh được (G14)", %{s: s} do
    place(s, %{"m_1" => {50, 36}})
    join(s, "a", {20, 30})

    # đặt quái ngay cạnh (ngoài tường) không được: thử đánh từ trong thị trấn
    set_monster(s, "m_1", %{x: 21, y: 30})
    assert {:error, "FORBIDDEN"} = attack(s, "a", "m_1")
  end

  test "Spider chết: state dead, phần thưởng EXP 10 + Zen 5–15 cho người giết; hồi sinh sau 8s",
       %{s: s} do
    place(s, %{"m_1" => {50, 36}})
    join(s, "a", {49, 36})
    set_monster(s, "m_1", %{hp: 1})
    flush()

    # đòn đánh xử lý ngay: dừng đúng lúc quái chết để đếm thời gian hồi sinh từ đó
    Enum.find(1..50, fn _ ->
      :ok = attack(s, "a", "m_1")
      monster(s, "m_1").state == "dead" or (MapServer.tick(s, 20) && false)
    end) || flunk("không hạ được")

    assert_receive {:map_reward, %{exp: 10, zen: zen, monster: "m_1"}}
    assert zen in 5..15
    assert_receive {:map_event, "combat", %{target: "m_1", hp: 0}}
    assert {:error, "INVALID_TARGET"} = attack(s, "a", "m_1")
    MapServer.tick(s, 2)
    assert_receive {:map_event, "snapshot", %{entities: es}}
    assert Enum.any?(es, &match?(%{id: "m_1", state: "dead", hp: 0}, &1))

    # respawnSeconds 8 = 160 tick (AI 10 Hz kiểm tra hồi sinh)
    flush()
    MapServer.tick(s, 148)
    refute_receive {:map_event, "spawn", %{id: "m_1"}}, 10
    MapServer.tick(s, 12)
    assert_receive {:map_event, "despawn", %{id: "m_1"}}

    assert_receive {:map_event, "spawn",
                    %{
                      id: "m_1",
                      kind: "monster",
                      hp: 30,
                      maxHp: 30,
                      state: "idle",
                      templateId: "spider"
                    }}

    m = monster(s, "m_1")
    [%{area: a}] = @map.spawns
    assert m.x in a.x..(a.x + a.w - 1) and m.state in ["idle", "chase", "attack"]
  end

  test "đồ rơi: g_<ULID> dưới đất, chủ = người gây nhiều sát thương nhất, hết hạn sau 60s", %{
    s: s
  } do
    place(s, %{"m_1" => {50, 36}})
    join(s, "a", {49, 36})

    # giết lặp lại (hp 1, hồi sinh tức thì) tới khi có đồ rơi
    drop =
      Enum.find_value(1..400, fn _ ->
        set_monster(s, "m_1", %{hp: 1, state: "idle", x: 50, y: 36})
        attack(s, "a", "m_1")
        MapServer.tick(s, 20)

        case MapServer.debug_state(s).ground |> Map.values() do
          [g | _] -> g
          [] -> nil
        end
      end) || flunk("không rơi đồ sau 400 lần")

    assert "g_" <> serial = drop.id
    assert Mu.Ulid.valid?(serial) and drop.serial == serial
    assert {drop.x, drop.y} == {50, 36}
    assert drop.owner == "a"

    assert drop.template_id in ~w(hp_potion_small mp_potion_small sword_t0 shield_t0 helm_t0 armor_t0 pants_t0 gloves_t0 boots_t0 ring_hp_t0)

    assert drop.protect_until - drop.expire_at == (10 - 60) * 1000

    gid = drop.id
    assert_receive {:map_event, "spawn", %{id: ^gid, kind: "item", templateId: _}}
    MapServer.debug_update(s, fn st -> %{st | monsters: %{}} end)
    MapServer.tick(s, 60 * 20)
    assert_receive {:map_event, "despawn", %{id: ^gid}}
    refute Map.has_key?(MapServer.debug_state(s).ground, gid)
  end

  test "AI: Spider thấy người trong 5 ô thì đuổi, đánh; người mất máu", %{s: s} do
    place(s, %{"m_1" => {52, 36}})
    join(s, "a", {48, 36})
    flush()
    MapServer.tick(s, 60)
    m = monster(s, "m_1")
    assert m.target == "a"
    assert m.state == "attack"
    assert Mu.World.Pathfinding.chebyshev({m.x, m.y}, {48, 36}) == 1
    MapServer.tick(s, 200)
    assert_receive {:map_event, "combat", %{rid: nil, attacker: "m_1", target: "p_a"}}
    assert player(s, "a").hp < 185
    assert MapServer.player_state(s, "a").combat_remaining_ms > 0
  end

  test "AI: người chạy vào thị trấn (safe zone) → quái về chỗ sinh, hồi đầy máu, không vào safe zone",
       %{s: s} do
    place(s, %{"m_1" => {32, 31}})
    join(s, "a", {30, 31})
    MapServer.tick(s, 6)
    assert monster(s, "m_1").target == "a"
    set_monster(s, "m_1", %{hp: 10})
    :ok = MapServer.move_to(s, "a", 18, 31)

    for _ <- 1..30 do
      MapServer.tick(s, 10)
      m = monster(s, "m_1")
      refute Maps.safe?(@map, m.x, m.y)
    end

    m = monster(s, "m_1")
    assert {m.x, m.y, m.state, m.hp, m.target} == {32, 31, "idle", 30, nil}
  end

  test "AI: vượt leashRange 12 thì bỏ đuổi", %{s: s} do
    place(s, %{"m_1" => {44, 50}})
    join(s, "a", {42, 50}, hp: 10_000)
    MapServer.tick(s, 6)
    assert monster(s, "m_1").target == "a"
    :ok = MapServer.move_to(s, "a", 10, 56)
    MapServer.tick(s, 400)
    m = monster(s, "m_1")
    assert m.state == "idle" and {m.x, m.y} == {44, 50}
  end

  test "người chơi chết: state dead, không đi/đánh được; sau 3s hồi sinh ở playerSpawn đầy HP/MP (G11)",
       %{s: s} do
    place(s, %{"m_1" => {50, 36}})
    join(s, "a", {49, 36}, hp: 1, mp: 3)
    flush()

    Enum.find(1..100, fn _ ->
      MapServer.tick(s, 2)
      player(s, "a").state == "dead"
    end) || flunk("không chết")

    assert_receive {:map_died, "a"}
    assert {:error, "FORBIDDEN"} = MapServer.move_to(s, "a", 45, 36)
    assert {:error, "FORBIDDEN"} = attack(s, "a", "m_1")
    # quái bỏ mục tiêu đã chết
    MapServer.tick(s, 2)
    assert monster(s, "m_1").target == nil

    MapServer.tick(s, Config.get(["combat", "playerRespawnSeconds"]) * 20)
    assert_receive {:map_event, "despawn", %{id: "p_a"}}
    assert_receive {:map_event, "spawn", %{id: "p_a", hp: 185, state: "idle"}}
    p = player(s, "a")
    assert {{p.x, p.y}, p.hp, p.mp} == {@map.player_spawn, 185, 30}
  end

  test "rời map khi đang chết: lưu như đã hồi sinh", %{s: s} do
    join(s, "a", {49, 36})
    set_player(s, "a", %{hp: 0, state: "dead", dead_at: 0})
    {px, py} = @map.player_spawn
    assert {:ok, %{x: ^px, y: ^py, hp: 185, mp: 30}} = MapServer.leave(s, "a")
  end

  test "Twisting Slash: cần cấp 10; AoE bán kính 2 quanh người dùng (G7); mana 10; cooldown 800",
       %{s: s} do
    place(s, %{"m_1" => {50, 36}, "m_2" => {51, 38}, "m_3" => {48, 34}, "m_4" => {52, 36}})
    join(s, "lv1", {49, 30})

    assert {:error, "REQUIREMENT_NOT_MET"} =
             MapServer.use_skill(s, "lv1", "twisting_slash", "m_1", "x")

    MapServer.leave(s, "lv1")

    join(s, "a", {50, 36}, level: 10)
    flush()
    assert :ok = MapServer.use_skill(s, "a", "twisting_slash", "m_1", "ts1")

    hits =
      for _ <- 1..3,
          do:
            (
              assert_receive({:map_event, "combat", %{rid: "ts1", target: t}})
              t
            )

    # m_4 cách 2 ô: trong bán kính 2; m_1 (0,0)... m_2 (1,2), m_3 (2,2) cũng trong
    assert Enum.sort(hits) -- ["m_1", "m_2", "m_3", "m_4"] == []
    assert_receive {:map_event, "combat", %{rid: "ts1"}}
    refute_receive {:map_event, "combat", %{rid: "ts1"}}, 10
    assert player(s, "a").mp == Engine.derived(dk(10)).mp_max - 10

    assert {:error, "COOLDOWN"} = MapServer.use_skill(s, "a", "twisting_slash", "m_1", "ts2")
    MapServer.tick(s, 16)
    set_monster(s, "m_1", %{hp: 30, state: "idle"})
    assert :ok = MapServer.use_skill(s, "a", "twisting_slash", {51, 36}, "ts3")

    # thiếu mana
    MapServer.tick(s, 16)
    set_player(s, "a", %{mp: 9})
    assert {:error, "NO_MANA"} = MapServer.use_skill(s, "a", "twisting_slash", "m_1", "ts4")

    assert {:error, "OUT_OF_RANGE"} =
             MapServer.use_skill(s, "a", "twisting_slash", {50, 40}, "ts5")

    assert {:error, "INVALID_TARGET"} = MapServer.use_skill(s, "a", "fireball", "m_1", "ts6")
  end

  test "update_player: chỉ số mới, HP không vượt max", %{s: s} do
    join(s, "a", {49, 36})
    stats = Engine.derived(dk(2))
    :ok = MapServer.update_player(s, "a", %{level: 2, stats: stats, hp: 999})
    assert player(s, "a").hp == stats.hp_max
  end
end

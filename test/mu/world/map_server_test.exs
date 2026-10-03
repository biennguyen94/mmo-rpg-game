defmodule Mu.World.MapServerTest do
  use ExUnit.Case, async: true

  alias Mu.World.{Maps, MapServer}

  setup do
    topic = "test_map:#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(Mu.PubSub, topic)

    pid =
      start_supervised!(
        {MapServer,
         map_id: "lorencia", name: nil, tick: :manual, topic: topic, spawn_monsters: false},
        id: :test_map
      )

    %{server: pid, map: Maps.get("lorencia")}
  end

  @dk %{class: "DK", level: 1, strength: 28, agility: 20, vitality: 25, energy: 10}

  defp player(id, {x, y}) do
    %{
      character_id: id,
      name: "N#{id}",
      class: "DK",
      level: 1,
      hp: 185,
      mp: 30,
      x: x,
      y: y,
      stats: Mu.Game.Engine.derived(@dk),
      skills: ["basic_attack"]
    }
  end

  defp join(server, id, pos, owner \\ self()) do
    {:ok, info} = MapServer.join(server, player(id, pos), owner)
    info
  end

  # chạy từng tick tới khi người chơi tới `pos`; trả về số tick đã chạy
  defp ticks_until(server, id, pos, max \\ 200) do
    Enum.reduce_while(1..max, nil, fn i, _ ->
      MapServer.tick(server)
      if MapServer.position(server, id) == pos, do: {:halt, i}, else: {:cont, nil}
    end)
  end

  test "join: đứng ở vị trí đã lưu; vị trí không đi được → playerSpawn", %{server: s, map: map} do
    assert %{entity_id: "p_a", x: 15, y: 30, entities: es} = join(s, "a", {15, 30})
    assert Enum.any?(es, &(&1.kind == "npc" and &1.id == "npc_lorencia_potion_merchant"))

    assert %{id: "p_a", kind: "player", maxHp: 185, state: "idle"} =
             Enum.find(es, &(&1.id == "p_a"))

    assert_receive {:map_event, "spawn", %{id: "p_a"}}

    {sx, sy} = map.player_spawn
    assert %{x: ^sx, y: ^sy} = join(s, "b", {0, 0})
    assert %{x: ^sx, y: ^sy} = join(s, "c", {999, 999})
  end

  test "join lần hai (tab khác) giữ vị trí, không spawn lại", %{server: s} do
    join(s, "a", {15, 30})
    assert_receive {:map_event, "spawn", _}
    :ok = MapServer.move_to(s, "a", 18, 30)
    ticks_until(s, "a", {18, 30})
    assert %{x: 18, y: 30} = join(s, "a", {15, 30})
    refute_receive {:map_event, "spawn", _}, 50
    assert MapServer.stats(s).players == 1
  end

  test "tốc độ 5 ô/giây (G3): 5 bước thẳng = 20 tick; bước chéo ×1.414", %{server: s} do
    join(s, "a", {10, 30})
    :ok = MapServer.move_to(s, "a", 15, 30)
    # 5 bước × 200 ms = 1000 ms = 20 tick × 50 ms
    assert ticks_until(s, "a", {15, 30}) == 20

    :ok = MapServer.move_to(s, "a", 16, 31)
    # 200 × 1.414 = 282.8 ms → tick thứ 6 (300 ms)
    assert ticks_until(s, "a", {16, 31}) == 6
  end

  test "đang đi nhận lệnh mới thì tính đường từ ô hiện tại; đi tới chỗ đang đứng = dừng", %{
    server: s
  } do
    join(s, "a", {10, 30})
    :ok = MapServer.move_to(s, "a", 20, 30)
    MapServer.tick(s, 8)
    assert MapServer.position(s, "a") == {12, 30}
    :ok = MapServer.move_to(s, "a", 12, 30)
    MapServer.tick(s, 20)
    assert MapServer.position(s, "a") == {12, 30}
    :ok = MapServer.move_to(s, "a", 12, 25)
    assert ticks_until(s, "a", {12, 25}) == 20
  end

  test "move_to bị từ chối: tường, nước, NPC, ngoài biên, sai kiểu, không có mặt", %{
    server: s,
    map: map
  } do
    join(s, "a", {15, 30})
    [npc] = map.npcs

    for {x, y} <- [{6, 30}, {33, 10}, {npc.x, npc.y}, {-1, 3}, {64, 3}, {1, 1}] do
      assert {:error, "INVALID_TARGET"} = MapServer.move_to(s, "a", x, y), inspect({x, y})
    end

    ExUnit.CaptureLog.capture_log(fn ->
      assert {:error, "INVALID_TARGET"} = MapServer.move_to(s, "a", "16", 30)
      assert {:error, "INVALID_TARGET"} = MapServer.move_to(s, "a", 16.5, 30)
    end)

    assert {:error, "INVALID_TARGET"} = MapServer.move_to(s, "khong_co", 16, 30)
    assert MapServer.position(s, "a") == {15, 30}
  end

  test "đi vòng qua tường thị trấn bằng cổng (server tự tính đường)", %{server: s} do
    join(s, "a", {20, 25})
    # (28, 25) ở ngoài tường đông: phải ra cổng đông (x=25, y 30..33)
    :ok = MapServer.move_to(s, "a", 28, 25)
    n = ticks_until(s, "a", {28, 25}, 400)
    # đường thẳng chỉ 8 ô; vòng qua cổng xa hơn nhiều
    assert n > 8 * 4
  end

  test "snapshot delta 10 Hz: chỉ khi có thay đổi, chỉ entity đổi", %{server: s} do
    join(s, "a", {10, 30})
    join(s, "b", {10, 35})
    assert_receive {:map_event, "spawn", %{id: "p_a"}}
    assert_receive {:map_event, "spawn", %{id: "p_b"}}

    # không ai đi: không có snapshot
    MapServer.tick(s, 4)
    refute_receive {:map_event, "snapshot", _}, 20

    :ok = MapServer.move_to(s, "a", 12, 30)
    # snapshot đầu tiên sau 2 tick (mỗi 100 ms)
    MapServer.tick(s, 1)
    refute_receive {:map_event, "snapshot", _}, 20
    MapServer.tick(s, 1)
    assert_receive {:map_event, "snapshot", %{t: t, entities: [e], removed: []}}
    assert is_integer(t)
    assert %{id: "p_a", x: 10, y: 30, state: "walk", hp: 185} = e

    MapServer.tick(s, 30)
    snaps = collect_snapshots()

    assert List.last(snaps).entities == [
             %{id: "p_a", x: 12, y: 30, hp: 185, mp: 30, state: "idle"}
           ]

    refute Enum.any?(snaps, fn sn -> Enum.any?(sn.entities, &(&1.id == "p_b")) end)
  end

  test "rời map: despawn + removed trong snapshot kế; trả vị trí cuối", %{server: s} do
    join(s, "a", {10, 30})
    assert {:ok, %{x: 10, y: 30, hp: 185, mp: 30}} = MapServer.leave(s, "a")
    assert :error = MapServer.leave(s, "a")
    assert_receive {:map_event, "despawn", %{id: "p_a"}}
    MapServer.tick(s, 2)
    assert_receive {:map_event, "snapshot", %{removed: ["p_a"], entities: []}}
    assert MapServer.position(s, "a") == nil
  end

  test "tiến trình chủ (Session) chết thì người chơi rời map", %{server: s} do
    owner = spawn(fn -> receive do: (:stop -> :ok) end)
    join(s, "a", {10, 30}, owner)
    send(owner, :stop)
    assert_receive {:map_event, "despawn", %{id: "p_a"}}
    assert MapServer.stats(s).players == 0
  end

  test "chế độ tự tick: ~20 tick/giây, không trôi" do
    pid =
      start_supervised!(
        {MapServer,
         map_id: "lorencia", name: nil, tick: :auto, topic: "test_auto", spawn_monsters: false},
        id: :auto_map
      )

    Process.sleep(1000)
    %{ticks: ticks, max_drift_ms: drift} = MapServer.stats(pid)
    assert ticks in 18..21
    assert drift < 50
  end

  defp collect_snapshots(acc \\ []) do
    receive do
      {:map_event, "snapshot", p} -> collect_snapshots([p | acc])
    after
      20 -> Enum.reverse(acc)
    end
  end
end

defmodule MuWeb.CombatChannelTest do
  @moduledoc "M3 qua kênh thật: đánh Spider → EXP/Zen → lên cấp → cộng stat → lưu → reload."
  use MuWeb.ChannelCase

  alias Mu.Game.{Character, Session}
  alias Mu.World.MapServer
  alias MuWeb.GameChannel

  @map "lorencia"

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  # đưa nhân vật ra ô (49, 36), chỉ giữ m_1 ở (50, 36)
  defp stage(character) do
    MapServer.debug_update(@map, fn st ->
      m = %{st.monsters["m_1"] | x: 50, y: 36, home: {50, 36}}
      players = Map.update!(st.players, character.id, &%{&1 | x: 49, y: 36})
      %{st | monsters: %{"m_1" => m}, players: players}
    end)
  end

  defp revive_spider(hp) do
    MapServer.debug_update(@map, fn st ->
      update_in(
        st.monsters["m_1"],
        &%{&1 | hp: hp, state: "idle", x: 50, y: 36, respawn_at: nil, damage_by: %{}}
      )
    end)
  end

  # hạ m_1 một lần (máu 1) bằng lệnh attack qua kênh
  defp kill_spider(socket, n) do
    revive_spider(1)

    Enum.find(1..40, fn i ->
      # test gửi nhanh hơn người chơi thật nhiều: bỏ qua giới hạn tần suất (đã có test riêng)
      Mu.RateLimit.reset()
      ref = push(socket, "cmd", %{"act" => "attack", "rid" => "k#{n}-#{i}", "target" => "m_1"})
      assert_reply ref, status, _
      dead? = status == :ok and MapServer.debug_state(@map).monsters["m_1"].state == "dead"
      dead? or (MapServer.tick(@map, 20) && false)
    end) || flunk("không hạ được")
  end

  defp stored(c), do: Mu.Repo.get!(Character, c.id)

  defp last_player_push(acc \\ nil) do
    receive do
      %Phoenix.Socket.Message{event: "player", payload: p} -> last_player_push(p)
    after
      100 -> acc
    end
  end

  test "attack qua kênh: ack {rid}, mọi người nhận combat" do
    {a, c} = create_character()
    {:ok, _, socket} = join_game(a, c)
    stage(c)
    ref = push(socket, "cmd", %{"act" => "attack", "rid" => "atk1", "target" => "m_1"})
    assert_reply ref, :ok, %{rid: "atk1"}
    eid = "p_" <> c.id
    assert_push "combat", %{rid: "atk1", attacker: ^eid, target: "m_1"}

    ref = push(socket, "cmd", %{"act" => "attack", "rid" => "atk2", "target" => "m_1"})
    assert_reply ref, :error, %{rid: "atk2", error: "COOLDOWN"}
    ref = push(socket, "cmd", %{"act" => "attack", "rid" => "atk3"})
    assert_reply ref, :error, %{error: "INVALID_TARGET"}

    ref =
      push(socket, "cmd", %{
        "act" => "skill",
        "rid" => "sk1",
        "id" => "twisting_slash",
        "target" => "m_1"
      })

    assert_reply ref, :error, %{error: "REQUIREMENT_NOT_MET"}
  end

  test "hạ Spider: EXP 10 + Zen, Zen ghi DB ngay (G12); 10 con → lên cấp 2, +5 điểm, hồi đầy HP" do
    {a, c} = create_character()
    {:ok, _, socket} = join_game(a, c)
    stage(c)

    kill_spider(socket, 1)
    p = last_player_push()
    assert {p.experience, p.level} == {10, 1}
    assert p.zen in 5..15
    assert stored(c).zen == p.zen
    assert stored(c).experience == 10

    for n <- 2..9, do: kill_spider(socket, n)
    # máu tụt để thấy hồi đầy khi lên cấp (G10)
    MapServer.debug_update(@map, fn st -> update_in(st.players[c.id], &%{&1 | hp: 50}) end)
    kill_spider(socket, 10)
    p = last_player_push()
    assert {p.level, p.experience, p.freeStatPoints} == {2, 0, 5}
    # cấp 2: hpMax = 110 + 3 + 75 = 188
    assert p.hp == 188 and p.view.hpMax == 188
    assert p.view.expRequired == 283

    s = stored(c)
    assert {s.level, s.experience, s.free_stat_points, s.hp_current} == {2, 0, 5, 188}
    assert s.zen == p.zen and s.zen in 50..150
  end

  test "cộng stat (alloc): đúng điểm, ghi DB, đẩy player; vượt điểm/stat sai bị chặn" do
    {a, c} = create_character()
    Mu.Repo.update!(Ecto.Changeset.change(c, level: 3, free_stat_points: 10))
    {:ok, _, socket} = join_game(a, c)

    ref =
      push(socket, "cmd", %{"act" => "alloc", "rid" => "al1", "stat" => "vitality", "points" => 4})

    assert_reply ref, :ok, %{rid: "al1"}
    assert_push "player", %{vitality: 29, freeStatPoints: 6, view: %{hpMax: hp_max}}
    # cấp 3: 110 + 2×3 + 29×3 = 203
    assert hp_max == 203
    s = stored(c)
    assert {s.vitality, s.free_stat_points} == {29, 6}

    ref =
      push(socket, "cmd", %{"act" => "alloc", "rid" => "al2", "stat" => "strength", "points" => 7})

    assert_reply ref, :error, %{error: "REQUIREMENT_NOT_MET"}

    ref =
      push(socket, "cmd", %{"act" => "alloc", "rid" => "al3", "stat" => "luck", "points" => 1})

    assert_reply ref, :error, %{error: "FORBIDDEN"}

    ref =
      push(socket, "cmd", %{
        "act" => "alloc",
        "rid" => "al4",
        "stat" => "strength",
        "points" => -3
      })

    assert_reply ref, :error, %{error: "FORBIDDEN"}
    assert stored(c).strength == 28
  end

  test "reload: level, EXP, stat, Zen, HP còn nguyên (đọc lại từ DB sau restart Session)" do
    {a, c} = create_character()
    {:ok, _, socket} = join_game(a, c)
    stage(c)
    for n <- 1..11, do: kill_spider(socket, n)

    ref =
      push(socket, "cmd", %{"act" => "alloc", "rid" => "al", "stat" => "strength", "points" => 5})

    assert_reply ref, :ok, _
    MapServer.debug_update(@map, fn st -> update_in(st.players[c.id], &%{&1 | hp: 77}) end)
    before = last_player_push()

    pid = Session.whereis(a.id)
    Process.unlink(socket.channel_pid)
    DynamicSupervisor.terminate_child(Mu.Game.SessionSupervisor, pid)

    {:ok, reply, _} = join_game(a, c)
    p = reply.player

    assert {p.level, p.experience, p.strength, p.freeStatPoints, p.zen} ==
             {2, 10, 33, 0, before.zen}

    assert p.hp == 77
  end

  test "chết: Spider đánh tới 0 HP → hồi sinh ở thị trấn sau 3s, đầy máu" do
    {a, c} = create_character()
    {:ok, reply, _socket} = join_game(a, c)
    stage(c)
    MapServer.debug_update(@map, fn st -> update_in(st.players[c.id], &%{&1 | hp: 1}) end)
    eid = reply.entityId

    Enum.find(1..200, fn _ ->
      MapServer.tick(@map, 2)
      MapServer.debug_state(@map).players[c.id].state == "dead"
    end) || flunk("không chết")

    assert_push "combat", %{attacker: "m_1", target: ^eid, hp: 0}
    MapServer.tick(@map, 60)
    assert_push "spawn", %{id: ^eid, hp: 185, state: "idle"}
    assert MapServer.position(@map, c.id) == Mu.World.Maps.get(@map).player_spawn
  end

  test "đóng tab khi đang combat: ở lại logoutInCombatSeconds rồi mới rời (G21)" do
    {a, c} = create_character()
    {:ok, _, socket} = join_game(a, c)
    stage(c)
    ref = push(socket, "cmd", %{"act" => "attack", "rid" => "a1", "target" => "m_1"})
    assert_reply ref, :ok, _

    Process.unlink(socket.channel_pid)
    close(socket)
    Process.sleep(50)
    # vẫn trên map (có thể bị đánh)
    assert MapServer.position(@map, c.id) != nil
    pid = Session.whereis(a.id)
    assert :sys.get_state(pid).leave_timer != nil

    send(pid, :delayed_leave)
    Process.sleep(50)
    assert MapServer.position(@map, c.id) == nil
  end

  test "đóng tab khi không combat: rời ngay" do
    {a, c} = create_character()
    {:ok, _, socket} = join_game(a, c)
    Process.unlink(socket.channel_pid)
    close(socket)
    Process.sleep(50)
    assert MapServer.position(@map, c.id) == nil
  end

  test "P2-5: Elf cầm cung đánh thường từ 5 ô; DK tay không chỉ 1 ô" do
    {a, c} = create_character(nil, "ELF")
    {:ok, r, socket} = join_game(a, c)
    assert r.player.view.attackRange == 5

    MapServer.debug_update(@map, fn st ->
      m = %{st.monsters["m_1"] | x: 50, y: 36, home: {50, 36}}
      players = Map.update!(st.players, c.id, &%{&1 | x: 45, y: 36})
      %{st | monsters: %{"m_1" => m}, players: players}
    end)

    ref = push(socket, "cmd", %{"act" => "attack", "rid" => "b1", "target" => "m_1"})
    assert_reply ref, :ok, %{rid: "b1"}

    MapServer.debug_update(@map, fn st ->
      put_in(st.players[c.id].x, 44) |> put_in([:players, c.id, :cooldowns], %{})
    end)

    ref = push(socket, "cmd", %{"act" => "attack", "rid" => "b2", "target" => "m_1"})
    assert_reply ref, :error, %{error: "OUT_OF_RANGE"}

    {a2, c2} = create_character()
    {:ok, r2, socket2} = join_game(a2, c2)
    assert r2.player.view.attackRange == 1

    MapServer.debug_update(@map, fn st ->
      put_in(st.players[c2.id].x, 48) |> put_in([:players, c2.id, :y], 36)
    end)

    ref = push(socket2, "cmd", %{"act" => "attack", "rid" => "d1", "target" => "m_1"})
    assert_reply ref, :error, %{error: "OUT_OF_RANGE"}
  end
end

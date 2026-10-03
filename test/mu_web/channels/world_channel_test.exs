defmodule MuWeb.WorldChannelTest do
  @moduledoc "M2 qua kênh thật: vào Lorencia, click-to-move, 2 người thấy nhau, lưu vị trí."
  use MuWeb.ChannelCase

  alias Mu.Game.{Character, Session}
  alias Mu.World.{Maps, MapServer}
  alias MuWeb.GameChannel
  alias Phoenix.Socket.Message

  @map "lorencia"

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)
    join_socket(socket, character)
  end

  defp join_socket(socket, character) do
    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  # Push của mọi kênh trong test đều về tiến trình test; phân biệt kênh bằng `join_ref`.
  defp pushes(join_ref, event, acc \\ []) do
    receive do
      %Message{event: ^event, join_ref: ^join_ref, payload: p} ->
        pushes(join_ref, event, [p | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  defp tick_until(character_id, pos, max \\ 400) do
    Enum.find(1..max, fn _ ->
      MapServer.tick(@map)
      MapServer.position(@map, character_id) == pos
    end) || flunk("không tới #{inspect(pos)}")
  end

  defp stored(character), do: Mu.Repo.get!(Character, character.id)

  defp wait_until(fun, tries \\ 50) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("điều kiện không thành sau 500 ms")
      true -> Process.sleep(10) && wait_until(fun, tries - 1)
    end
  end

  test "join: trả map, entityId; đẩy spawn của mình và NPC" do
    {a, c} = create_character()
    {:ok, reply, _} = join_game(a, c)

    assert reply.entityId == "p_" <> c.id
    assert reply.map.id == @map and reply.map.width == 64 and length(reply.map.tiles) == 64
    assert {reply.player.x, reply.player.y} == Maps.get(@map).player_spawn

    assert_push "spawn", %{id: "npc_lorencia_potion_merchant", kind: "npc"}
    eid = reply.entityId
    assert_push "spawn", %{id: ^eid, kind: "player", name: name}
    assert name == c.name
  end

  test "click-to-move: move_to hợp lệ ack {rid}; snapshot thấy mình đi; tường bị từ chối" do
    {a, c} = create_character()
    {:ok, reply, socket} = join_game(a, c)
    eid = reply.entityId
    {x, y} = {reply.player.x + 3, reply.player.y}

    ref = push(socket, "cmd", %{"act" => "move_to", "rid" => "mv1", "x" => x, "y" => y})
    assert_reply ref, :ok, %{rid: "mv1"}

    tick_until(c.id, {x, y})
    MapServer.tick(@map, 2)
    assert_push "snapshot", %{entities: [%{id: ^eid, state: "walk"}]}

    ref = push(socket, "cmd", %{"act" => "move_to", "rid" => "mv2", "x" => 6, "y" => 30})
    assert_reply ref, :error, %{rid: "mv2", error: "INVALID_TARGET"}
    assert_push "error", %{rid: "mv2", error: "INVALID_TARGET"}

    ref = push(socket, "cmd", %{"act" => "move_to", "rid" => "mv3"})
    assert_reply ref, :error, %{error: "INVALID_TARGET"}
  end

  test "2 người chơi cùng lúc thấy nhau di chuyển" do
    {a, ca} = create_character()
    {b, cb} = create_character()
    {:ok, ra, sa} = join_game(a, ca)
    {:ok, rb, sb} = join_game(b, cb)
    {ea, eb} = {ra.entityId, rb.entityId}
    {ja, jb} = {sa.join_ref, sb.join_ref}

    # A thấy B vào; B thấy A trong danh sách spawn lúc vào
    assert_receive %Message{event: "spawn", join_ref: ^ja, payload: %{id: ^eb, kind: "player"}}
    assert_receive %Message{event: "spawn", join_ref: ^jb, payload: %{id: ^ea, kind: "player"}}

    {tx, ty} = {ra.player.x + 2, ra.player.y - 2}
    ref = push(sa, "cmd", %{"act" => "move_to", "rid" => "r1", "x" => tx, "y" => ty})
    assert_reply ref, :ok, _
    tick_until(ca.id, {tx, ty})
    MapServer.tick(@map, 4)

    # B nhận snapshot có A, các vị trí liền nhau, cuối cùng đúng điểm A đã tới
    positions =
      for sn <- pushes(jb, "snapshot"), %{id: ^ea, x: x, y: y} <- sn.entities, do: {x, y}

    assert length(positions) >= 2
    assert List.last(positions) == {tx, ty}

    # B đăng xuất → A nhận despawn
    Process.unlink(sb.channel_pid)
    leave(sb)
    assert_receive %Message{event: "despawn", join_ref: ^ja, payload: %{id: ^eb}}
  end

  test "đăng xuất rồi vào lại: vị trí còn nguyên, đã ghi DB" do
    {a, c} = create_character()
    {:ok, reply, socket} = join_game(a, c)
    {tx, ty} = {reply.player.x + 4, reply.player.y + 1}

    ref = push(socket, "cmd", %{"act" => "move_to", "rid" => "r1", "x" => tx, "y" => ty})
    assert_reply ref, :ok, _
    tick_until(c.id, {tx, ty})

    Process.unlink(socket.channel_pid)
    leave(socket)
    # tab cuối rời kênh (đăng xuất) → rời map ngay và lưu (G21)
    wait_until(fn -> MapServer.position(@map, c.id) == nil end)
    s = stored(c)
    assert {s.position_x, s.position_y} == {tx, ty}
    assert s.version > c.version

    {:ok, reply2, _} = join_game(a, c)
    assert {reply2.player.x, reply2.player.y} == {tx, ty}
  end

  test "khởi động lại Session (như restart server): đọc lại vị trí từ DB" do
    {a, c} = create_character()
    {:ok, reply, socket} = join_game(a, c)
    {tx, ty} = {reply.player.x - 2, reply.player.y + 3}
    ref = push(socket, "cmd", %{"act" => "move_to", "rid" => "r1", "x" => tx, "y" => ty})
    assert_reply ref, :ok, _
    tick_until(c.id, {tx, ty})

    pid = Session.whereis(a.id)
    Process.unlink(socket.channel_pid)
    DynamicSupervisor.terminate_child(Mu.Game.SessionSupervisor, pid)
    refute Process.alive?(pid)
    assert {stored(c).position_x, stored(c).position_y} == {tx, ty}

    {:ok, reply2, _} = join_game(a, c)
    assert {reply2.player.x, reply2.player.y} == {tx, ty}
  end

  test "lưu định kỳ (session.saveIntervalSeconds) khi vẫn đang online" do
    assert Mu.Game.Config.get(["session", "saveIntervalSeconds"]) == 30
    {a, c} = create_character()
    {:ok, reply, socket} = join_game(a, c)
    {tx, ty} = {reply.player.x + 1, reply.player.y + 1}
    ref = push(socket, "cmd", %{"act" => "move_to", "rid" => "r1", "x" => tx, "y" => ty})
    assert_reply ref, :ok, _
    tick_until(c.id, {tx, ty})

    # kích hẹn giờ ngay thay vì đợi 30 giây
    send(Session.whereis(a.id), :save)
    wait_until(fn -> {stored(c).position_x, stored(c).position_y} == {tx, ty} end)
    assert MapServer.position(@map, c.id) == {tx, ty}
  end

  test "tab mới đá tab cũ nhưng nhân vật vẫn ở nguyên chỗ trên map" do
    {a, c} = create_character()
    {:ok, reply, s1} = join_game(a, c)
    {tx, ty} = {reply.player.x + 2, reply.player.y}
    ref = push(s1, "cmd", %{"act" => "move_to", "rid" => "r1", "x" => tx, "y" => ty})
    assert_reply ref, :ok, _
    tick_until(c.id, {tx, ty})
    Process.unlink(s1.channel_pid)

    {:ok, r2, _} = join_game(a, c)
    assert {r2.player.x, r2.player.y} == {tx, ty}
    assert_push "error", %{rid: nil, error: "FORBIDDEN"}
    refute_push "despawn", %{}
    assert MapServer.position(@map, c.id) == {tx, ty}
  end
end

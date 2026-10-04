defmodule MuWeb.PortalChannelTest do
  @moduledoc "P2-M4 qua kênh thật: cổng Lorencia ↔ Noria, thiếu cấp, đổi topic, lưu map."
  use MuWeb.ChannelCase

  alias Mu.Game.{Character, Session}
  alias Mu.World.MapServer
  alias MuWeb.GameChannel
  alias Phoenix.Socket.Message

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  defp cmd(socket, payload) do
    Mu.RateLimit.reset()
    ref = push(socket, "cmd", payload)
    assert_reply ref, status, reply
    {status, reply}
  end

  defp level(c, lv), do: Mu.Repo.update!(Ecto.Changeset.change(c, level: lv))

  defp place(map, c, {x, y}),
    do: MapServer.debug_update(map, fn st -> update_in(st.players[c.id], &%{&1 | x: x, y: y}) end)

  # bước lên ô cổng: move_to rồi tick tới khi nhận event `event`
  defp walk_into(map, socket, {x, y}, event) do
    {:ok, _} = cmd(socket, %{"act" => "move_to", "rid" => "mv#{x}#{y}", "x" => x, "y" => y})

    Enum.find_value(1..60, fn _ ->
      MapServer.tick(map, 1)

      receive do
        %Message{event: ^event, payload: p} -> p
      after
        5 -> nil
      end
    end) || flunk("không nhận #{event}")
  end

  test "thiếu cấp: báo REQUIREMENT_NOT_MET (portal, cấp 10), vẫn ở Lorencia" do
    {a, c} = create_character()
    {:ok, _, socket} = join_game(a, c)
    place("lorencia", c, {15, 10})

    assert %{error: "REQUIREMENT_NOT_MET", reason: "portal", map: "noria", levelRequired: 10} =
             walk_into("lorencia", socket, {15, 8}, "error")

    assert MapServer.position("lorencia", c.id) == {15, 8}
    assert MapServer.player_state("noria", c.id) == nil
  end

  test "đủ cấp: sang Noria (map_change + spawn), lưu map_id; quay về Lorencia qua cổng nam" do
    {a, c} = create_character()
    c = level(c, 10)
    {:ok, _, socket} = join_game(a, c)
    place("lorencia", c, {15, 10})

    p = walk_into("lorencia", socket, {15, 8}, "map_change")

    assert %{
             map: %{id: "noria", name: "Noria"},
             entityId: eid,
             player: %{mapId: "noria", x: 31, y: 59}
           } = p

    assert eid == "p_" <> c.id
    assert_push "spawn", %{id: "npc_noria_potion_merchant"}
    assert MapServer.player_state("lorencia", c.id) == nil
    assert %{x: 31, y: 59} = MapServer.player_state("noria", c.id)
    assert Mu.Repo.get!(Character, c.id).map_id == "noria"

    # kênh đã đổi topic: đánh / đi ở Noria thì nhận snapshot Noria, không còn của Lorencia
    {:ok, _} = cmd(socket, %{"act" => "move_to", "rid" => "n1", "x" => 31, "y" => 60})
    MapServer.tick("noria", 10)
    assert_push "snapshot", %{entities: [%{id: ^eid, y: 60} | _]}

    back = walk_into("noria", socket, {31, 61}, "map_change")
    assert %{map: %{id: "lorencia"}, player: %{x: 15, y: 9}} = back
    assert Mu.Repo.get!(Character, c.id).map_id == "lorencia"

    # vào lại game: Session đọc map đã lưu
    Process.unlink(socket.channel_pid)
    DynamicSupervisor.terminate_child(Mu.Game.SessionSupervisor, Session.whereis(a.id))
    {:ok, r, _} = join_game(a, Mu.Repo.get!(Character, c.id))
    assert r.map.id == "lorencia"
  end

  test "vào game khi nhân vật đã lưu ở Noria: join đúng map, chết hồi sinh ở thị trấn Noria" do
    {a, c} = create_character()

    c =
      Mu.Repo.update!(
        Ecto.Changeset.change(c, level: 12, map_id: "noria", position_x: 31, position_y: 40)
      )

    {:ok, r, _socket} = join_game(a, c)
    assert r.map.id == "noria" and {r.player.x, r.player.y} == {31, 40}

    MapServer.debug_update("noria", fn st ->
      update_in(st.players[c.id], &%{&1 | hp: 0, state: "dead", dead_at: 0})
    end)

    MapServer.tick("noria", 80)
    assert %{x: 31, y: 50, dead?: false} = MapServer.player_state("noria", c.id)
  end
end

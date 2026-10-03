defmodule MuWeb.ReconnectChannelTest do
  @moduledoc """
  P3-M2 (`KB_TECHNICAL §4`): mất kết nối → nhân vật đứng yên trên map `reconnectGraceSeconds`,
  vẫn bị đánh; vào lại trong hạn thì giữ nguyên trạng thái; quá hạn thì rời map và lưu.
  """
  use MuWeb.ChannelCase

  import Ecto.Query, only: [from: 2]

  alias Mu.Game.{Character, Config, Session}
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

  defp drop_connection(socket) do
    Process.unlink(socket.channel_pid)
    close(socket)
    Process.sleep(50)
  end

  defp stored(c), do: Mu.Repo.one(from(x in Character, where: x.id == ^c.id))

  setup do
    # bỏ quái: không bị đánh lạc trong test (trừ test bị đánh tự đặt quái)
    {a, c} = create_character()
    {:ok, reply, socket} = join_game(a, c)
    m1 = MapServer.debug_state(@map).monsters["m_1"]
    MapServer.debug_update(@map, fn st -> %{st | monsters: %{}} end)
    %{a: a, c: c, m1: m1, reply: reply, socket: socket}
  end

  test "mất kết nối: ở lại map reconnectGraceSeconds, dừng đi", %{
    a: a,
    c: c,
    reply: r,
    socket: socket
  } do
    assert Config.get(["session", "reconnectGraceSeconds"]) == 30

    ref =
      push(socket, "cmd", %{
        "act" => "move_to",
        "rid" => "m1",
        "x" => r.player.x + 8,
        "y" => r.player.y
      })

    assert_reply ref, :ok, _
    MapServer.tick(@map, 2)

    drop_connection(socket)
    e = MapServer.debug_state(@map).players[c.id]
    assert {e.path, e.state} == {[], "idle"}
    stop_at = {e.x, e.y}
    MapServer.tick(@map, 20)
    assert MapServer.position(@map, c.id) == stop_at

    timer = :sys.get_state(Session.whereis(a.id)).leave_timer
    assert Process.read_timer(timer) > 29_000
  end

  test "vẫn bị đánh khi mất kết nối", %{c: c, m1: m1, socket: socket} do
    # Spider cạnh nhân vật, bị đánh một đòn thì đánh trả (máu cao: không chết vì một đòn)
    MapServer.debug_update(@map, fn st ->
      m = %{m1 | x: 50, y: 36, home: {50, 36}, hp: 10_000, state: "idle", respawn_at: nil}
      players = Map.update!(st.players, c.id, &%{&1 | x: 49, y: 36})
      %{st | monsters: %{"m_1" => m}, players: players}
    end)

    ref = push(socket, "cmd", %{"act" => "attack", "rid" => "a1", "target" => "m_1"})
    assert_reply ref, :ok, _
    drop_connection(socket)
    hp0 = MapServer.debug_state(@map).players[c.id].hp
    MapServer.tick(@map, 100)
    assert MapServer.debug_state(@map).players[c.id].hp < hp0
  end

  test "vào lại trong hạn: giữ vị trí, HP/MP, buff; hủy hẹn rời map", %{
    a: a,
    c: c,
    socket: socket
  } do
    MapServer.debug_update(@map, fn st ->
      update_in(st.players[c.id], &%{&1 | x: 20, y: 30, hp: 100})
    end)

    buff = %{id: "greater_defense", stat: "defense", value: 5, expiresAt: 9_999_999_999_999}
    :sys.replace_state(Session.whereis(a.id), &%{&1 | buffs: [buff]})

    drop_connection(socket)
    {:ok, r2, _} = join_game(a, c)
    assert {r2.player.x, r2.player.y, r2.player.hp} == {20, 30, 100}
    assert r2.player.view.buffs == [buff]
    assert :sys.get_state(Session.whereis(a.id)).leave_timer == nil
  end

  test "quá hạn: rời map, lưu DB, buff mất", %{a: a, c: c, socket: socket} do
    MapServer.debug_update(@map, fn st -> update_in(st.players[c.id], &%{&1 | x: 21, y: 31}) end)
    drop_connection(socket)
    pid = Session.whereis(a.id)
    send(pid, :delayed_leave)
    Process.sleep(50)
    assert MapServer.position(@map, c.id) == nil
    assert {stored(c).position_x, stored(c).position_y} == {21, 31}
    assert :sys.get_state(pid).buffs == []
  end
end

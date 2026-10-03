defmodule MuWeb.DuelChannelTest do
  @moduledoc """
  P4-M2 qua kênh thật (P4-4): mời / nhận / từ chối / hủy, "vùng riêng" (người ngoài không xen
  vào), về 0 HP thì giữ 1 HP và thua (không chết, không PK), hết giờ hòa, đi xa / mất kết nối /
  đầu hàng thì thua; cùng nhóm không đánh được nhau (P4M1-2).
  """
  use MuWeb.ChannelCase

  import Ecto.Query, only: [from: 2]

  alias Mu.Game.Character
  alias Mu.World.MapServer
  alias MuWeb.GameChannel
  alias Phoenix.Socket.Message

  @map "lorencia"

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  defp player(level \\ 10) do
    {a, c} = create_character()
    c = Mu.Repo.update!(Ecto.Changeset.change(c, level: level))
    {:ok, _, socket} = join_game(a, c)
    %{a: a, c: c, s: socket, id: "p_" <> c.id, name: c.name}
  end

  defp cmd(p, act, payload \\ %{}) do
    Mu.RateLimit.reset()

    ref =
      push(
        p.s,
        "cmd",
        Map.merge(%{"act" => act, "rid" => "r#{System.unique_integer([:positive])}"}, payload)
      )

    assert_reply ref, status, reply
    if status == :ok, do: :ok, else: {:error, reply.error}
  end

  defp place(p, {x, y}, extra \\ %{}),
    do:
      MapServer.debug_update(@map, fn st ->
        update_in(st.players[p.c.id], &Map.merge(%{&1 | x: x, y: y, path: []}, extra))
      end)

  defp pl(p), do: MapServer.debug_state(@map).players[p.c.id]

  defp got(p, ev, acc \\ []) do
    jr = p.s.join_ref

    receive do
      %Message{event: ^ev, join_ref: ^jr, payload: x} -> got(p, ev, [x | acc])
    after
      80 -> Enum.reverse(acc)
    end
  end

  defp start(a, b) do
    :ok = cmd(a, "duel_request", %{"to" => b.name})
    :ok = cmd(b, "duel_accept", %{"from" => a.name})
  end

  defp hit(a, b) do
    Enum.find(1..60, fn _ ->
      hp0 = pl(b).hp
      MapServer.debug_update(@map, fn st -> put_in(st.players[a.c.id].cooldowns, %{}) end)
      _ = cmd(a, "attack", %{"target" => b.id})
      pl(b).hp < hp0
    end) || flunk("không đánh trúng")
  end

  defp ai_ticks, do: MapServer.tick(@map, MapServer.debug_state(@map).ai_every)

  setup do
    MapServer.debug_update(@map, fn st -> %{st | monsters: %{}} end)
    :ok
  end

  test "mời → nhận: hai bên nhận duel start, cả map nhận SYSTEM; luật mời (tầm 10, cấp 6, đã duel)" do
    {a, b, low} = {player(), player(), player(5)}
    place(a, {40, 31})
    place(b, {52, 31})
    assert {:error, "OUT_OF_RANGE"} = cmd(a, "duel_request", %{"to" => b.name})
    place(b, {41, 31})
    assert {:error, "REQUIREMENT_NOT_MET"} = cmd(a, "duel_request", %{"to" => low.name})
    assert {:error, "INVALID_TARGET"} = cmd(a, "duel_request", %{"to" => "KhongCo99"})

    :ok = cmd(a, "duel_request", %{"to" => String.upcase(b.name)})
    assert [%{state: "request", opponent: an}] = got(b, "duel")
    assert an == a.name
    :ok = cmd(b, "duel_accept", %{"from" => a.name})
    bid = b.id
    assert [%{state: "start", opponent: _, opponentId: ^bid, endsAt: ends}] = got(a, "duel")
    assert ends > System.os_time(:millisecond) + 170_000
    assert Enum.any?(got(low, "chat"), &(&1.channel == "SYSTEM" and &1.text =~ "đấu tay đôi"))
    # đang duel: không ai mời được
    c = player()
    place(c, {40, 32})
    assert {:error, "FORBIDDEN"} = cmd(c, "duel_request", %{"to" => a.name})
  end

  test "từ chối / hủy lời mời báo người kia" do
    {a, b} = {player(), player()}
    place(a, {40, 31})
    place(b, {41, 31})
    :ok = cmd(a, "duel_request", %{"to" => b.name})
    :ok = cmd(b, "duel_decline", %{"from" => a.name})
    assert [%{state: "end", result: "declined"}] = got(a, "duel")
    assert {:error, "INVALID_TARGET"} = cmd(b, "duel_accept", %{"from" => a.name})

    :ok = cmd(a, "duel_request", %{"to" => b.name})
    got(b, "duel")
    :ok = cmd(a, "duel_cancel")
    assert [%{state: "end", result: "cancelled"}] = got(b, "duel")
  end

  test "vùng riêng: người ngoài không đánh được người đang duel và ngược lại; về 0 HP → 1 HP, thua, không PK" do
    {a, b, c} = {player(), player(), player()}
    place(a, {40, 31})
    place(b, {41, 31})
    place(c, {40, 32})
    start(a, b)
    aid = a.id
    assert_receive %Message{event: "spawn", payload: %{id: ^aid, dueling: true}}
    assert {:error, "FORBIDDEN"} = cmd(c, "attack", %{"target" => a.id})
    assert {:error, "FORBIDDEN"} = cmd(a, "attack", %{"target" => c.id})

    # đánh nhau trong duel: không tự vệ / kẻ gây sự
    hit(a, b)
    assert pl(a).aggressor_until == nil
    place(b, {41, 31}, %{hp: 1})
    for p <- [a, b], do: got(p, "duel")
    hit_until_end(a, b)
    assert %{hp: 1, state: state} = pl(b)
    assert state != "dead"
    assert [%{state: "end", result: "win"}] = got(a, "duel")
    assert [%{state: "end", result: "lose"}] = got(b, "duel")
    assert Mu.Repo.one(from(x in Character, where: x.id == ^a.c.id, select: x.pk_points)) == 0
    # hết duel: c lại đánh được a
    assert :ok = cmd(c, "attack", %{"target" => a.id})
  end

  test "hết giờ → hòa; đi xa quá 20 ô → người đi xa thua; mất kết nối / đầu hàng → thua" do
    {a, b} = {player(), player()}
    place(a, {40, 31})
    place(b, {41, 31})
    start(a, b)

    MapServer.debug_update(@map, fn st ->
      %{
        st
        | duels: %{
            st.duels
            | active: Map.new(st.duels.active, fn {k, v} -> {k, %{v | ends_at: 0}} end)
          }
      }
    end)

    for p <- [a, b], do: got(p, "duel")
    ai_ticks()
    assert [%{result: "draw"}] = got(a, "duel")

    start(a, b)
    for p <- [a, b], do: got(p, "duel")
    place(b, {62, 31})
    ai_ticks()
    assert [%{result: "lose"}] = got(b, "duel")
    assert [%{result: "win"}] = got(a, "duel")

    place(b, {41, 31})
    start(a, b)
    for p <- [a, b], do: got(p, "duel")
    :ok = cmd(a, "duel_cancel")
    assert [%{result: "lose"}] = got(a, "duel")

    start(a, b)
    for p <- [a, b], do: got(p, "duel")
    Process.unlink(b.s.channel_pid)
    close(b.s)
    Process.sleep(50)
    assert [%{result: "win"}] = got(a, "duel")
  end

  test "P4M1-2: người cùng nhóm không đánh được nhau" do
    {a, b} = {player(), player()}
    place(a, {40, 31})
    place(b, {41, 31})
    :ok = cmd(a, "party_invite", %{"to" => b.name})
    :ok = cmd(b, "party_accept", %{"from" => a.name})
    assert {:error, "FORBIDDEN"} = cmd(a, "attack", %{"target" => b.id})
  end

  defp hit_until_end(a, b) do
    Enum.find(1..60, fn _ ->
      MapServer.debug_update(@map, fn st -> put_in(st.players[a.c.id].cooldowns, %{}) end)
      _ = cmd(a, "attack", %{"target" => b.id})
      not Mu.Game.Duel.in_duel?(MapServer.debug_state(@map).duels, a.c.id)
    end) || flunk("duel không kết thúc")
  end
end

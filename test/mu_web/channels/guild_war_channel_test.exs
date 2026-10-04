defmodule MuWeb.GuildWarChannelTest do
  @moduledoc """
  P4-M4 (P4-6) qua kênh thật: master tuyên chiến / nhận / từ chối, event `guild_war`, thành viên
  hai guild đánh nhau không PK / không tự vệ / không rơi đồ, kill +1 điểm, đạt điểm thắng, AOE trúng
  người guild địch, đầu hàng, hết giờ, giải tán = đầu hàng, người vào game thấy war.
  """
  use MuWeb.ChannelCase

  import Ecto.Query, only: [from: 2]

  alias Mu.Game.{Character, Config}
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

  defp player(level \\ 20, zen \\ 0) do
    {a, c} = create_character()
    c = Mu.Repo.update!(Ecto.Changeset.change(c, level: level, zen: zen))
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

  defp got(p, ev, acc \\ []) do
    jr = p.s.join_ref

    receive do
      %Message{event: ^ev, join_ref: ^jr, payload: x} -> got(p, ev, [x | acc])
    after
      80 -> Enum.reverse(acc)
    end
  end

  defp last(p, ev), do: List.last(got(p, ev))
  defp gname, do: "W#{rem(System.unique_integer([:positive]), 1_000_000)}"

  # guild: master + thành viên
  defp guild(members) do
    m = player(20, Config.get(["guild", "createZen"]))
    name = gname()
    :ok = cmd(m, "guild_create", %{"name" => name})

    for p <- members do
      :ok = cmd(m, "guild_invite", %{"to" => p.name})
      :ok = cmd(p, "guild_accept", %{"guild" => name})
    end

    {m, name}
  end

  defp at_war(ma, na, mb, nb) do
    :ok = cmd(ma, "guild_war_declare", %{"guild" => nb})
    :ok = cmd(mb, "guild_war_accept", %{"guild" => na})
  end

  defp place(p, {x, y}, extra \\ %{}) do
    MapServer.debug_update(@map, fn st ->
      update_in(st.players[p.c.id], &Map.merge(%{&1 | x: x, y: y, path: []}, extra))
    end)
  end

  defp pl(p), do: MapServer.debug_state(@map).players[p.c.id]

  defp hit(a, b) do
    Enum.find(1..40, fn _ ->
      hp0 = pl(b).hp
      MapServer.debug_update(@map, fn st -> put_in(st.players[a.c.id].cooldowns, %{}) end)
      :ok = cmd(a, "attack", %{"target" => b.id})
      pl(b).hp < hp0 or pl(b).state == "dead"
    end) || flunk("không đánh trúng")
  end

  defp pk(p), do: Mu.Repo.one(from(c in Character, where: c.id == ^p.c.id, select: c.pk_points))

  setup do
    MapServer.debug_update(@map, fn st -> %{st | monsters: %{}} end)
    :ok
  end

  test "tuyên chiến → master bên kia nhận request → nhận: hai guild nhận start + SYSTEM" do
    {a1, b1} = {player(), player()}
    {ma, na} = guild([a1])
    {mb, nb} = guild([b1])

    # chỉ master; tên sai; tự tuyên chiến mình
    assert {:error, "FORBIDDEN"} = cmd(a1, "guild_war_declare", %{"guild" => nb})
    assert {:error, "INVALID_TARGET"} = cmd(ma, "guild_war_declare", %{"guild" => "KhongCo1"})
    assert {:error, "INVALID_TARGET"} = cmd(ma, "guild_war_declare", %{"guild" => na})

    :ok = cmd(ma, "guild_war_declare", %{"guild" => nb})
    assert %{state: "request", enemy: ^na, from: from} = last(mb, "guild_war")
    assert from == ma.name
    assert got(b1, "guild_war") == []

    :ok = cmd(mb, "guild_war_accept", %{"guild" => na})

    for {p, enemy} <- [{ma, nb}, {a1, nb}, {mb, na}, {b1, na}] do
      assert %{state: "start", enemy: ^enemy, score: 0, enemyScore: 0, scoreToWin: 20} =
               last(p, "guild_war")
    end

    assert Enum.any?(
             got(a1, "chat"),
             &(&1.channel == "SYSTEM" and &1.text =~ "chiến tranh guild")
           )

    assert Mu.Guild.at_war?(na, nb) and Mu.Guild.at_war?(nb, na)

    # đang war: không tuyên chiến / nhận thêm
    {mc, nc} = guild([])
    assert {:error, "FORBIDDEN"} = cmd(mc, "guild_war_declare", %{"guild" => na})
    assert {:error, "INVALID_TARGET"} = cmd(mb, "guild_war_accept", %{"guild" => nc})
  end

  test "từ chối báo master bên tuyên chiến; master bên kia offline → INVALID_TARGET" do
    {ma, na} = guild([])
    {mb, nb} = guild([])
    :ok = cmd(ma, "guild_war_declare", %{"guild" => nb})
    :ok = cmd(mb, "guild_war_decline", %{"guild" => na})
    assert Enum.any?(got(ma, "chat"), &(&1.text =~ "từ chối lời tuyên chiến"))
    assert {:error, "INVALID_TARGET"} = cmd(mb, "guild_war_accept", %{"guild" => na})

    Process.unlink(mb.s.channel_pid)
    leave(mb.s)
    Process.sleep(100)
    assert {:error, "INVALID_TARGET"} = cmd(ma, "guild_war_declare", %{"guild" => nb})
  end

  test "đánh nhau trong war: không tự vệ / kẻ gây sự, kill không PK, không rơi đồ, +1 điểm; người ngoài vẫn như PvP thường" do
    {a1, b1, o} = {player(), player(), player()}
    {ma, na} = guild([a1])
    {mb, nb} = guild([b1])
    at_war(ma, na, mb, nb)
    _ = got(a1, "guild_war")

    place(a1, {40, 31})
    place(b1, {41, 31}, %{hp: 1})
    # safe zone vẫn cấm
    place(b1, {16, 31}, %{hp: 1})
    assert {:error, "FORBIDDEN"} = cmd(a1, "attack", %{"target" => b1.id})
    place(b1, {41, 31}, %{hp: 1})

    hit(a1, b1)
    assert pl(b1).state == "dead"
    assert pl(a1).aggressor_until == nil
    Process.sleep(80)
    assert pk(a1) == 0
    assert %{state: "score", score: 1, enemyScore: 0} = last(a1, "guild_war")
    assert %{state: "score", score: 0, enemyScore: 1} = last(b1, "guild_war")

    # người ngoài guild: PvP thường (kẻ gây sự)
    place(o, {39, 31})
    hit(a1, o)
    assert pl(a1).aggressor_until != nil
  end

  test "đạt scoreToWin → thắng / thua, SYSTEM, hết war" do
    {a1, b1} = {player(), player()}
    {ma, na} = guild([a1])
    {mb, nb} = guild([b1])
    at_war(ma, na, mb, nb)
    goal = Config.get(["guildWar", "scoreToWin"])

    for _ <- 1..goal do
      MapServer.debug_update(@map, fn st -> put_in(st.players[b1.c.id].state, "idle") end)
      place(a1, {40, 31})
      place(b1, {41, 31}, %{hp: 1})
      hit(a1, b1)
    end

    Process.sleep(80)
    assert %{state: "end", result: "win", reason: "score", score: ^goal} = last(a1, "guild_war")
    assert %{state: "end", result: "lose", enemyScore: ^goal} = last(mb, "guild_war")
    assert Enum.any?(got(b1, "chat"), &(&1.text =~ "Guild #{na} thắng"))
    refute Mu.Guild.at_war?(na, nb)
  end

  test "AOE (Twisting Slash) trúng người guild địch, không trúng người ngoài" do
    {a1, b1, o} = {player(), player(), player()}
    {ma, na} = guild([a1])
    {mb, nb} = guild([b1])
    at_war(ma, na, mb, nb)
    place(a1, {40, 31})
    place(b1, {41, 31})
    place(o, {40, 32})
    hp_o = pl(o).hp

    Enum.find(1..40, fn _ ->
      MapServer.debug_update(@map, fn st -> put_in(st.players[a1.c.id].cooldowns, %{}) end)
      _ = cmd(a1, "skill", %{"id" => "twisting_slash"})
      pl(b1).hp < pl(b1).stats.hp_max
    end) || flunk("AOE không trúng")

    assert pl(o).hp == hp_o
  end

  test "đầu hàng; hết giờ hòa; giải tán = đầu hàng; người vào game thấy war" do
    {ma, na} = guild([])
    {mb, nb} = guild([])
    assert {:error, "INVALID_TARGET"} = cmd(ma, "guild_war_surrender")
    at_war(ma, na, mb, nb)
    :ok = cmd(ma, "guild_war_surrender")
    assert %{state: "end", result: "lose", reason: "surrender"} = last(ma, "guild_war")
    assert %{state: "end", result: "win"} = last(mb, "guild_war")

    at_war(ma, na, mb, nb)
    :ok = Mu.Guild.expire_wars(System.monotonic_time(:millisecond) + 31 * 60_000)
    assert %{state: "end", result: "draw", reason: "time"} = last(ma, "guild_war")

    # vào game (tab mới) giữa war: nhận start
    at_war(ma, na, mb, nb)
    # tab mới đá tab cũ (singleLoginPerAccount)
    Process.unlink(mb.s.channel_pid)
    {:ok, _, s2} = join_game(mb.a, mb.c)
    assert %{state: "start", enemy: ^na} = last(%{mb | s: s2}, "guild_war")

    :ok = cmd(ma, "guild_disband")
    assert %{state: "end", result: "win", reason: "disband"} = last(%{mb | s: s2}, "guild_war")
    refute Mu.Guild.at_war?(na, nb)
  end
end

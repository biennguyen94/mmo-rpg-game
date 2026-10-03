defmodule MuWeb.PvpChannelTest do
  @moduledoc """
  P4-M1 qua kênh thật: đánh người chơi (cấp, safe zone), tự vệ + kẻ gây sự, giết NORMAL → PK
  (ghi DB ngay), giết khi tự vệ không PK, kẻ giết không nhận EXP, MURDERER không dùng NPC, rơi đồ
  khi bị giết, PK giảm theo giờ khi vào lại.
  """
  use MuWeb.ChannelCase

  import Ecto.Query, only: [from: 2]

  alias Mu.Game.{Character, Items, Session}
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

  defp player(level \\ 10, attrs \\ []) do
    {a, c} = create_character()
    c = Mu.Repo.update!(Ecto.Changeset.change(c, [level: level] ++ attrs))
    {:ok, reply, socket} = join_game(a, c)
    %{a: a, c: c, s: socket, id: "p_" <> c.id, reply: reply}
  end

  defp cmd(p, act, payload) do
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

  defp place(p, {x, y}, extra \\ %{}) do
    MapServer.debug_update(@map, fn st ->
      update_in(st.players[p.c.id], &Map.merge(%{&1 | x: x, y: y, path: []}, extra))
    end)
  end

  defp pl(p), do: MapServer.debug_state(@map).players[p.c.id]

  # đánh tới khi trúng ít nhất một đòn (đòn có thể trượt)
  defp hit(a, b) do
    Enum.find(1..40, fn _ ->
      hp0 = pl(b).hp
      MapServer.debug_update(@map, fn st -> put_in(st.players[a.c.id].cooldowns, %{}) end)
      :ok = cmd(a, "attack", %{"target" => b.id})
      pl(b).hp < hp0 or pl(b).state == "dead"
    end) || flunk("không đánh trúng")
  end

  defp last_player(p) do
    jr = p.s.join_ref

    receive do
      %Message{event: "player", join_ref: ^jr, payload: x} -> last_player(p) || x
    after
      100 -> nil
    end
  end

  defp stored(p), do: Mu.Repo.one(from(c in Character, where: c.id == ^p.c.id))

  setup do
    MapServer.debug_update(@map, fn st -> %{st | monsters: %{}} end)
    :ok
  end

  test "đánh người: cấp < 6 hoặc safe zone thì không; ngoài thị trấn trúng, sát thương × 0,5, kẻ gây sự + tự vệ" do
    {a, b, low} = {player(), player(), player(5)}
    place(a, {40, 31})
    place(b, {41, 31})
    place(low, {41, 32})

    assert {:error, "REQUIREMENT_NOT_MET"} = cmd(a, "attack", %{"target" => low.id})
    assert {:error, "REQUIREMENT_NOT_MET"} = cmd(low, "attack", %{"target" => a.id})

    # trong thị trấn (safe zone)
    place(b, {16, 31})
    assert {:error, "FORBIDDEN"} = cmd(a, "attack", %{"target" => b.id})
    place(b, {41, 31})

    hit(a, b)
    assert pl(a).aggressor_until != nil
    assert Map.has_key?(pl(b).rights, a.c.id)
    aid = a.id

    assert_receive %Message{
      event: "spawn",
      payload: %{id: ^aid, aggressor: true, pkState: "NORMAL"}
    }

    # B đánh trả: B không thành kẻ gây sự
    hit(b, a)
    assert pl(b).aggressor_until == nil
  end

  test "giết người NORMAL → +1 PK (ghi DB, player.pkState WARNING, spawn cam); không nhận EXP; nạn nhân chết" do
    {a, b} = {player(), player()}
    place(a, {40, 31})
    place(b, {41, 31}, %{hp: 1})
    last_player(a)

    hit(a, b)
    assert pl(b).state == "dead"
    Process.sleep(50)

    assert %{experience: 0, view: %{pkPoints: 1, pkState: "WARNING"}} = last_player(a)
    assert %{pk_points: 1, last_pk_at: %DateTime{}} = stored(a)
    aid = a.id
    assert_receive %Message{event: "spawn", payload: %{id: ^aid, pkState: "WARNING"}}
  end

  test "giết khi đang tự vệ không tính PK; giết người WARNING không tính PK" do
    {a, b} = {player(), player()}
    place(a, {40, 31})
    place(b, {41, 31})
    hit(a, b)
    place(a, {40, 31}, %{hp: 1})
    hit(b, a)
    assert pl(a).state == "dead"
    Process.sleep(50)
    assert stored(b).pk_points == 0

    {c, w} = {player(), player(10, pk_points: 1, last_pk_at: DateTime.utc_now())}
    place(c, {40, 33})
    place(w, {41, 33}, %{hp: 1})
    hit(c, w)
    Process.sleep(50)
    assert stored(c).pk_points == 0
  end

  test "MURDERER không dùng NPC; vào lại sau 2 giờ PK 2 → 0" do
    m = player(10, pk_points: 2, last_pk_at: DateTime.utc_now())
    assert m.reply.player.view.pkState == "MURDERER"
    place(m, {12, 26})
    assert {:error, "FORBIDDEN"} = cmd(m, "npc_open", %{"npcId" => "lorencia_potion_merchant"})

    {a2, old} = create_character()

    old =
      Mu.Repo.update!(
        Ecto.Changeset.change(old,
          level: 10,
          pk_points: 2,
          last_pk_at: DateTime.add(DateTime.utc_now(), -121 * 60, :second)
        )
      )

    {:ok, r, _} = join_game(a2, old)
    assert {r.player.view.pkPoints, r.player.view.pkState} == {0, "NORMAL"}
  end

  test "rơi đồ khi bị giết: 1 món trong túi rơi xuống chỗ chết, kẻ giết có loot protect" do
    {a, b} = {player(), player()}

    {:ok, _} =
      Items.pickup(b.c.id, %{serial: Mu.Ulid.generate(), template_id: "sword_t0"}, "test")

    # Session đọc lại túi
    :sys.replace_state(Session.whereis(b.a.id), &%{&1 | items: Items.load(b.c.id)})
    place(b, {44, 31})

    send(Session.whereis(b.a.id), {:map_pk_drop, b.c.id, a.c.id})
    Process.sleep(80)

    assert Items.load(b.c.id) |> Enum.filter(&(&1.location == "INVENTORY")) == []

    g =
      MapServer.debug_state(@map).ground
      |> Map.values()
      |> Enum.find(&(&1.template_id == "sword_t0"))

    assert {g.x, g.y, g.owner} == {44, 31, a.c.id}
  end
end

defmodule MuWeb.PartyChannelTest do
  @moduledoc """
  P3-M4 (P3-5) qua kênh thật: mời / nhận / từ chối, chỉ trưởng nhóm mời / đuổi / giải tán,
  tối đa 5, chat PARTY, event `party` (HP, map, online), chia EXP, loot protect cả nhóm,
  trưởng nhóm rời, mất kết nối quá hạn thì rời nhóm.
  """
  use MuWeb.ChannelCase

  alias Mu.Game.Session
  alias Mu.Party
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

  defp player do
    {a, c} = create_character()
    {:ok, _, socket} = join_game(a, c)
    %{a: a, c: c, s: socket, name: c.name}
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

  # tin `ev` của người chơi `p` (theo join_ref)
  defp got(p, ev, acc \\ []) do
    jr = p.s.join_ref

    receive do
      %Message{event: ^ev, join_ref: ^jr, payload: x} -> got(p, ev, [x | acc])
    after
      80 -> Enum.reverse(acc)
    end
  end

  defp last(p, ev), do: List.last(got(p, ev))

  defp form(leader, member) do
    :ok = cmd(leader, "party_invite", %{"to" => member.name})
    :ok = cmd(member, "party_accept", %{"from" => leader.name})
  end

  defp names(view), do: Enum.map(view.members, & &1.name)

  test "mời → nhận: cả hai nhận party {leader, members}; người được mời nhận party_invite" do
    [a, b] = [player(), player()]
    :ok = cmd(a, "party_invite", %{"to" => String.upcase(b.name)})
    assert [%{from: from}] = got(b, "party_invite")
    assert from == a.name

    :ok = cmd(b, "party_accept", %{"from" => a.name})

    for p <- [a, b] do
      view = last(p, "party")
      assert view.leader == a.name
      assert names(view) == [a.name, b.name]

      assert [%{class: "DK", level: 1, mapId: @map, online: true, hp: hp, maxHp: max} | _] =
               view.members

      assert is_integer(hp) and hp == max
    end

    # nhận lại lời mời đã dùng → INVALID_TARGET
    assert {:error, "INVALID_TARGET"} = cmd(b, "party_accept", %{"from" => a.name})
  end

  test "luật mời: mình / offline / đã có nhóm → INVALID_TARGET; không phải trưởng nhóm → FORBIDDEN; từ chối báo người mời" do
    [a, b, c] = [player(), player(), player()]
    form(a, b)

    assert {:error, "INVALID_TARGET"} = cmd(a, "party_invite", %{"to" => a.name})
    assert {:error, "INVALID_TARGET"} = cmd(a, "party_invite", %{"to" => "KhongCo99"})
    assert {:error, "FORBIDDEN"} = cmd(b, "party_invite", %{"to" => c.name})

    :ok = cmd(a, "party_invite", %{"to" => c.name})
    got(a, "chat")
    :ok = cmd(c, "party_decline", %{"from" => a.name})
    assert Enum.any?(got(a, "chat"), &(&1.channel == "SYSTEM" and &1.text =~ "từ chối"))

    # C lập nhóm khác với D, A mời C → C đã có nhóm
    d = player()
    form(c, d)
    assert {:error, "INVALID_TARGET"} = cmd(a, "party_invite", %{"to" => c.name})
  end

  test "lời mời hết hạn sau party.inviteSeconds" do
    [a, b] = [player(), player()]
    :ok = cmd(a, "party_invite", %{"to" => b.name})

    :sys.replace_state(Party, fn st ->
      %{
        st
        | invites:
            Map.new(st.invites, fn {k, v} ->
              {k, Map.new(v, fn {f, _} -> {f, System.monotonic_time(:millisecond) - 1} end)}
            end)
      }
    end)

    assert {:error, "INVALID_TARGET"} = cmd(b, "party_accept", %{"from" => a.name})
  end

  test "tối đa party.maxSize (5) người" do
    [a | rest] = for _ <- 1..6, do: player()
    for m <- Enum.take(rest, 4), do: form(a, m)
    assert length(last(a, "party").members) == 5
    assert {:error, "FORBIDDEN"} = cmd(a, "party_invite", %{"to" => List.last(rest).name})
  end

  test "chat PARTY chỉ tới thành viên; không có nhóm → INVALID_TARGET" do
    [a, b, c] = [player(), player(), player()]
    assert {:error, "INVALID_TARGET"} = cmd(a, "chat", %{"channel" => "PARTY", "text" => "x"})
    form(a, b)
    for p <- [a, b, c], do: got(p, "chat")
    :ok = cmd(b, "chat", %{"channel" => "PARTY", "text" => "đi săn"})

    for p <- [a, b],
        do:
          assert(
            [%{channel: "PARTY", text: "đi săn"}] =
              Enum.filter(got(p, "chat"), &(&1.channel == "PARTY"))
          )

    assert got(c, "chat") == []
  end

  test "chia EXP: thành viên trong expRange chia đều + bonus; ngoài tầm không nhận; Zen chỉ người hạ" do
    [a, b, c] = [player(), player(), player()]
    form(a, b)
    form(a, c)

    MapServer.debug_update(@map, fn st ->
      m = %{
        st.monsters["m_1"]
        | x: 50,
          y: 36,
          home: {50, 36},
          hp: 1,
          state: "idle",
          respawn_at: nil
      }

      players =
        st.players
        |> Map.update!(a.c.id, &%{&1 | x: 49, y: 36})
        |> Map.update!(b.c.id, &%{&1 | x: 51, y: 36})
        # C cách quái 30 ô > expRange 20
        |> Map.update!(c.c.id, &%{&1 | x: 20, y: 36})

      %{st | monsters: %{"m_1" => m}, players: players}
    end)

    for p <- [a, b, c], do: got(p, "player")
    # đòn có thể trượt (roll ngẫu nhiên): đánh tới khi Spider chết
    Enum.find(1..40, fn _ ->
      _ = cmd(a, "attack", %{"target" => "m_1"})

      MapServer.debug_state(@map).monsters["m_1"].state == "dead" or
        (MapServer.tick(@map, 20) && false)
    end) || flunk("không hạ được Spider")

    jr = a.s.join_ref
    assert_receive %Message{event: "player", join_ref: ^jr, payload: %{experience: 5}}, 1000

    # Spider 10 EXP, 2 người nhận: 10 / 2 × (1 + 0,1) = 5,5 → 5 mỗi người
    assert Mu.Game.Engine.party_exp_gain(10, 2, 1, 2) == 5
    assert %{experience: 5, zen: 0} = last(b, "player")
    assert got(c, "player") == []
  end

  test "loot protect: người cùng nhóm với chủ nhặt được" do
    [a, b, c] = [player(), player(), player()]
    form(a, b)
    serial = Mu.Ulid.generate()

    g = %{
      id: "g_" <> serial,
      serial: serial,
      template_id: "helm_t0",
      quantity: 1,
      attrs: nil,
      x: 40,
      y: 40,
      owner: a.c.id,
      protect_until: 10_000_000,
      expire_at: 10_000_000
    }

    MapServer.debug_update(@map, fn st ->
      players =
        st.players
        |> Map.update!(b.c.id, &%{&1 | x: 40, y: 40})
        |> Map.update!(c.c.id, &%{&1 | x: 40, y: 41})

      %{st | players: players, ground: Map.put(st.ground, g.id, g)}
    end)

    assert {:error, "NOT_OWNER"} = cmd(c, "pickup", %{"id" => g.id})
    assert :ok = cmd(b, "pickup", %{"id" => g.id})
  end

  test "đuổi / rời / giải tán: chỉ trưởng nhóm đuổi, giải tán; trưởng nhóm rời → người vào sớm nhất làm trưởng" do
    [a, b, c, d] = [player(), player(), player(), player()]
    form(a, b)
    form(a, c)
    form(a, d)

    assert {:error, "FORBIDDEN"} = cmd(b, "party_kick", %{"name" => c.name})
    assert {:error, "FORBIDDEN"} = cmd(b, "party_disband")
    :ok = cmd(a, "party_kick", %{"name" => d.name})
    assert %{leader: nil, members: []} = last(d, "party")
    assert names(last(a, "party")) == [a.name, b.name, c.name]

    :ok = cmd(a, "party_leave")
    view = last(b, "party")
    assert {view.leader, names(view)} == {b.name, [b.name, c.name]}
    assert %{members: []} = last(a, "party")

    :ok = cmd(b, "party_disband")
    for p <- [b, c], do: assert(%{members: []} = last(p, "party"))
    assert {:error, "INVALID_TARGET"} = cmd(c, "party_leave")
  end

  test "còn 1 người thì nhóm giải tán" do
    [a, b] = [player(), player()]
    form(a, b)
    :ok = cmd(b, "party_leave")
    assert %{members: []} = last(a, "party")
    assert Party.mates(a.c.id) == [a.c.id]
  end

  test "mất kết nối: online false trong hạn reconnect; quá hạn thì rời nhóm" do
    [a, b, c] = [player(), player(), player()]
    form(a, b)
    form(a, c)
    got(a, "party")

    Process.unlink(b.s.channel_pid)
    close(b.s)
    Process.sleep(50)
    :ok = Party.flush()
    assert %{members: [_, %{online: false}, _]} = last(a, "party")

    send(Session.whereis(b.a.id), :delayed_leave)
    Process.sleep(50)
    assert names(last(a, "party")) == [a.name, c.name]
  end
end

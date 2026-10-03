defmodule MuWeb.GuildChannelTest do
  @moduledoc """
  P4-M3 (P4-5) qua kênh thật: tạo guild (cấp + Zen), mời / nhận / từ chối, quyền master /
  assistant / member, rời / đuổi / phong / hạ / giải tán, chat GUILD, event `guild`, tên guild
  trên `spawn`, vào lại game vẫn còn guild.
  """
  use MuWeb.ChannelCase

  alias Mu.Game.Config
  alias MuWeb.GameChannel
  alias Phoenix.Socket.Message

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  defp player(level \\ 1, zen \\ 0) do
    {a, c} = create_character()
    c = Mu.Repo.update!(Ecto.Changeset.change(c, level: level, zen: zen))
    {:ok, _, socket} = join_game(a, c)
    %{a: a, c: c, s: socket, id: "p_" <> c.id, name: c.name}
  end

  defp master do
    player(Config.get(["guild", "createLevel"]), Config.get(["guild", "createZen"]) + 100)
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
  defp gname, do: "G#{rem(System.unique_integer([:positive]), 1_000_000)}"
  defp roles(view), do: Map.new(view.members, &{&1.name, &1.role})

  defp chats(p), do: got(p, "chat")
  defp said?(p, text), do: Enum.any?(chats(p), &(&1.text =~ text))

  # master `m` lập guild và kéo `ps` vào
  defp found(m, ps) do
    name = gname()
    :ok = cmd(m, "guild_create", %{"name" => name})

    for p <- ps do
      :ok = cmd(m, "guild_invite", %{"to" => p.name})
      :ok = cmd(p, "guild_accept", %{"guild" => name})
    end

    name
  end

  test "tạo: trừ Zen (player), event guild, tên guild trên spawn người khác thấy" do
    m = master()
    o = player()
    _ = got(m, "guild")
    name = gname()
    assert :ok = cmd(m, "guild_create", %{"name" => name})

    assert last(m, "player").zen == 100
    view = last(m, "guild")
    assert view.name == name and view.master == m.name
    assert [%{name: mn, role: "master", online: true, level: lvl}] = view.members
    assert mn == m.name and lvl == Config.get(["guild", "createLevel"])

    assert Enum.any?(got(o, "spawn"), &(&1.id == m.id and &1.guild == name))

    # đã có guild / tên trùng
    assert {:error, "FORBIDDEN"} = cmd(m, "guild_create", %{"name" => gname()})
    assert {:error, "FORBIDDEN"} = cmd(master(), "guild_create", %{"name" => name})
    assert {:error, "REQUIREMENT_NOT_MET"} = cmd(o, "guild_create", %{"name" => gname()})
    assert {:error, "INVALID_TARGET"} = cmd(o, "guild_create", %{"name" => "x"})
  end

  test "mời → nhận / từ chối; chỉ master + assistant mời; người đã có guild không mời được" do
    [m, a, b, c] = [master(), player(), player(), player()]
    name = found(m, [a])
    assert [%{from: from, guild: ^name}] = got(a, "guild_invite") |> Enum.take(-1)
    assert from == m.name
    assert roles(last(m, "guild")) == %{m.name => "master", a.name => "member"}
    assert last(a, "guild").name == name
    assert said?(m, "#{a.name} đã vào guild")

    # member không mời được; người đã có guild / không online → INVALID_TARGET
    assert {:error, "FORBIDDEN"} = cmd(a, "guild_invite", %{"to" => b.name})
    assert {:error, "INVALID_TARGET"} = cmd(m, "guild_invite", %{"to" => a.name})
    assert {:error, "INVALID_TARGET"} = cmd(m, "guild_invite", %{"to" => "KhongCo99"})
    assert {:error, "INVALID_TARGET"} = cmd(b, "guild_invite", %{"to" => c.name})

    # từ chối: người mời nhận SYSTEM; lời mời hết
    :ok = cmd(m, "guild_invite", %{"to" => b.name})
    :ok = cmd(b, "guild_decline", %{"guild" => name})
    assert said?(m, "#{b.name} từ chối")
    assert {:error, "INVALID_TARGET"} = cmd(b, "guild_accept", %{"guild" => name})

    # phó guild mời được
    :ok = cmd(m, "guild_promote", %{"name" => a.name})
    :ok = cmd(a, "guild_invite", %{"to" => c.name})
    :ok = cmd(c, "guild_accept", %{"guild" => String.downcase(name)})
    assert Map.keys(roles(last(m, "guild"))) |> length() == 3
  end

  test "đầy guild: FORBIDDEN" do
    max = Config.get(["guild", "maxMembers"])
    m = master()
    gid = Mu.Guilds.by_name(found(m, [])).id
    for _ <- 1..(max - 1), do: :ok = Mu.Guilds.add_member(gid, elem(create_character(), 1).id)
    assert {:error, "FORBIDDEN"} = cmd(m, "guild_invite", %{"to" => player().name})
  end

  test "quyền: đuổi / phong / hạ / rời / giải tán" do
    [m, a, b, c] = [master(), player(), player(), player()]
    name = found(m, [a, b, c])
    :ok = cmd(m, "guild_promote", %{"name" => a.name})
    assert roles(last(b, "guild"))[a.name] == "assistant"
    assert said?(b, "#{a.name} được phong")

    # member không đuổi / phong được; assistant không phong, không đuổi assistant / master
    assert {:error, "FORBIDDEN"} = cmd(b, "guild_kick", %{"name" => c.name})
    assert {:error, "FORBIDDEN"} = cmd(a, "guild_promote", %{"name" => b.name})
    assert {:error, "FORBIDDEN"} = cmd(a, "guild_kick", %{"name" => m.name})
    assert {:error, "FORBIDDEN"} = cmd(b, "guild_disband")
    assert {:error, "INVALID_TARGET"} = cmd(m, "guild_promote", %{"name" => a.name})
    assert {:error, "INVALID_TARGET"} = cmd(m, "guild_kick", %{"name" => m.name})

    # assistant đuổi member: người bị đuổi nhận guild rỗng, spawn guild null
    _ = got(m, "spawn")
    :ok = cmd(a, "guild_kick", %{"name" => c.name})
    assert last(c, "guild") == %{id: nil, name: nil, master: nil, members: []}
    assert said?(m, "#{c.name} bị mời ra khỏi guild")
    refute Map.has_key?(roles(last(m, "guild")), c.name)
    assert Enum.any?(got(m, "spawn"), &(&1.id == c.id and &1.guild == nil))

    # hạ phó guild; master không rời được; member rời
    :ok = cmd(m, "guild_demote", %{"name" => a.name})
    assert roles(last(m, "guild"))[a.name] == "member"
    assert {:error, "FORBIDDEN"} = cmd(m, "guild_leave")
    :ok = cmd(b, "guild_leave")
    assert said?(m, "#{b.name} đã rời guild")
    assert {:error, "INVALID_TARGET"} = cmd(b, "guild_leave")

    # giải tán: mọi người hết guild; tên dùng lại được
    :ok = cmd(m, "guild_disband")
    assert said?(a, "đã giải tán")

    for p <- [m, a], do: assert(last(p, "guild").members == [])
    assert Mu.Guilds.by_name(name) == nil
  end

  test "chat GUILD chỉ tới thành viên; không có guild → INVALID_TARGET" do
    [m, a, o] = [master(), player(), player()]
    _ = found(m, [a])
    _ = chats(o)
    :ok = cmd(a, "chat", %{"channel" => "GUILD", "text" => "tập trung"})

    for p <- [m, a] do
      assert Enum.any?(chats(p), &(&1.channel == "GUILD" and &1.text == "tập trung"))
    end

    refute said?(o, "tập trung")

    assert {:error, "INVALID_TARGET"} =
             cmd(o, "chat", %{"channel" => "GUILD", "text" => "hi"})
  end

  test "đăng xuất → thành viên thấy offline; vào lại vẫn còn guild, tên trên đầu" do
    [m, a] = [master(), player()]
    name = found(m, [a])
    Process.unlink(a.s.channel_pid)
    leave(a.s)
    Process.sleep(100)

    assert Enum.find(last(m, "guild").members, &(&1.name == a.name)).online == false

    {:ok, _, s2} = join_game(a.a, a.c)
    a2 = %{a | s: s2}
    assert last(a2, "guild").name == name
    assert Enum.find(last(m, "guild").members, &(&1.name == a.name)).online == true
    assert Enum.any?(got(m, "spawn"), &(&1.id == a.id and &1.guild == name))
  end
end

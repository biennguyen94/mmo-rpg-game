defmodule HacLongWeb.GuildWarArenaTest do
  @moduledoc "Chiến bang đi hết đường thật: lệnh pvp_challenge qua kênh → thắng → bang được điểm, nhật ký trận báo."
  use HacLongWeb.ChannelCase

  alias HacLong.{Accounts, GuildWars}
  alias HacLong.Game.{Characters, Commands}
  alias HacLongWeb.{ClientVersion, UserSocket}

  setup do
    HacLong.RateLimit.reset()
    GuildWars.reset()
    :ok
  end

  defp player(user, attrs) do
    name = "Bh #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})

    p =
      p
      |> Map.put(:tutorial, nil)
      |> Map.put(:pos, %{map: "village", x: 12, y: 14})
      |> Map.merge(%{gold: 50_000})
      |> Map.merge(attrs)

    {p, _} = HacLong.Game.Achievements.check(p)
    Characters.save!(user.id, p, "TEST")
    p
  end

  defp join(user) do
    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})
    {:ok, _reply, socket} = subscribe_and_join(socket, "game", %{"v" => ClientVersion.current()})
    socket
  end

  defp cmd(socket, payload) do
    ref = push(socket, "cmd", payload)
    assert_reply ref, :ok, reply

    if reply[:msg] == "Thao tác quá nhanh." do
      Process.sleep(100)
      cmd(socket, payload)
    else
      reply
    end
  end

  defp gop(socket, op, payload \\ %{}) do
    ref = push(socket, "guild", Map.put(payload, "op", op))
    assert_reply ref, status, reply
    {status, reply}
  end

  test "thắng thành viên bang địch qua lệnh pvp_challenge thật thì bang được điểm" do
    ua = create_user()
    player(ua, %{level: 200, str: 3000, vit: 3000, agi: 500})
    sa = join(ua)
    r = cmd(sa, %{"act" => "guild_create", "name" => "Bang AA", "tag" => "AA1"})
    ga = r.player.guild.id

    ub = create_user()
    player(ub, %{})
    sb = join(ub)
    r = cmd(sb, %{"act" => "guild_create", "name" => "Bang BB", "tag" => "BB1"})
    gb = r.player.guild.id

    {:ok, _} = gop(sa, "war_declare", %{"tag" => "BB1"})
    {:ok, _} = gop(sb, "war_accept")

    r = cmd(sa, %{"act" => "pvp_challenge", "uid" => ub.id})
    assert r.msg =~ "Thách đấu"

    r =
      Enum.reduce_while(1..100, r, fn _, _ ->
        r = cmd(sa, %{"act" => "attack"})
        if r.player.battle && r.player.battle.over, do: {:halt, r}, else: {:cont, r}
      end)

    assert r.player.battle.result == "win"
    assert List.last(r.player.battle.log).text =~ "Chiến bang: bang bạn +1 điểm"
    assert %{mine: 1, theirs: 0} = GuildWars.brief(ga)
    assert %{mine: 0, theirs: 1} = GuildWars.brief(gb)
  end
end

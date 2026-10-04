defmodule HacLongWeb.GuildWarTest do
  @moduledoc "Phase 5 (H4, H5): tối đa 2 phó bang, đơn xin vào hết hạn; chiến bang (tuyên chiến, nhận, điểm, kết thúc, thưởng)."
  use HacLongWeb.ChannelCase

  import Ecto.Query

  alias HacLong.{Accounts, GuildWars, Guilds, Repo}
  alias HacLong.Game.{Characters, Commands}
  alias HacLongWeb.{ClientVersion, UserSocket}

  setup do
    HacLong.RateLimit.reset()
    GuildWars.reset()
    :ok
  end

  defp player(user, attrs \\ %{}) do
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

  # bang mới, bang chủ online; trả {bang_chủ, socket, gid, tag}
  defp guild do
    u = create_user()
    player(u)
    s = join(u)
    tag = "W#{rem(System.unique_integer([:positive]), 1000)}"
    r = cmd(s, %{"act" => "guild_create", "name" => "Bang #{tag}", "tag" => tag})
    {u, s, r.player.guild.id, tag}
  end

  defp add(gid) do
    u = create_user()
    player(u, %{level: 40})
    {:ok, _} = Guilds.join(u.id, gid)
    u
  end

  test "tối đa 2 phó bang; nhường bang chủ khi đã đủ phó thì bang chủ cũ làm thành viên" do
    {_l, s, gid, _} = guild()
    [a, b, c] = for _ <- 1..3, do: add(gid)

    assert {:ok, _} = gop(s, "promote", %{"uid" => a.id})
    assert {:ok, _} = gop(s, "promote", %{"uid" => b.id})
    assert {:error, %{msg: msg}} = gop(s, "promote", %{"uid" => c.id})
    assert msg =~ "đủ 2 phó bang"

    assert {:ok, _} = gop(s, "transfer", %{"uid" => c.id})
    roles = Repo.all(from m in "guild_members", where: m.guild_id == ^gid, select: m.role)
    assert Enum.frequencies(roles) == %{"leader" => 1, "officer" => 2, "member" => 1}
  end

  test "đơn xin vào quá 7 ngày tự bỏ" do
    {_l, s, gid, _} = guild()
    {:ok, _} = gop(s, "settings", %{"open" => false, "notice" => ""})
    u = create_user()
    player(u)
    {:ok, _} = Guilds.join(u.id, gid)
    assert Guilds.my_requests(u.id) == [gid]
    old = DateTime.utc_now() |> DateTime.add(-8 * 86_400, :second) |> DateTime.truncate(:second)

    Repo.update_all(from(r in "guild_requests", where: r.user_id == ^u.id),
      set: [inserted_at: old]
    )

    assert Guilds.my_requests(u.id) == []
  end

  test "tuyên chiến → nhận → thắng ở đấu trường ghi điểm (tối đa 3 lần một cặp) → hết giờ: thưởng bang thắng" do
    {la, sa, ga, _ta} = guild()
    {lb, sb, gb, tb} = guild()
    fund0 = Repo.one(from g in "guilds", where: g.id == ^ga, select: g.fund)

    assert {:ok, %{msg: msg}} = gop(sa, "war_declare", %{"tag" => tb})
    assert msg =~ "Đã tuyên chiến"
    assert {:error, _} = gop(sa, "war_declare", %{"tag" => tb})
    assert {:ok, %{guild: %{war_pending: %{tag: _}}}} = gop(sb, "info")

    assert {:ok, %{msg: "Bắt đầu chiến bang!", guild: %{war: %{mine: 0, theirs: 0}}}} =
             gop(sb, "war_accept")

    # bang chủ A thắng bang chủ B ở đấu trường 4 lần: chỉ 3 lần tính điểm
    for _ <- 1..3, do: assert({:ok, _} = GuildWars.record(la.id, lb.id))
    assert GuildWars.record(la.id, lb.id) == nil
    # người ngoài bang địch không tính
    outsider = create_user()
    player(outsider)
    assert GuildWars.record(la.id, outsider.id) == nil

    assert %{mine: 3, theirs: 0} = GuildWars.brief(ga)
    assert %{mine: 0, theirs: 3} = GuildWars.brief(gb)

    %{id: id} = GuildWars.active(ga)
    GuildWars.finish(id)

    assert GuildWars.active(ga) == nil

    assert Repo.one(from g in "guilds", where: g.id == ^ga, select: g.fund) ==
             fund0 + GuildWars.rules().win_fund

    mails =
      Repo.all(
        from m in "mails",
          where: m.user_id == ^la.id and m.subject == "Thưởng chiến bang",
          select: m.gold
      )

    assert mails == [GuildWars.rules().win_gold]
    assert [%{result: "win", mine: 3}] = GuildWars.history(ga)
    assert [%{result: "lose"}] = GuildWars.history(gb)

    # vừa chiến xong: chưa chiến lại được
    assert {:error, %{msg: msg}} = gop(sa, "war_declare", %{"tag" => tb})
    assert msg =~ "chiến lại"
  end

  test "từ chối, đầu hàng, không có ai online để nhận" do
    {_la, sa, ga, _} = guild()
    {_lb, sb, _gb, tb} = guild()
    {:ok, _} = gop(sa, "war_declare", %{"tag" => tb})
    assert {:ok, %{msg: "Đã từ chối."}} = gop(sb, "war_decline")
    assert GuildWars.active(ga) == nil

    {:ok, _} = gop(sa, "war_declare", %{"tag" => tb})
    {:ok, _} = gop(sb, "war_accept")
    assert {:ok, %{msg: "Đã đầu hàng."}} = gop(sb, "war_surrender")
    assert [%{result: "win"}] = GuildWars.history(ga)

    # bang không ai online
    u = create_user()
    p = player(u)
    tag = "Z#{rem(System.unique_integer([:positive]), 1000)}"
    Guilds.create(u.id, "Bang #{tag}", tag, p, fn _ -> :ok end)
    assert is_integer(Guilds.id_by_tag(tag))
    {_lc, sc, _gc, _} = guild()
    assert {:error, %{msg: msg}} = gop(sc, "war_declare", %{"tag" => tag})
    assert msg =~ "online"
  end
end

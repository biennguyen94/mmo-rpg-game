defmodule HacLongWeb.CastleSiegeTest do
  @moduledoc "Công Thành Chiến (B-22): lịch tuần, đăng ký, vào thành, Vương Miện, đồ sát giữa bang, Chủ Thành, thưởng."
  use HacLongWeb.ChannelCase

  alias HacLong.{Accounts, CastleSiege, Guilds, Mailbox, Slay}
  alias HacLong.Game.{Characters, Commands, Session}
  alias HacLong.World.MapServer
  alias HacLongWeb.{ClientVersion, UserSocket}

  @r CastleSiege.rules()
  @tower %{map: "village", x: 20, y: 8}

  setup do
    HacLong.RateLimit.reset()
    Slay.reset()
    CastleSiege.reload()

    on_exit(fn ->
      CastleSiege.finish_now()
    end)

    :ok
  end

  defp player(user, attrs \\ %{}) do
    name = "Ct #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})

    p =
      p
      |> Map.put(:tutorial, nil)
      |> Map.put(:pos, @tower)
      |> Map.merge(%{gold: 500_000, level: 40})
      |> Map.merge(attrs)

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

  defp wait(pred, n \\ 100) do
    cond do
      pred.() -> :ok
      n == 0 -> flunk("chờ quá lâu")
      true -> Process.sleep(20) && wait(pred, n - 1)
    end
  end

  # bang mới với bang chủ online đứng cạnh Người Gác Tháp: {user, socket, gid}
  defp guild do
    u = create_user()
    player(u)
    s = join(u)
    tag = "C#{rem(System.unique_integer([:positive]), 1000)}"
    r = cmd(s, %{"act" => "guild_create", "name" => "Bang #{tag}", "tag" => tag})
    {u, s, r.player.guild.id}
  end

  defp vn(d, h, m), do: DateTime.new!(d, Time.new!(h, m, 0)) |> DateTime.add(-7 * 3600)

  test "lịch: mỗi tuần vào thứ weekday lúc hour:minute giờ Việt Nam" do
    # 2026-10-10 là thứ Bảy
    sat = ~D[2026-10-10]
    assert Date.day_of_week(sat) == 6
    at = DateTime.to_unix(vn(Date.add(sat, @r.weekday - 6), @r.hour, @r.minute))
    assert CastleSiege.next_start(DateTime.from_unix!(at - 60)) == at
    assert CastleSiege.next_start(DateTime.from_unix!(at)) == at + 7 * 86_400
  end

  test "đăng ký → vào thành → Vương Miện → bang giữ Vương Miện thành Chủ Thành, thành viên nhận thư" do
    {ua, sa, ga} = guild()
    {ub, sb, gb} = guild()

    # chưa có bang thì không đăng ký được; bang chủ đăng ký, mất vàng
    r = cmd(sa, %{"act" => "cs_register"})
    assert r.ok
    assert r.player.view.cs.mine_registered
    assert cmd(sb, %{"act" => "cs_register"}).ok
    refute cmd(sb, %{"act" => "cs_register"}).ok

    # nạp lại từ database vẫn còn đăng ký
    CastleSiege.reload()
    assert CastleSiege.status().registered |> Enum.sort() == Enum.sort([ga, gb])

    # chưa đánh thì chưa vào được
    refute cmd(sa, %{"act" => "cs_enter"}).ok

    :ok = CastleSiege.start_now(false)
    ra = cmd(sa, %{"act" => "cs_enter"})
    assert ra.ok and ra.player.pos.map == @r.map
    assert cmd(sb, %{"act" => "cs_enter"}).ok

    crown = MapServer.snapshot(@r.map).monsters |> Enum.find(&(&1.kind == @r.crown.kind))
    assert crown.name == @r.crown.name and crown.boss

    # đồ sát: khác bang được, cùng bang không
    a = Session.get(ua.id)
    b = Session.get(ub.id)
    assert Slay.check(a, b) == :ok

    assert {:error, "Trong Công Thành Chiến chỉ đánh người bang khác."} =
             Slay.check(a, %{b | guild: a.guild})

    # bang B hạ Vương Miện → giữ; B không đánh được Vương Miện nữa, A thì được
    CastleSiege.defeated(ub.id, crown.id, b.guild)
    wait(fn -> CastleSiege.status().holder != nil end)
    assert CastleSiege.status().holder.id == gb
    assert CastleSiege.crown_blocked(b, crown) =~ "đang giữ"
    assert CastleSiege.crown_blocked(a, crown) == nil

    :ok = CastleSiege.finish_now()
    st = CastleSiege.status()
    assert st.phase == "idle" and st.owner.id == gb and st.registered == []

    wait(fn -> Session.get(ua.id).pos.map == "village" end)
    wait(fn -> Mailbox.list(ub.id) |> Enum.any?(&(&1.subject =~ "Chủ Thành")) end)
    assert Enum.find(Mailbox.list(ub.id), &(&1.subject =~ "Chủ Thành")).gold == @r.reward.gold
    refute Mailbox.list(ua.id) |> Enum.any?(&(&1.subject =~ "Chủ Thành"))

    # Chủ Thành giữ qua khởi động lại
    CastleSiege.reload()
    assert CastleSiege.status().owner.id == gb
    _ = ga
  end

  test "không bang, không phải bang chủ / phó: không đăng ký, không vào được" do
    u = create_user()
    player(u)
    s = join(u)
    r = cmd(s, %{"act" => "cs_register"})
    refute r.ok
    assert r.msg =~ "bang"

    {_, _, gid} = guild()
    m = create_user()
    player(m)
    {:ok, _} = Guilds.join(m.id, gid)
    p = %{Session.get(m.id) | guild: %{id: gid, name: "x", tag: "x", role: "member"}}
    assert {%{ok: false, msg: "Chỉ bang chủ" <> _}, _} = CastleSiege.register(p, m.id)

    # không bang nào đăng ký: trận không diễn ra
    :ok = CastleSiege.start_now(false)
    assert CastleSiege.status().phase == "idle"

    # bang khác đăng ký: trận diễn ra, bang chưa đăng ký không vào được
    {_, s2, _} = guild()
    assert cmd(s2, %{"act" => "cs_register"}).ok
    :ok = CastleSiege.start_now(false)
    assert {%{ok: false, msg: "Bang bạn chưa đăng ký" <> _}, _} = CastleSiege.enter(p, m.id)
  end
end

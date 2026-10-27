defmodule HacLongWeb.ChaosCastleTest do
  @moduledoc "Hỗn Chiến Thành (B-19): lịch, mua vé, vào thành, thả quái, đồ sát trong thành, người trụ cuối thắng."
  use HacLongWeb.ChannelCase

  alias HacLong.{Accounts, ChaosCastle, Mailbox, Slay}
  alias HacLong.Game.{Characters, Commands, Session}
  alias HacLong.World.MapServer
  alias HacLongWeb.{ClientVersion, UserSocket}

  @r ChaosCastle.rules()
  # cạnh Người Gác Tháp ở Làng
  @tower %{map: "village", x: 20, y: 8}

  setup do
    HacLong.RateLimit.reset()
    Slay.reset()
    on_exit(fn -> ChaosCastle.finish_now() end)
    :ok
  end

  defp player(user, attrs) do
    name = "Cc #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    p = p |> Map.put(:tutorial, nil) |> Map.put(:pos, @tower) |> Map.merge(attrs)
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

  # giờ Việt Nam hh:mm → DateTime UTC
  defp vn(h, m), do: DateTime.new!(~D[2026-10-10], Time.new!(h, m, 0)) |> DateTime.add(-7 * 3600)

  test "lịch: mở lệch offset, cho vào entry_minutes phút, hỗn chiến run_minutes phút" do
    h = div(@r.offset_minutes, 60)
    m = rem(@r.offset_minutes, 60)
    assert {:entry, _, _, _} = ChaosCastle.phase_at(vn(h, m))
    assert {:entry, _, _, _} = ChaosCastle.phase_at(vn(h, m + @r.entry_minutes - 1))
    assert {:fight, _, _, _} = ChaosCastle.phase_at(vn(h, m + @r.entry_minutes))

    assert {:idle, next} = ChaosCastle.phase_at(vn(h, m + @r.entry_minutes + @r.run_minutes))
    assert next == DateTime.to_unix(vn(h + @r.every_hours, m))
  end

  test "mua vé, vào thành, thả quái, người trụ cuối thắng nhận thư, về Làng" do
    ua = create_user()
    ub = create_user()
    player(ua, %{level: 30, gold: 100_000})
    player(ub, %{level: 30, gold: 100_000, inv: %{@r.ticket => 1}})
    sa = join(ua)
    sb = join(ub)

    r = cmd(sa, %{"act" => "cc_buy"})
    assert r.ok and r.player.inv[@r.ticket] == 1
    assert r.player.gold == 100_000 - @r.ticket_price

    # chưa mở cửa
    r = cmd(sa, %{"act" => "cc_enter"})
    refute r.ok
    assert r.msg =~ "chưa mở"

    {:ok, _} = ChaosCastle.open_now()
    r = cmd(sa, %{"act" => "cc_enter"})
    assert r.ok and r.player.pos.map == @r.map
    refute Map.has_key?(r.player.inv, @r.ticket)
    assert r.player.view.cc.inside and r.player.view.cc.phase == "entry"
    assert cmd(sb, %{"act" => "cc_enter"}).ok
    assert ChaosCastle.status().players == 2

    # chưa hỗn chiến thì chưa được đánh nhau
    a = Session.get(ua.id)
    b = Session.get(ub.id)
    assert {:error, "Hỗn Chiến Thành chưa bắt đầu" <> _} = Slay.check(a, b)

    :ok = ChaosCastle.start_fight()
    st = ChaosCastle.status()
    assert st.phase == "fight" and st.alive == 2
    assert st.monsters == max(@r.min_monsters, @r.total - 2)
    assert length(MapServer.snapshot(@r.map).monsters) == st.monsters
    assert Slay.check(a, b) == :ok

    # B bị loại (đổi bản đồ / gục) → còn A; A hạ hết quái → thắng
    ChaosCastle.out(ub.id)
    for _ <- 1..st.monsters, do: ChaosCastle.kill(ua.id, :monster)
    wait(fn -> ChaosCastle.status().phase == "idle" end)

    wait(fn -> Session.get(ua.id).pos.map == "village" end)
    wait(fn -> Mailbox.list(ua.id) |> Enum.any?(&(&1.subject =~ "Hỗn Chiến Thành")) end)
    mail = Mailbox.list(ua.id) |> Enum.find(&(&1.subject =~ "Hỗn Chiến Thành"))
    assert mail.gold == @r.reward.winner.gold
    assert MapServer.snapshot(@r.map).monsters == []
    # B không trụ tới cuối, không hạ ai: không có thư
    refute Mailbox.list(ub.id) |> Enum.any?(&(&1.subject =~ "Hỗn Chiến Thành"))
  end

  test "hết giờ: người còn trụ nhận thưởng nhỏ; mở lại game khi đã bị loại thì về Làng" do
    ua = create_user()
    player(ua, %{level: 30, inv: %{@r.ticket => 1}})
    sa = join(ua)
    {:ok, _} = ChaosCastle.open_now()
    assert cmd(sa, %{"act" => "cc_enter"}).ok
    :ok = ChaosCastle.start_fight()
    :ok = ChaosCastle.finish_now()

    wait(fn -> Mailbox.list(ua.id) |> Enum.any?(&(&1.subject =~ "Hỗn Chiến Thành")) end)
    mail = Mailbox.list(ua.id) |> Enum.find(&(&1.subject =~ "Hỗn Chiến Thành"))
    assert mail.gold == @r.reward.survivor.gold
    wait(fn -> Session.get(ua.id).pos.map == "village" end)
  end

  test "phòng theo số lần chuyển sinh: khác mốc vào bản đồ khác, quái mạnh theo mốc phòng, mỗi phòng thắng riêng" do
    ua = create_user()
    ub = create_user()
    player(ua, %{level: 30, inv: %{@r.ticket => 1}})
    player(ub, %{level: 30, rebirths: 5, inv: %{@r.ticket => 1}})
    sa = join(ua)
    sb = join(ub)
    {:ok, _} = ChaosCastle.open_now()

    ra = cmd(sa, %{"act" => "cc_enter"})
    rb = cmd(sb, %{"act" => "cc_enter"})
    room_b = HacLong.Game.EventRooms.band(5)
    assert ra.player.pos.map == ChaosCastle.map_id(0)
    assert rb.player.pos.map == ChaosCastle.map_id(room_b)
    assert rb.player.view.cc.room == HacLong.Game.EventRooms.label(room_b)
    assert ChaosCastle.room_k(ChaosCastle.map_id(room_b)) == HacLong.Game.EventRooms.k(room_b)

    # mỗi phòng một người: mỗi phòng thả quái riêng
    :ok = ChaosCastle.start_fight()
    n = max(@r.min_monsters, @r.total - 1)
    assert length(MapServer.snapshot(ChaosCastle.map_id(0)).monsters) == n
    assert length(MapServer.snapshot(ChaosCastle.map_id(room_b)).monsters) == n

    # khác phòng thì không đồ sát nhau được (khác bản đồ)
    refute Slay.check(Session.get(ua.id), Session.get(ub.id)) == :ok

    # A hạ hết quái phòng mình → thắng phòng 0; phòng của B vẫn chạy
    for _ <- 1..n, do: ChaosCastle.kill(ua.id, :monster)
    wait(fn -> Mailbox.list(ua.id) |> Enum.any?(&(&1.subject =~ "Hỗn Chiến Thành")) end)
    assert ChaosCastle.status().phase == "fight"
    assert ChaosCastle.alive?(ub.id)
  end

  test "không đủ cấp / không có vé / không đứng cạnh Người Gác Tháp" do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Thử", "cls" => "dk"})
    p = %{p | pos: @tower, level: 30}
    {:ok, _} = ChaosCastle.open_now()

    assert {%{ok: false, msg: "Cần 1 " <> _}, _} = ChaosCastle.enter(p, 1)
    p = %{p | inv: Map.put(p.inv, @r.ticket, 1)}
    assert {%{ok: false, msg: "Cần đạt cấp" <> _}, _} = ChaosCastle.enter(%{p | level: 1}, 1)

    assert {%{ok: false, msg: "Hãy đến gặp" <> _}, _} =
             ChaosCastle.enter(%{p | pos: %{p.pos | x: 1, y: 1}}, 1)

    assert ChaosCastle.ticket_chance(%{level: @r.ticket_drop.min_level}) == @r.ticket_drop.chance
    assert ChaosCastle.ticket_chance(%{level: 1}) == 0
  end
end

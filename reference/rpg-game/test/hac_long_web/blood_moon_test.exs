defmodule HacLongWeb.BloodMoonTest do
  @moduledoc """
  Huyết Nguyệt ở Pháp Trường (DECISIONS "Pháp Trường Huyết Nguyệt"): ngày thường an toàn; mở thì đồ sát tự do, gục không
  mất vàng / không tên đỏ, về Làng, khóa vào lại; hạ người có cơ hội rơi ngọc; hết giờ top nhận ngọc qua thư; quản trị
  mở / đóng / lịch / gọi bot.
  """
  use HacLongWeb.ChannelCase

  import Ecto.Query

  alias HacLong.{Accounts, BloodMoon, Repo, Slay}
  alias HacLong.Game.{Characters, Commands, Session}
  alias HacLong.World.Maps
  alias HacLongWeb.{ClientVersion, UserSocket}

  @r HacLong.Game.Data.rules().blood_moon

  setup do
    HacLong.RateLimit.reset()
    Slay.reset()
    BloodMoon.reset()
    on_exit(fn -> BloodMoon.reset() end)
    :ok
  end

  defp arena(dx \\ 0), do: %{map: @r.map, x: 30 + dx, y: 19 + 6}

  defp player(user, attrs, pos) do
    name = "Hn #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    p = p |> Map.put(:tutorial, nil) |> Map.put(:pos, pos) |> Map.merge(attrs)
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

  defp strong, do: %{level: 40, stats: %{str: 400, agi: 100, vit: 300, ene: 20}}

  defp fight(sa, sb, ua) do
    Enum.reduce_while(1..200, nil, fn _, _ ->
      case Slay.peek(ua.id) do
        nil -> {:halt, :ok}
        %{mine: true} -> {:cont, cmd(sa, %{"act" => "attack"})}
        %{mine: false} -> {:cont, cmd(sb, %{"act" => "attack"})}
      end
    end)
  end

  defp settled(uid, n \\ 700) do
    p = Session.get(uid)

    cond do
      p.battle && p.battle.over -> p
      n == 0 -> flunk("trận đồ sát chưa được chốt")
      true -> Process.sleep(20) && settled(uid, n - 1)
    end
  end

  test "bản đồ: 60×40, không quái, nối với Làng hai chiều, có Quan Giám Trảm" do
    m = Maps.get(@r.map)
    assert {m.width, m.height} == {60, 40}
    assert m.spawns == []
    assert Enum.any?(m.portals, &(&1.to == "village"))
    assert Enum.any?(Maps.get("village").portals, &(&1.to == @r.map))
    assert Enum.any?(m.npcs, &(&1.role == "blood_moon"))
    assert BloodMoon.map_spawns() != []
  end

  test "cơ hội rơi ngọc: theo chuyển sinh hai bên, giảm khi hạ lại cùng người" do
    assert_in_delta BloodMoon.drop_chance(3, 3, 0), @r.drop_pct, 1.0e-9
    # người gục nhiều hơn 2 lần chuyển sinh: × (1 + 2 × step)
    assert_in_delta BloodMoon.drop_chance(3, 5, 0),
                    @r.drop_pct * (1 + 2 * @r.rebirth_step),
                    1.0e-9

    # chặn trần rebirth_max, sàn 0 (hạ người yếu hơn nhiều)
    assert_in_delta BloodMoon.drop_chance(0, 50, 0), @r.drop_pct * @r.rebirth_max, 1.0e-9
    assert BloodMoon.drop_chance(10, 0, 0) == 0.0
    # hạ lại lần 2, 3: × decay, × decay²
    assert_in_delta BloodMoon.drop_chance(3, 3, 2), @r.drop_pct * @r.repeat_decay ** 2, 1.0e-9
  end

  test "xếp hạng: nhiều mạng trước, bằng nhau ai đạt trước; quà chỉ cho người thật đủ mạng" do
    score = %{
      1 => %{name: "A", kills: 3, bot: false, at: 9},
      2 => %{name: "Bot", kills: 5, bot: true, at: 4},
      3 => %{name: "C", kills: 3, bot: false, at: 6},
      4 => %{name: "D", kills: 0, bot: false, at: 1}
    }

    rank = BloodMoon.ranking(score)
    assert Enum.map(rank, & &1.name) == ["Bot", "C", "A", "D"]

    assert [{%{name: "C"}, top1}, {%{name: "A"}, top2}] = BloodMoon.winners(rank)
    assert top1 == hd(@r.top_rewards) and top2 == Enum.at(@r.top_rewards, 1)
  end

  test "ngày thường an toàn; mở thì đồ sát được; gục không mất vàng, không tên đỏ, về Làng, khóa vào lại, ngọc rơi" do
    ua = create_user()
    ub = create_user()
    player(ua, Map.put(strong(), :gold, 5000), arena())
    player(ub, %{level: 10, gold: 3000}, arena(1))
    sa = join(ua)
    sb = join(ub)

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :error, %{msg: msg}
    assert msg =~ "Huyết Nguyệt"

    # ép rơi chắc chắn để kiểm đường đi của ngọc
    BloodMoon.reset(1.0)
    assert {:ok, %{open: true}} = BloodMoon.open_now(10)
    assert BloodMoon.open?()

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :ok, _
    fight(sa, sb, ua)

    pa = settled(ua.id)
    pb = settled(ub.id)
    assert pa.battle.result == "win" and pb.battle.result == "lose"
    # không mất vàng, không chuyển vàng
    assert pb.gold == 3000 and pa.gold == 5000
    assert pb.pos.map == "village"
    refute Slay.red?(ua.id)
    # ngọc vào túi người hạ
    assert Enum.count(@r.jewels, &((pa.inv[&1] || 0) > 0)) == 1
    assert Enum.any?(pa.battle.log, &(&1.text =~ "Huyết Nguyệt: nhặt được"))
    # điểm, khóa vào lại
    assert [%{name: name, kills: 1}] = BloodMoon.public().top
    assert name == pa.name
    assert BloodMoon.locked_s(ub.id) in (@r.relock_s - 2)..@r.relock_s

    assert %{ok: true} = cmd(sb, %{"act" => "leave"})
    r = cmd(sb, %{"act" => "travel", "to" => @r.map})
    assert r.ok == false and r.msg =~ "vừa gục ở Pháp Trường"

    # hết giờ (đóng sớm): top 1 nhận thư ngọc theo mức quản trị đặt
    {:ok, _} = BloodMoon.set_rewards([%{"jewel_chaos" => 5}, %{}, %{}])
    assert {:ok, %{open: false}} = BloodMoon.close_now()
    refute BloodMoon.open?()

    assert [subject] =
             Repo.all(from m in "mails", where: m.user_id == ^ua.id, select: m.subject)

    assert subject =~ "hạng 1"

    assert [%{"jewel_chaos" => 5} = items] =
             Repo.all(from m in "mails", where: m.user_id == ^ua.id, select: m.items)

    assert map_size(items) == 1
    assert Repo.all(from m in "mails", where: m.user_id == ^ub.id, select: m.id) == []
  end

  test "quản trị: mở, đóng, lịch hằng ngày, gọi bot cần mở trước; người chơi thường không dùng được" do
    admin =
      Repo.get!(Accounts.User, create_user().id)
      |> Ecto.Changeset.change(role: "admin")
      |> Repo.update!()

    player(admin, %{level: 20}, %{map: "village", x: 12, y: 14})
    sa = join(admin)

    ref = push(sa, "admin", %{"op" => "blood_moon_bots"})
    assert_reply ref, :error, %{msg: "Mở Huyết Nguyệt trước" <> _}

    ref = push(sa, "admin", %{"op" => "blood_moon_open", "minutes" => "99"})
    assert_reply ref, :error, %{msg: "Số phút phải" <> _}

    ref = push(sa, "admin", %{"op" => "blood_moon_open", "minutes" => 3})
    assert_reply ref, :ok, %{blood_moon: %{open: true, left: left}}
    assert left > 170_000
    assert_push "blood_moon", %{open: true}

    ref = push(sa, "admin", %{"op" => "blood_moon_bots"})
    assert_reply ref, :ok, %{msg: "Đã gọi " <> _}

    ref = push(sa, "admin", %{"op" => "blood_moon_close"})
    assert_reply ref, :ok, %{blood_moon: %{open: false}}

    ref = push(sa, "admin", %{"op" => "blood_moon_daily", "at" => "25:00"})
    assert_reply ref, :error, _
    ref = push(sa, "admin", %{"op" => "blood_moon_daily", "at" => "20:00"})
    assert_reply ref, :ok, %{blood_moon: %{daily: "20:00"}}
    ref = push(sa, "admin", %{"op" => "blood_moon_daily", "at" => ""})
    assert_reply ref, :ok, %{blood_moon: %{daily: nil}}

    # quà top: sai thì từ chối, đúng thì lưu (thiếu ngọc là 0), về mặc định
    bad = [%{"jewel_bless" => 100}, %{}, %{}]
    ref = push(sa, "admin", %{"op" => "blood_moon_rewards", "rewards" => bad})
    assert_reply ref, :error, %{msg: "Quà mỗi hạng" <> _}
    ref = push(sa, "admin", %{"op" => "blood_moon_rewards", "rewards" => [%{"jewel_bless" => 7}]})
    assert_reply ref, :error, _

    good = [%{"jewel_bless" => 7, "jewel_life" => 1}, %{"jewel_soul" => 2}, %{}]
    ref = push(sa, "admin", %{"op" => "blood_moon_rewards", "rewards" => good})
    assert_reply ref, :ok, %{blood_moon: %{rewards: [r1, r2, r3]}}
    assert r1 == %{"jewel_bless" => 7, "jewel_soul" => 0, "jewel_chaos" => 0, "jewel_life" => 1}
    assert r2["jewel_soul"] == 2 and Enum.all?(r3, fn {_, n} -> n == 0 end)

    ref = push(sa, "admin", %{"op" => "blood_moon_rewards", "reset" => true})
    assert_reply ref, :ok, %{blood_moon: %{rewards: rw}}
    assert rw == BloodMoon.default_rewards()

    ub = create_user()
    player(ub, %{level: 20}, %{map: "village", x: 12, y: 14})
    sb = join(ub)
    ref = push(sb, "admin", %{"op" => "blood_moon_open"})
    assert_reply ref, :error, _
  end

  test "bot được gọi: bị khóa thì chờ, ngoài Pháp Trường thì vào, trong tầm thì đồ sát, xa thì đi tới" do
    alias HacLong.Bots.Brain
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Bot", "cls" => "dk"})
    p = %{p | level: 30, pos: %{map: "village", x: 12, y: 14}}
    assert Brain.blood_job(p, nil, 1, 10) == nil
    assert {:teleport, {x, y}} = Brain.blood_job(p, nil, 1, 0)
    assert {x, y} in BloodMoon.map_spawns()

    # đang đánh quái ngoài Pháp Trường: bỏ ngang đi luôn; trận xong thì rời trận
    assert {:teleport, _} = Brain.blood_job(%{p | battle: %{over: false}}, nil, 1, 0)
    assert Brain.blood_job(%{p | battle: %{over: true}}, nil, 1, 0) == %{"act" => "leave"}

    p = %{p | pos: arena()}

    foe = fn dx, extra ->
      Map.merge(%{id: 2, x: p.pos.x + dx, y: p.pos.y, level: 30, safe: false}, extra)
    end

    me = %{id: 1, x: p.pos.x, y: p.pos.y, level: 30, safe: false}
    snap = fn others -> %{players: [me | others], monsters: []} end

    assert Brain.blood_job(p, snap.([foe.(1, %{})]), 1, 0) == {:slay, 2}
    # đang được bảo vệ / dưới cấp đồ sát thì bỏ qua
    refute match?({:slay, _}, Brain.blood_job(p, snap.([foe.(1, %{safe: true})]), 1, 0))
    refute match?({:slay, _}, Brain.blood_job(p, snap.([foe.(1, %{level: 5})]), 1, 0))
    # xa ngoài tầm: bước đi
    assert %{"act" => "move"} = Brain.blood_job(p, snap.([foe.(8, %{})]), 1, 0)
  end
end

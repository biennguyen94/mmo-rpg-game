defmodule HacLongWeb.EventRoomTest do
  @moduledoc """
  Sự kiện đánh chung theo phòng (DECISIONS "Sự kiện đánh chung theo phòng", `HacLong.EventRoom`): Quảng Trường Quỷ /
  Lâu Đài Máu chung phòng theo mốc chuyển sinh, chung máu quái, thưởng theo đóng góp; Kalima theo tổ đội.
  """
  use HacLongWeb.ChannelCase

  alias HacLong.{Accounts, EventRoom, Party}
  alias HacLong.Game.{BloodCastle, Characters, Commands, DevilSquare, Kalima, Session}
  alias HacLongWeb.{ClientVersion, UserSocket}

  @tower %{map: "village", x: 20, y: 8}

  setup do
    HacLong.RateLimit.reset()
    Application.put_env(:hac_long, :devil_square_always_open, true)

    on_exit(fn ->
      Application.delete_env(:hac_long, :devil_square_always_open)

      for {_, pid, _, _} <- DynamicSupervisor.which_children(EventRoom.Supervisor),
          do: DynamicSupervisor.terminate_child(EventRoom.Supervisor, pid)
    end)

    :ok
  end

  defp player(user, attrs) do
    name = "Er #{System.unique_integer([:positive]) |> rem(100_000)}"
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

  defp wait(pred, n \\ 150) do
    cond do
      pred.() -> :ok
      n == 0 -> flunk("chờ quá lâu")
      true -> Process.sleep(20) && wait(pred, n - 1)
    end
  end

  # bản đồ kênh vừa đẩy xuống thỏa `pred`
  defp map_push(pred) do
    receive do
      %Phoenix.Socket.Message{event: "map", payload: pl} ->
        if pred.(pl), do: pl, else: map_push(pred)
    after
      2000 -> flunk("không nhận được bản đồ phòng")
    end
  end

  @dirs [{"up", 0, -1}, {"down", 0, 1}, {"left", -1, 0}, {"right", 1, 0}]

  # đặt người chơi cạnh quái `m` của phòng rồi bước vào đánh
  defp engage(socket, user, m) do
    t = Session.get(user.id).tower
    taken = MapSet.new(t.monsters, &{&1.x, &1.y})

    {dir, x, y} =
      Enum.find_value(@dirs, fn {dir, dx, dy} ->
        {x, y} = {m.x - dx, m.y - dy}
        tile = t.tiles |> Enum.at(y, "") |> String.at(x)
        if tile == "." and not MapSet.member?(taken, {x, y}), do: {dir, x, y}
      end)

    {:ok, _} =
      Session.admin(user.id, fn p -> {:ok, %{p | pos: %{p.pos | x: x, y: y}}, "ok"} end)

    r = cmd(socket, %{"act" => "move", "dir" => dir})
    assert r.ok, inspect(r[:msg])
    assert r.player.battle
    r.player
  end

  test "Quảng Trường: cùng mốc chuyển sinh chung phòng, khác mốc phòng khác; thấy nhau trên bản đồ" do
    [ua, ub, uc] = for _ <- 1..3, do: create_user()
    ticket = %{DevilSquare.ticket() => 1}
    player(ua, %{level: 40, inv: ticket, rebirths: 0})
    player(ub, %{level: 40, inv: ticket, rebirths: 1})
    player(uc, %{level: 40, inv: ticket, rebirths: 2})
    [sa, sb, sc] = Enum.map([ua, ub, uc], &join/1)

    a = cmd(sa, %{"act" => "ds_enter"})
    assert a.ok, inspect(a[:msg])
    b = cmd(sb, %{"act" => "ds_enter"})
    c = cmd(sc, %{"act" => "ds_enter"})
    assert a.player.tower.room == b.player.tower.room
    assert a.player.tower.tiles == b.player.tower.tiles
    assert c.player.tower.room != a.player.tower.room
    # quái mạnh theo mốc cao nhất của phòng: CS 0–1 → k 1, CS 2–3 → k 3
    assert a.player.tower.k == 1 and c.player.tower.k == 3
    assert a.player.tower.room_label == "CS 0–1"

    # kênh của A nhận bản đồ phòng có cả B
    wait(fn ->
      case EventRoom.snapshot(a.player.tower.room) do
        %{players: ps} -> length(ps) == 2
        _ -> false
      end
    end)

    %{players: ps} = map_push(&(&1[:map] == "tower" and length(&1.players) == 2))
    assert Enum.any?(ps, &(&1.id == ub.id))
    wait(fn -> Session.get(ua.id).tower.people == 2 end)
  end

  test "Quảng Trường: chung máu quái; người hạ được điểm, người cùng đánh thắng theo phần sát thương" do
    [ua, ub] = for _ <- 1..2, do: create_user()
    ticket = %{DevilSquare.ticket() => 1}
    player(ua, %{level: 40, inv: ticket})
    player(ub, %{level: 40, inv: ticket})
    [sa, sb] = Enum.map([ua, ub], &join/1)
    a = cmd(sa, %{"act" => "ds_enter"})
    _ = cmd(sb, %{"act" => "ds_enter"})
    room = a.player.tower.room
    [m1, m2 | _] = a.player.tower.monsters

    # A đánh m1, B vào cùng con đó: máu B thấy là máu A để lại
    pa = engage(sa, ua, m1)
    max = pa.battle.monster.maxHp
    assert pa.battle.monster.hp == max
    assert {:alive, left} = EventRoom.hit(room, ua.id, m1.id, div(max, 2))
    pb = engage(sb, ub, m1)
    assert pb.battle.monster.hp == left

    # B hạ (gọi thẳng phòng như một đòn của B): A đang đánh cùng thì thắng, góp 50%
    assert {:killed, %{share: share}} = EventRoom.hit(room, ub.id, m1.id, left)
    assert_in_delta share, 0.5, 0.01

    wait(fn ->
      b = Session.get(ua.id).battle
      b && b.over && b.result == "win"
    end)

    pa = Session.get(ua.id)
    assert Enum.any?(pa.battle.log, &(&1.text =~ "Người khác ra đòn kết liễu"))
    assert pa.battle.monster.xp == round(pa.battle.encounter.base_xp * 0.5)
    wait(fn -> not Enum.any?(Session.get(ua.id).tower.monsters, &(&1.id == m1.id)) end)
    assert Session.get(ua.id).tower.ds.score == 0

    # A tự hạ m2 (B làm máu còn 1): A được điểm
    cmd(sa, %{"act" => "leave"})
    cmd(sb, %{"act" => "flee"})
    cmd(sb, %{"act" => "leave"})
    pa = engage(sa, ua, m2)
    assert {:alive, 1} = EventRoom.hit(room, ub.id, m2.id, pa.battle.monster.maxHp - 1)
    r = cmd(sa, %{"act" => "attack"})
    assert r.player.battle.over and r.player.battle.result == "win"
    assert r.player.tower.ds.score == DevilSquare.rules().score.monster
  end

  test "Quảng Trường: hạ hết quái, một người lên cầu thang thì cả phòng sang đợt sau; tự ra thì chỉ mình kết thúc" do
    [ua, ub] = for _ <- 1..2, do: create_user()
    ticket = %{DevilSquare.ticket() => 1}
    player(ua, %{level: 40, inv: ticket})
    player(ub, %{level: 40, inv: ticket})
    [sa, sb] = Enum.map([ua, ub], &join/1)
    a = cmd(sa, %{"act" => "ds_enter"})
    _ = cmd(sb, %{"act" => "ds_enter"})
    room = a.player.tower.room

    for m <- a.player.tower.monsters do
      {:ok, _} = EventRoom.engage(room, ua.id, m.id, 10)
      {:killed, _} = EventRoom.hit(room, ua.id, m.id, 10)
    end

    wait(fn -> Session.get(ub.id).tower.monsters == [] end)
    [sx, sy] = a.player.tower.stairs

    {:ok, _} =
      Session.admin(ua.id, fn p -> {:ok, %{p | pos: %{p.pos | x: sx, y: sy + 1}}, "ok"} end)

    r = cmd(sa, %{"act" => "move", "dir" => "up"})
    assert r.ok and r.player.tower.floor == 2

    wait(fn -> Session.get(ub.id).tower.floor == 2 end)
    pb = Session.get(ub.id)
    [ex, ey] = pb.tower.exit
    assert pb.pos == %{map: "tower", x: ex, y: ey - 1}
    assert pb.tower.monsters != []

    # B tự ra ở cổng: chỉ B về Làng, phòng còn A
    {:ok, _} =
      Session.admin(ub.id, fn p -> {:ok, %{p | pos: %{p.pos | x: ex, y: ey - 1}}, "ok"} end)

    r = cmd(sb, %{"act" => "move", "dir" => "down"})
    assert r.player.pos.map == "village" and r.player.tower == nil
    assert EventRoom.alive?(room)
    wait(fn -> Session.get(ua.id).tower.people == 1 end)
  end

  test "hết giờ: cả phòng kết thúc, nhận thưởng theo điểm của mình, về Làng" do
    [ua, ub] = for _ <- 1..2, do: create_user()
    ticket = %{BloodCastle.ticket() => 1}
    player(ua, %{level: 45, inv: ticket})
    player(ub, %{level: 45, inv: ticket})
    [sa, sb] = Enum.map([ua, ub], &join/1)
    a = cmd(sa, %{"act" => "bc_enter"})
    assert a.ok, inspect(a[:msg])
    b = cmd(sb, %{"act" => "bc_enter"})
    assert a.player.tower.room == b.player.tower.room
    [{pid, _}] = Registry.lookup(EventRoom.Registry, a.player.tower.room)
    send(pid, :time_up)

    for u <- [ua, ub], do: wait(fn -> Session.get(u.id).pos.map == "village" end)
    assert Session.get(ua.id).tower == nil
    refute EventRoom.alive?(a.player.tower.room)
  end

  test "Lâu Đài: hạ trùm, người gây nhiều sát thương nhất lên trùm nhận Lông Vũ, người khác theo phần sát thương" do
    p = %{
      gold: 0,
      xp: 0,
      level: 45,
      inv: %{},
      tower: %{bc: %{level: 50, killed: 8, mine: 3, done: false, stage: "boss"}}
    }

    p =
      Map.merge(
        Commands.run(nil, %{"act" => "create", "name" => "Bc", "cls" => "dk"}) |> elem(1),
        p
      )

    {r1, top} = EventRoom.settle(p, %{success: true, top: true, share: 0.7})
    {r2, other} = EventRoom.settle(p, %{success: true, top: false, share: 0.3})
    feather = BloodCastle.rules().reward.success.items |> Map.keys() |> hd() |> to_string()
    assert top.inv[feather] && !other.inv[feather]
    assert top.tower.bc.done and other.tower.bc.done
    assert top.gold > other.gold and other.gold > 0
    assert r1.msg =~ "nhiều sát thương nhất" and r2.msg =~ "30%"
  end

  test "Kalima tổ đội: một người dùng Bản Đồ, đồng đội vào cùng phòng không tốn; quái theo chuyển sinh cao nhất" do
    [ua, ub] = for _ <- 1..2, do: create_user()
    player(ua, %{level: 30, inv: %{Kalima.ticket() => 1}, rebirths: 0})
    player(ub, %{level: 30, rebirths: 4})
    [sa, sb] = Enum.map([ua, ub], &join/1)
    Party.invite(ua.id, ub.id)
    Party.accept(ub.id)
    assert Party.of(ua.id).members |> length() == 2

    # B chưa có phòng để vào, cũng không có bản đồ
    r = cmd(sb, %{"act" => "kal_enter"})
    refute r.ok

    a = cmd(sa, %{"act" => "kal_enter"})
    assert a.ok, inspect(a[:msg])
    assert a.player.inv[Kalima.ticket()] == nil
    assert a.player.tower.k == 4
    assert a.player.tower.room_label == "Tổ đội"

    b = cmd(sb, %{"act" => "kal_enter"})
    assert b.ok, inspect(b[:msg])
    assert b.player.tower.room == a.player.tower.room

    # hạ Kundun: cả tổ đội cùng thắng
    room = a.player.tower.room
    [{pid, _}] = Registry.lookup(EventRoom.Registry, room)

    :sys.replace_state(pid, fn s ->
      boss = %{
        id: 100,
        kind: "kundun",
        name: "Kundun",
        level: 30,
        x: 1,
        y: 1,
        elite: true,
        role: "boss"
      }

      %{s | t: %{s.t | monsters: [boss], kal: %{s.t.kal | stage: "boss"}}}
    end)

    {:ok, _} = EventRoom.engage(room, ua.id, 100, 1000)
    assert {:killed, %{end: %{success: true}}} = EventRoom.hit(room, ua.id, 100, 1000)
    wait(fn -> Session.get(ub.id).tower.kal.done end)
  end
end

defmodule HacLongWeb.SlayTest do
  @moduledoc "Đồ sát: không cần đồng ý, luân phiên lượt, thua / bỏ chạy là chết, vàng chuyển cho người thắng."
  use HacLongWeb.ChannelCase

  import Ecto.Query

  alias HacLong.{Accounts, Audit, Repo, Slay}
  alias HacLong.Game.{Characters, Commands, Session}
  alias HacLong.World.Maps
  alias HacLongWeb.{ClientVersion, UserSocket}

  setup do
    HacLong.RateLimit.reset()
    Slay.reset()
    :ok
  end

  # chỗ đứng hợp lệ ở bản đồ chung không an toàn
  defp field do
    [p | _] = Maps.get("forest_1").portals
    {x, y} = p.at
    %{map: "forest_1", x: x, y: y - 1}
  end

  defp player(user, attrs, pos \\ nil) do
    name = "Ds #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    p = p |> Map.put(:tutorial, nil) |> Map.put(:pos, pos || field()) |> Map.merge(attrs)
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

  # chờ trận của `uid` được chốt (settle chạy ở tiến trình riêng)
  defp settled(uid, n \\ 100) do
    p = Session.get(uid)

    cond do
      p.battle && p.battle.over -> p
      n == 0 -> flunk("trận đồ sát chưa được chốt")
      true -> Process.sleep(20) && settled(uid, n - 1)
    end
  end

  test "điều kiện: cấp, vùng an toàn, khác bản đồ, đang đánh" do
    {_, a} = Commands.run(nil, %{"act" => "create", "name" => "A", "cls" => "dk"})
    a = %{a | level: 20, pos: field()}
    b = %{a | name: "B"}

    assert Slay.check(a, b) == :ok
    assert {:error, "Cần đạt cấp 10" <> _} = Slay.check(%{a | level: 5}, b)
    assert {:error, "B dưới cấp 10" <> _} = Slay.check(a, %{b | level: 9})
    village = %{map: "village", x: 12, y: 14}

    assert {:error, "Đây là vùng an toàn" <> _} =
             Slay.check(%{a | pos: village}, %{b | pos: village})

    assert {:error, "Hãy đến cùng bản đồ" <> _} = Slay.check(a, %{b | pos: village})
    assert {:error, "B đang trong trận đấu."} = Slay.check(a, %{b | battle: %{}})
  end

  test "đồ sát → luân phiên lượt → người thua chết, vàng mất chuyển cho người thắng, audit sạch" do
    ua = create_user()
    ub = create_user()
    player(ua, Map.put(strong(), :gold, 5000))
    player(ub, %{level: 10, gold: 3000})
    sa = join(ua)
    sb = join(ub)

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :ok, _

    # bên bị đánh vào trận ngay, không cần đồng ý; người tấn công đi trước
    pb = Session.get(ub.id)
    assert pb.battle.live and pb.battle.encounter.mine == false
    assert pb.battle.monster.name == Session.get(ua.id).name
    assert Session.get(ua.id).battle.encounter.mine

    assert %{ok: false, msg: "Chưa tới lượt bạn."} = cmd(sb, %{"act" => "attack"})
    # đang đồ sát thì không bị đồ sát thêm
    ref = push(sb, "slay", %{"uid" => ua.id})
    assert_reply ref, :error, %{msg: _}

    Enum.reduce_while(1..200, nil, fn _, _ ->
      case Slay.peek(ua.id) do
        nil -> {:halt, :ok}
        %{mine: true} -> {:cont, cmd(sa, %{"act" => "attack"})}
        %{mine: false} -> {:cont, cmd(sb, %{"act" => "attack"})}
      end
    end)

    pa = settled(ua.id)
    pb = settled(ub.id)
    assert pa.battle.result == "win" and pb.battle.result == "lose"
    assert pb.gold == 2700 and pa.gold == 5300
    assert pa.battle.reward.gold == 300
    assert pb.deaths == 1 and pb.pos == Maps.home_spawn()
    assert pb.hp > 0

    assert [%{wager: 300, winner_id: winner}] =
             Repo.all(
               from m in "pk_matches",
                 where: m.a_id == ^ua.id and m.b_id == ^ub.id,
                 select: %{wager: m.wager, winner_id: m.winner_id}
             )

    assert winner == ua.id

    deltas =
      Repo.all(
        from l in "gold_log",
          where: l.user_id in ^[ua.id, ub.id] and l.reason == "SLAY",
          select: l.delta
      )

    assert Enum.sort(deltas) == [-300, 300]
    assert Enum.filter(Audit.run().problems, &(&1[:user_id] in [ua.id, ub.id])) == []

    # rời trận được như thường
    assert %{ok: true} = cmd(sa, %{"act" => "leave"})
  end

  test "bỏ chạy tính như gục ngã" do
    ua = create_user()
    ub = create_user()
    player(ua, %{level: 12, gold: 1000})
    player(ub, %{level: 12, gold: 500})
    sa = join(ua)
    _sb = join(ub)

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :ok, _
    assert %{ok: true} = cmd(sa, %{"act" => "flee"})

    pa = settled(ua.id)
    pb = settled(ub.id)
    assert pa.battle.result == "lose" and pb.battle.result == "win"
    assert pa.gold == 900 and pb.gold == 600
    assert pa.pos == Maps.home_spawn() and pa.deaths == 1
  end

  test "hết giờ lượt: server đánh thay, sang lượt đối thủ" do
    ua = create_user()
    ub = create_user()
    player(ua, %{level: 12})
    player(ub, %{level: 12})
    sa = join(ua)
    _sb = join(ub)

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :ok, _
    %{id: id, mine: true} = Slay.peek(ua.id)

    send(Process.whereis(Slay), {:turn_over, id, ua.id})

    Enum.reduce_while(1..100, nil, fn _, _ ->
      if Slay.peek(ub.id).mine, do: {:halt, :ok}, else: {:cont, Process.sleep(20)}
    end)

    assert %{mine: true} = Slay.peek(ub.id)
    assert Enum.any?(Session.get(ub.id).battle.log, &(&1.text =~ "hết giờ"))
  end

  test "từ chối: vùng an toàn, người không online" do
    ua = create_user()
    ub = create_user()
    uc = create_user()
    village = %{map: "village", x: 12, y: 14}
    player(ua, %{level: 12}, village)
    player(ub, %{level: 12}, village)
    player(uc, %{level: 12})
    sa = join(ua)
    _sb = join(ub)

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :error, %{msg: "Đây là vùng an toàn" <> _}

    ref = push(sa, "slay", %{"uid" => uc.id})
    assert_reply ref, :error, %{msg: "Người này không online."}
    assert Session.get(ub.id).battle == nil
  end

  test "thắng: người tấn công bị tên đỏ, người thua được bảo vệ, báo kênh thế giới" do
    ua = create_user()
    ub = create_user()
    player(ua, Map.put(strong(), :gold, 5000))
    player(ub, %{level: 10, gold: 3000})
    sa = join(ua)
    sb = join(ub)

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :ok, _

    Enum.reduce_while(1..200, nil, fn _, _ ->
      case Slay.peek(ua.id) do
        nil -> {:halt, :ok}
        %{mine: true} -> {:cont, cmd(sa, %{"act" => "attack"})}
        %{mine: false} -> {:cont, cmd(sb, %{"act" => "attack"})}
      end
    end)

    settled(ub.id)
    assert Slay.red?(ua.id) and Slay.red_s(ua.id) > 1700
    refute Slay.red?(ub.id)
    assert Slay.protected_s(ub.id) in 100..120
    assert Enum.any?(HacLong.Chat.history(), &(&1.text =~ "đã hạ"))

    # hồ sơ hiện tên đỏ; ảnh chụp bản đồ có cờ đỏ
    ref = push(sb, "inspect", %{"uid" => ua.id})
    assert_reply ref, :ok, %{profile: %{red_s: red_s}}
    assert red_s > 0

    # đang được bảo vệ thì không bị đồ sát
    assert {:error, msg} = Slay.start(ua.id, ub.id, Session.get(ua.id), Session.get(ub.id))
    assert msg =~ "đang được bảo vệ"
  end

  test "mỗi giờ đồ sát cùng một người tối đa 3 lần; tự đi đồ sát thì mất bảo vệ" do
    pa = %{name: "A", hp: 100, pos: field()}
    pb = %{name: "B", hp: 100, pos: field()}

    for _ <- 1..3 do
      {:ok, f} = Slay.start(1, 2, pa, pb)
      Slay.abort(f.id)
    end

    assert {:error, "Bạn đã đồ sát B 3 lần" <> _} = Slay.start(1, 2, pa, pb)
    # người khác vẫn đánh được
    assert {:ok, f} = Slay.start(3, 2, %{pa | name: "C"}, pb)
    Slay.abort(f.id)

    :ets.insert(:slay_marks, {{3, :safe}, System.system_time(:millisecond) + 60_000})
    assert Slay.protected_s(3) > 0
    assert {:ok, f} = Slay.start(3, 4, %{pa | name: "C"}, %{pb | name: "D"})
    Slay.abort(f.id)
    assert Slay.protected_s(3) == 0
  end

  test "tên đỏ gục: mất vàng gấp đôi, người thắng nhận hết" do
    {_, a} = Commands.run(nil, %{"act" => "create", "name" => "Thang", "cls" => "dk"})
    {_, b} = Commands.run(nil, %{"act" => "create", "name" => "Do", "cls" => "dk"})

    f = %{
      id: 7,
      a: 1,
      b: 2,
      names: %{1 => "Thang", 2 => "Do"},
      hp: %{1 => 50, 2 => 0},
      red: %{1 => false, 2 => true},
      map: "forest_1",
      turns: 3
    }

    in_slay = fn p, foe, uid ->
      {_, p} = HacLong.Game.Engine.start_with_monster(p, 0, Slay.opponent(foe, uid))

      b =
        Map.merge(p.battle, %{live: true, encounter: %{slay: 7, foe: uid, mine: false, until: 0}})

      %{p | battle: b, pos: field()}
    end

    pw = in_slay.(%{a | gold: 1000}, b, 2)
    pl = in_slay.(%{b | gold: 1000}, a, 1)
    {pw2, pl2, lost} = Slay.outcome(f, pw, pl, 1, :ko)

    assert lost == 200 and pl2.gold == 800 and pw2.gold == 1200
    assert pl2.battle.result == "lose" and pw2.battle.result == "win"
    assert Enum.any?(pl2.battle.log, &(&1.text =~ "Tên đỏ"))
  end
end

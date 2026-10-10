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
end

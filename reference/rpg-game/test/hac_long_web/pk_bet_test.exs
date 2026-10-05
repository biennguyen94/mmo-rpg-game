defmodule HacLongWeb.PkBetTest do
  @moduledoc "Phase 5 (H7 + H8): PK cược vàng — trận tự đánh thuần, mời / nhận / từ chối / hết hạn qua kênh, vàng + audit."
  use HacLongWeb.ChannelCase

  import Ecto.Query

  alias HacLong.{Accounts, Arena, Audit, PkBet, Repo}
  alias HacLong.Game.{Characters, Commands, PkFight, Rng, Session}
  alias HacLongWeb.{ClientVersion, UserSocket}

  setup do
    HacLong.RateLimit.reset()
    PkBet.reset()
    on_exit(&Rng.clear/0)
    :ok
  end

  defp player(user, attrs) do
    name = "Pk #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    p = p |> Map.put(:tutorial, nil) |> Map.put(:pos, %{map: "village", x: 12, y: 14})
    p = Map.merge(p, attrs)
    {p, _} = HacLong.Game.Achievements.check(p)
    Characters.save!(user.id, p, "TEST")
    p
  end

  defp join(user) do
    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})
    {:ok, _reply, socket} = subscribe_and_join(socket, "game", %{"v" => ClientVersion.current()})
    socket
  end

  describe "trận tự đánh (thuần)" do
    test "bên mạnh hơn thắng; cùng dãy số thì cùng kết quả" do
      {_, weak} = Commands.run(nil, %{"act" => "create", "name" => "Yeu", "cls" => "dw"})
      {_, strong} = Commands.run(nil, %{"act" => "create", "name" => "Manh", "cls" => "dk"})
      strong = %{strong | level: 40, stats: Map.new(strong.stats, fn {k, v} -> {k, v * 5} end)}

      Rng.put_sequence([0.5, 0.3, 0.7, 0.9, 0.1])
      r1 = PkFight.fight(Arena.opponent(strong, 1), Arena.opponent(weak, 2))
      Rng.put_sequence([0.5, 0.3, 0.7, 0.9, 0.1])
      r2 = PkFight.fight(Arena.opponent(strong, 1), Arena.opponent(weak, 2))

      assert r1.winner == :a and r1 == r2
      assert r1.hp.b == 0 and r1.rounds >= 1
      assert List.last(r1.log).text =~ "Manh thắng"

      # đổi chỗ: người mời yếu vẫn thua
      Rng.put_sequence([0.5])
      assert PkFight.fight(Arena.opponent(weak, 2), Arena.opponent(strong, 1)).winner == :b
    end

    test "hai bản sao không làm gì được nhau quá số lượt: hòa" do
      {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Hoa", "cls" => "dk"})
      a = %{Arena.opponent(p, 1) | maxHp: 10_000, hp: 10_000, dodge: 0.0, crit: 0.0}

      # cùng chỉ số, không né, không chí mạng, đòn cố định → máu hai bên giảm như nhau
      Rng.put_sequence([0.5])
      r = PkFight.fight(a, %{a | name: "Hoa 2"})
      assert r.winner == :draw and r.rounds == PkBet.rules().rounds
    end
  end

  describe "qua kênh + database" do
    test "mời → nhận: người thắng +cược, người thua −cược, một dòng pk_matches, nhật ký PK_BET, audit sạch" do
      ua = create_user()
      ub = create_user()
      player(ua, %{gold: 5000, level: 40})
      player(ub, %{gold: 3000})
      sa = join(ua)
      sb = join(ub)

      ref = push(sa, "pk", %{"op" => "invite", "uid" => ub.id, "wager" => 1000})
      assert_reply ref, :ok, %{invite: %{wager: 1000, incoming: false}}
      assert_push "pk_invite", %{invite: %{from: from, wager: 1000}}
      assert from == ua.id

      ref = push(sb, "pk", %{"op" => "accept"})
      assert_reply ref, :ok, %{result: %{winner: winner, wager: 1000, log: [_ | _]}, today: 1}
      assert_push "pk_result", %{id: id}

      ga = Session.get(ua.id).gold
      gb = Session.get(ub.id).gold
      assert ga + gb == 8000

      if winner == ua.id, do: assert({ga, gb} == {6000, 2000})
      if winner == ub.id, do: assert({ga, gb} == {4000, 4000})

      assert [%{winner_id: ^winner}] =
               Repo.all(
                 from m in "pk_matches", where: m.id == ^id, select: %{winner_id: m.winner_id}
               )

      reasons =
        Repo.all(
          from l in "gold_log",
            where: l.user_id in ^[ua.id, ub.id] and l.reason == "PK_BET",
            select: {l.ref, l.delta}
        )

      if winner,
        do: assert(Enum.sort(reasons) == Enum.sort([{"pk:#{id}", 1000}, {"pk:#{id}", -1000}]))

      assert Enum.filter(Audit.run().problems, &(&1[:user_id] in [ua.id, ub.id])) == []
    end

    test "không đủ vàng, cược ngoài giới hạn, tự mời mình, người không online" do
      ua = create_user()
      ub = create_user()
      uc = create_user()
      player(ua, %{gold: 500})
      player(ub, %{gold: 50})
      player(uc, %{})
      sa = join(ua)
      _ = join(ub)

      ref = push(sa, "pk", %{"op" => "invite", "uid" => ub.id, "wager" => 1000})
      assert_reply ref, :error, %{msg: msg}
      assert msg =~ "không đủ"

      ref = push(sa, "pk", %{"op" => "invite", "uid" => ub.id, "wager" => 10})
      assert_reply ref, :error, %{msg: "Cược từ" <> _}

      ref = push(sa, "pk", %{"op" => "invite", "uid" => uc.id, "wager" => 100})
      assert_reply ref, :error, %{msg: "Người này không online."}

      # B chỉ có 50 vàng: lời mời gửi được, nhận thì không ai mất gì
      ref = push(sa, "pk", %{"op" => "invite", "uid" => ub.id, "wager" => 100})
      assert_reply ref, :ok, _
      {:ok, inv} = PkBet.take(ub.id)
      assert {:error, msg} = PkBet.execute(inv)
      assert msg =~ "không đủ"
      assert Session.get(ua.id).gold == 500 and Session.get(ub.id).gold == 50
      assert PkBet.today_count(ua.id) == 0
    end

    test "từ chối và hết hạn: lời mời biến mất, báo người mời" do
      ua = create_user()
      ub = create_user()
      player(ua, %{gold: 5000})
      player(ub, %{gold: 5000})
      sa = join(ua)
      sb = join(ub)

      ref = push(sa, "pk", %{"op" => "invite", "uid" => ub.id, "wager" => 200})
      assert_reply ref, :ok, _
      ref = push(sb, "pk", %{"op" => "decline"})
      assert_reply ref, :ok, %{invite: nil}
      assert PkBet.of(ua.id) == nil

      ref = push(sa, "pk", %{"op" => "invite", "uid" => ub.id, "wager" => 200})
      assert_reply ref, :ok, _
      # giả lập hết giờ
      inv = :sys.get_state(PkBet).by_to[ub.id]
      send(PkBet, {:expire, ub.id, inv.ref})
      _ = PkBet.of(ua.id)
      assert PkBet.of(ub.id) == nil
      assert_push "notice", %{msg: "⚔ Lời mời cược đấu đã hết hạn."}
      ref = push(sb, "pk", %{"op" => "accept"})
      assert_reply ref, :error, %{msg: "Lời mời không còn nữa."}
    end
  end
end

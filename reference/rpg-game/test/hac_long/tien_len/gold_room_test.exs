defmodule HacLong.TienLen.GoldRoomTest do
  @moduledoc """
  Phase 17: bàn Tiến Lên trả bằng vàng Hắc Long qua `HacLong.TienLen.Gold` (luật T20–T25 của
  repo gốc, kịch bản lấy từ `coins_room_test.exs`), lưu ván (`Records`), kênh `tl`.
  """
  use HacLongWeb.ChannelCase

  import Ecto.Query

  alias HacLong.{Accounts, Audit, Repo}
  alias HacLong.Game.{Characters, Commands, Session}
  alias HacLong.TienLen.{Card, Gold, Records, RoomServer}
  alias HacLongWeb.{ClientVersion, UserSocket}

  setup do
    HacLong.RateLimit.reset()
    :ok
  end

  defp cards(codes), do: Card.parse_many!(codes)

  defp player!(gold) do
    u = create_user()
    name = "Tl #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    p = p |> Map.put(:tutorial, nil) |> Map.put(:gold, gold)
    {p, _} = HacLong.Game.Achievements.check(p)
    Characters.save!(u.id, p, "TEST")
    {u, name}
  end

  defp gold(uid), do: Session.get(uid).gold

  defp room!(stake, hands) do
    deal = {:hands, Map.new(hands, fn {seat, codes} -> {seat, cards(codes)} end)}

    {:ok, id} =
      RoomServer.start_room(stake: stake, economy: Gold, recorder: Records, deals: [deal])

    pid = RoomServer.whereis(id)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
    RoomServer.subscribe(id)
    id
  end

  test "cược 100, 3 người: chặt heo, tiền hạng, thối heo trả bằng vàng; tổng không đổi; lưu ván" do
    [{a, an}, {b, bn}, {c, cn}] = Enum.map(1..3, fn _ -> player!(1000) end)

    id =
      room!(100, %{
        0 => "3D 2H",
        1 => "4S 4C 5S 5C 6S 6C 9D 2C",
        2 => "7S 7C 8S 8C 9S 9C 10D 2S"
      })

    for {u, n} <- [{a, an}, {b, bn}, {c, cn}], do: {:ok, _} = RoomServer.join(id, u.id, n)
    :ok = RoomServer.start_game(id, a.id)

    play = fn u, codes -> assert :ok == RoomServer.play(id, u.id, cards(codes)) end
    pass = fn u -> assert :ok == RoomServer.pass(id, u.id) end

    play.(a, "3D")
    pass.(b)
    pass.(c)
    play.(a, "2H")
    play.(b, "4S 4C 5S 5C 6S 6C")
    play.(c, "7S 7C 8S 8C 9S 9C")
    pass.(b)
    play.(c, "10D")
    pass.(b)
    play.(c, "2S")

    assert gold(a.id) == 1_100
    assert gold(b.id) == 400
    assert gold(c.id) == 1_500

    deltas =
      Repo.all(
        from l in "gold_log",
          where: l.user_id in ^[a.id, b.id, c.id] and l.reason == "TIENLEN",
          select: l.delta
      )

    assert Enum.sum(deltas) == 0 and length(deltas) >= 3
    assert Enum.filter(Audit.run().problems, &(&1[:user_id] in [a.id, b.id, c.id])) == []

    view = RoomServer.view(id, a.id)
    assert view.coin_deltas == %{0 => 100, 1 => -600, 2 => 500}
    assert view.balances == %{0 => 1_100, 1 => 400, 2 => 1_500}

    # ván được lưu, ai ngồi trong ván mới xem lại được
    assert [%{place: 1, coins: 100, players: [_, _, _]} = g] = Records.list(a.id)
    assert %{replay: %{"events" => [_ | _]}} = Records.get(g.id, b.id)
    assert Records.get(g.id, create_user().id) == nil
  end

  test "trả một lần cho mỗi khóa; thiếu vàng thì trả tối đa số đang có, chia theo tỉ lệ" do
    {a, _} = player!(1000)
    {b, _} = player!(90)
    {c, _} = player!(0)

    debts = [
      %{from: b.id, to: a.id, amount: 100, reason: "place"},
      %{from: b.id, to: c.id, amount: 200, reason: "chop"}
    ]

    assert {:ok, paid} = Gold.settle("test:k1", debts)
    assert Enum.map(paid, & &1.amount) |> Enum.sum() == 90
    assert gold(b.id) == 0 and gold(a.id) + gold(c.id) == 1090
    assert {:ok, :already_applied} = Gold.settle("test:k1", debts)
    assert gold(a.id) + gold(c.id) == 1090

    assert {:error, :insufficient_coins} = Gold.spend(c.id, 1000, "throw", "x")
    assert {:ok, left} = Gold.spend(a.id, 5, "throw", "🍅")
    assert left == gold(a.id)
  end

  test "qua kênh: mở phòng, thêm 3 máy, chia bài, đánh tới hết ván" do
    {u, _} = player!(1000)
    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(u)})
    {:ok, _, s} = subscribe_and_join(socket, "game", %{"v" => ClientVersion.current()})

    tl = fn payload ->
      ref = push(s, "tl", payload)
      assert_reply ref, status, reply
      {status, reply}
    end

    assert {:ok, %{rooms: _, phrases: [_ | _]}} = tl.(%{"op" => "lobby"})
    assert {:error, %{msg: "Tiền cược" <> _}} = tl.(%{"op" => "create", "stake" => 5})
    assert {:ok, %{view: %{me: 0, host: 0}}} = tl.(%{"op" => "create"})

    for _ <- 1..3, do: assert({:ok, _} = tl.(%{"op" => "add_bot", "level" => "easy"}))
    assert {:ok, _} = tl.(%{"op" => "start"})
    assert_push "tl", %{view: %{status: _}}

    # đánh nước gợi ý đầu tiên mỗi khi tới lượt, tới khi hết ván
    Enum.reduce_while(1..400, nil, fn _, _ ->
      {:ok, %{view: v}} = tl.(%{"op" => "view"})

      cond do
        v.status == :waiting and v.games_played == 1 ->
          {:halt, :ok}

        v.game && v.game.current == 0 ->
          {:ok, %{hints: hints}} = tl.(%{"op" => "hints"})

          case hints do
            [first | _] -> tl.(%{"op" => "play", "cards" => first})
            [] -> tl.(%{"op" => "pass"})
          end

          {:cont, nil}

        true ->
          Process.sleep(10)
          {:cont, nil}
      end
    end)

    assert {:ok, %{view: %{games_played: 1}}} = tl.(%{"op" => "view"})
    assert {:error, %{msg: "Chưa có ván nào"}} = tl.(%{"op" => "pass"})
    assert {:ok, _} = tl.(%{"op" => "leave"})
    assert {:error, %{msg: "Bạn không ở trong phòng" <> _}} = tl.(%{"op" => "view"})
  end
end

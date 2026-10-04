defmodule HacLongWeb.DupeTest do
  @moduledoc """
  Chống nhân bản (FEATURE_CATALOG N5): bắn nhiều lệnh đụng cùng vàng / đồ **song song** — giao dịch
  trực tiếp đang chốt, rao chợ, mua chợ, rút hàng, nhận thư, bán cho cửa hàng — rồi kiểm:

  - tổng vàng của mọi bên (cộng tiền còn trong thư chưa nhận) không tăng;
  - mỗi món đồ thường đếm đủ, không hơn (túi hai người + hàng còn trên chợ);
  - đồ hiếm (`uid`) chỉ nằm đúng một chỗ;
  - `HacLong.Audit` không báo lỗi (vàng khớp nhật ký, không trùng `uid`).

  Mỗi kịch bản lặp vài lần với người chơi mới để tăng cơ hội gặp thứ tự xấu.
  """
  use HacLongWeb.ChannelCase

  import Ecto.Query

  alias HacLong.{Accounts, Audit, Mailbox, Market, Repo, Trade}
  alias HacLong.Game.{Characters, Commands, Session, TradeOffer}
  alias HacLongWeb.{ClientVersion, UserSocket}

  # cạnh Chủ Chợ (7, 15) và cạnh Thợ Rèn (8, 12)
  @market %{map: "village", x: 7, y: 14}
  @smith %{map: "village", x: 8, y: 11}
  @rounds 4

  setup do
    HacLong.RateLimit.reset()
    Trade.reset()
    :ok
  end

  defp player(user, attrs) do
    name = "Dp #{System.unique_integer([:positive]) |> rem(1_000_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    p = p |> Map.put(:tutorial, nil) |> Map.merge(attrs)
    {p, _} = HacLong.Game.Achievements.check(p)
    Characters.save!(user.id, p, "TEST")
    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})
    {:ok, _, _} = subscribe_and_join(socket, "game", %{"v" => ClientVersion.current()})
    p
  end

  defp sword do
    %{uid: "#DP#{System.unique_integer([:positive])}", base: "club", rarity: 3, bonus: %{str: 5}}
  end

  # bắn mọi hàm cùng lúc, chờ hết (kết quả từng lệnh không quan trọng, chỉ trạng thái cuối)
  defp burst(funs) do
    funs
    |> Enum.map(&Task.async/1)
    |> Enum.each(&Task.yield(&1, 10_000))
  end

  # giao dịch đang chốt (executing) thì chờ xong; xong rồi hoặc trả về bàn (open) thì thôi
  defp wait_idle(uids) do
    Enum.reduce_while(1..100, nil, fn _, _ ->
      if Enum.any?(uids, &match?(%{status: :executing}, Trade.of(&1))),
        do: {:cont, Process.sleep(20)},
        else: {:halt, :ok}
    end)
  end

  defp cmd(uid, c), do: fn -> Session.command(uid, c) end

  defp listings(uids) do
    Repo.all(
      from l in "market_listings",
        where: l.seller_id in ^uids and is_nil(l.sold_at),
        select: %{id: l.id, item: l.item, count: l.count, gear: l.gear, price: l.price}
    )
  end

  defp unclaimed_gold(uids) do
    Repo.one(
      from m in "mails",
        where: m.user_id in ^uids and is_nil(m.claimed_at),
        select: coalesce(sum(m.gold), 0)
    )
    |> then(&if(is_integer(&1), do: &1, else: Decimal.to_integer(&1)))
  end

  defp gold(uids), do: uids |> Enum.map(&Session.get(&1).gold) |> Enum.sum()

  defp item_count(uids, id) do
    held = uids |> Enum.map(&Map.get(Session.get(&1).inv, id, 0)) |> Enum.sum()

    listed =
      uids |> listings() |> Enum.filter(&(&1.item == id)) |> Enum.map(& &1.count) |> Enum.sum()

    held + listed
  end

  defp gear_places(uids, gid) do
    held = Enum.count(uids, fn u -> Enum.any?(Session.get(u).gear || [], &(&1.uid == gid)) end)
    listed = uids |> listings() |> Enum.count(&(&1.gear && &1.gear["uid"] == gid))
    held + listed
  end

  defp clean_audit(uids), do: Enum.filter(Audit.run().problems, &(&1[:user_id] in uids))

  test "giao dịch đang chốt + rao chợ + nhận thư + bán cùng lúc: không sinh vàng / đồ" do
    for round <- 1..@rounds do
      # vòng lẻ: lệnh khác tranh đúng món đang giao dịch; vòng chẵn: chỉ đụng vàng (nhận thư) trong
      # lúc giao dịch đang chốt — giao dịch phải xong
      fight? = rem(round, 2) == 1
      s = sword()
      ua = create_user()
      ub = create_user()
      pa = player(ua, %{gold: 1000, inv: %{"herb" => 5, "dagger" => 1}, gear: [s], pos: @market})
      pb = player(ub, %{gold: 1000, inv: %{"herb" => 2}, pos: @market})
      :ok = Mailbox.send(ua.id, %{subject: "đền bù", gold: 500})
      [mail] = Mailbox.list(ua.id)
      uids = [ua.id, ub.id]
      total0 = gold(uids) + unclaimed_gold(uids)

      :ok = Trade.request(ua.id, pa.name, ub.id)
      :ok = Trade.accept(ub.id, pb.name)

      {:ok, oa} =
        TradeOffer.parse(pa, %{"items" => %{"herb" => 5}, "gear" => [s.uid], "gold" => 800})

      {:ok, ob} = TradeOffer.parse(pb, %{"items" => %{"herb" => 2}, "gold" => 100})
      :ok = Trade.offer(ua.id, oa)
      :ok = Trade.offer(ub.id, ob)
      :ok = Trade.ready(ua.id)

      claims = for _ <- 1..3, do: cmd(ua.id, %{"act" => "mail_claim", "id" => mail.id})
      sell = &cmd(&1, %{"act" => "market_sell", "id" => &2, "count" => &3, "price" => 10})

      grabs =
        if fight? do
          [sell.(ua.id, "herb", 5), sell.(ua.id, s.uid, 1), sell.(ub.id, "herb", 2)] ++
            for _ <- 1..4, do: sell.(ua.id, "herb", 1)
        else
          [fn -> Trade.ready(ub.id) end]
        end

      burst([fn -> Trade.ready(ub.id) end] ++ claims ++ grabs)
      wait_idle(uids)
      unless fight?, do: assert(Trade.of(ua.id) == nil and gear_places([ub.id], s.uid) == 1)

      IO.inspect(
        {Trade.of(ua.id) && Trade.of(ua.id).status, Session.get(ub.id).inv,
         Session.get(ua.id).gold, listings(uids) |> length()},
        label: "DBG"
      )

      assert gold(uids) + unclaimed_gold(uids) == total0
      assert item_count(uids, "herb") == 7
      assert gear_places(uids, s.uid) == 1
      assert clean_audit(uids) == []
    end
  end

  test "mua cùng một món chợ từ nhiều người + người bán rút về cùng lúc: chỉ một người được" do
    for _ <- 1..@rounds do
      us = create_user()
      s = sword()
      player(us, %{gold: 0, gear: [s], pos: @market})

      {%{ok: true}, _} =
        Session.command(us.id, %{"act" => "market_sell", "id" => s.uid, "price" => 300})

      [l] = listings([us.id])

      buyers = for _ <- 1..4, do: create_user()
      Enum.each(buyers, &player(&1, %{gold: 1000, pos: @market}))
      uids = [us.id | Enum.map(buyers, & &1.id)]
      total0 = gold(uids) + unclaimed_gold(uids)

      burst(
        [cmd(us.id, %{"act" => "market_cancel", "listing" => l.id})] ++
          Enum.map(buyers, &cmd(&1.id, %{"act" => "market_buy", "listing" => l.id}))
      )

      # người bán nhận tiền qua thư (trừ phí chợ): tổng vàng chỉ có thể giảm đúng phần phí
      fee = div(300 * Market.fee_pct(), 100)
      now = gold(uids) + unclaimed_gold(uids)
      assert now == total0 or now == total0 - fee
      assert gear_places(uids, s.uid) == 1
      assert clean_audit(uids) == []
    end
  end

  test "bán cho cửa hàng + giao dịch cùng một món hiếm: món chỉ đi một đường" do
    for _ <- 1..@rounds do
      s = sword()
      ua = create_user()
      ub = create_user()
      pa = player(ua, %{gold: 100, gear: [s], pos: @smith})
      pb = player(ub, %{gold: 100, pos: @smith})
      uids = [ua.id, ub.id]

      :ok = Trade.request(ua.id, pa.name, ub.id)
      :ok = Trade.accept(ub.id, pb.name)
      {:ok, oa} = TradeOffer.parse(pa, %{"gear" => [s.uid]})
      :ok = Trade.offer(ua.id, oa)
      :ok = Trade.ready(ua.id)

      burst([
        fn -> Trade.ready(ub.id) end,
        cmd(ua.id, %{"act" => "sell", "id" => s.uid}),
        cmd(ua.id, %{"act" => "sell", "id" => s.uid})
      ])

      wait_idle(uids)
      sold? = gear_places(uids, s.uid) == 0

      # bán được thì đúng một lần (vàng tăng đúng giá một lần), không thì món nằm ở đúng một người
      if sold? do
        assert gold(uids) == 200 + HacLong.Game.Gear.price(s)
      else
        assert gear_places(uids, s.uid) == 1 and gold(uids) == 200
      end

      assert clean_audit(uids) == []
    end
  end
end

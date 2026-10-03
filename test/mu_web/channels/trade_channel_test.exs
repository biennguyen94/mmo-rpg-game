defmodule MuWeb.TradeChannelTest do
  @moduledoc """
  P5-M4 (P5-5, KB_TECHNICAL §10) qua kênh thật: mời / nhận / từ chối, đặt đồ + Zen, khóa → đồng
  ý → chốt một transaction (đồ + Zen đổi chủ, audit `TRADE`, `mu.audit` sạch), mọi thay đổi bỏ
  khóa, chốt hỏng giữ giao dịch mở, đồ trên bàn bị vứt thì tự gỡ, hủy khi mất kết nối / đi xa,
  luật mời (tầm, chính mình, đang giao dịch), cố dupe (chốt song song với bán).
  """
  use MuWeb.ChannelCase

  import Ecto.Query, only: [from: 2]

  alias Mu.Game.{Item, ItemAudit, ItemLocation, Items, Session, ZenAudit}
  alias Mu.World.MapServer
  alias MuWeb.GameChannel
  alias Phoenix.Socket.Message

  @map "lorencia"

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  defp player(zen \\ 0) do
    {a, c} = create_character()
    {:ok, _} = ZenAudit.admin_set(c.id, zen, "test")
    {:ok, _, socket} = join_game(a, Mu.Repo.get!(Mu.Game.Character, c.id))
    %{a: a, c: c, s: socket, name: c.name}
  end

  defp cmd(p, act, payload \\ %{}) do
    Mu.RateLimit.reset()

    ref =
      push(
        p.s,
        "cmd",
        Map.merge(%{"act" => act, "rid" => "r#{System.unique_integer([:positive])}"}, payload)
      )

    assert_reply ref, status, reply
    if status == :ok, do: :ok, else: {:error, reply.error}
  end

  defp give(p, tid, quantity \\ 1) do
    before = MapSet.new(Items.load(p.c.id), & &1.id)

    {:ok, _} =
      Items.pickup(
        p.c.id,
        %{serial: Mu.Ulid.generate(), template_id: tid, quantity: quantity},
        "test"
      )

    items = Items.load(p.c.id)
    :sys.replace_state(Session.whereis(p.a.id), &%{&1 | items: items})
    Enum.find(items, &(&1.template_id == tid and not MapSet.member?(before, &1.id))).id
  end

  defp place(p, {x, y}) do
    MapServer.debug_update(@map, fn st ->
      update_in(st.players[p.c.id], &%{&1 | x: x, y: y, path: []})
    end)
  end

  defp got(p, ev, acc \\ []) do
    jr = p.s.join_ref

    receive do
      %Message{event: ^ev, join_ref: ^jr, payload: x} -> got(p, ev, [x | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end

  defp last(p, ev), do: List.last(got(p, ev))
  defp owner(item_id), do: Mu.Repo.get(ItemLocation, item_id)
  defp zen(p), do: Mu.Repo.get!(Mu.Game.Character, p.c.id).zen

  defp open(a, b) do
    :ok = cmd(a, "trade_request", %{"to" => b.name})
    :ok = cmd(b, "trade_accept", %{"from" => a.name})
  end

  setup do
    MapServer.debug_update(@map, fn st -> %{st | monsters: %{}} end)
    :ok
  end

  test "mời → nhận → đặt đồ + Zen → khóa → đồng ý: đồ + Zen đổi chủ trong một transaction, audit sạch" do
    {a, b} = {player(1_000), player(0)}
    sword = give(a, "sword_t0")
    pots = give(b, "hp_potion_small", 5)

    :ok = cmd(a, "trade_request", %{"to" => String.upcase(b.name)})
    assert %{from: from} = last(b, "trade_invite")
    assert from == a.name
    :ok = cmd(b, "trade_accept", %{"from" => a.name})
    assert %{state: "open", partner: pb, mine: %{items: []}} = last(a, "trade")
    assert pb == b.name

    :ok = cmd(a, "trade_put", %{"itemId" => sword})
    :ok = cmd(a, "trade_zen", %{"amount" => 300})
    :ok = cmd(b, "trade_put", %{"itemId" => pots})
    assert %{theirs: %{items: [%{id: ^sword}], zen: 300}} = last(b, "trade")

    # đồng ý khi chưa khóa đủ hai bên → FORBIDDEN
    :ok = cmd(a, "trade_lock")
    assert {:error, "FORBIDDEN"} = cmd(a, "trade_confirm")
    :ok = cmd(b, "trade_lock")
    :ok = cmd(a, "trade_confirm")
    assert %{mine: %{confirmed: false}, theirs: %{confirmed: true}} = last(b, "trade")
    :ok = cmd(b, "trade_confirm")

    assert %{state: "closed", result: "done"} = last(a, "trade")
    assert %{character_id: cb} = owner(sword)
    assert cb == b.c.id
    assert owner(pots).character_id == a.c.id
    assert {zen(a), zen(b)} == {700, 300}

    # Session bên nhận đọc lại túi + Zen (event player)
    assert Enum.any?(List.last(got(b, "player")).inventory, &(&1.id == sword))

    assert Mu.Repo.exists?(
             from(x in ItemAudit, where: x.item_id == ^sword and x.action == "TRADE")
           )

    assert Mu.Audit.run().problems == []
    assert Mu.Trade.whereis(a.c.id) == nil and Mu.Trade.whereis(b.c.id) == nil
  end

  test "thay đổi sau khi khóa bỏ khóa cả hai; bàn đã khóa không đổi được; đồ trên bàn bị vứt thì tự gỡ" do
    {a, b} = {player(), player()}
    s1 = give(a, "sword_t0")
    s2 = give(a, "shield_t0")
    open(a, b)
    :ok = cmd(a, "trade_put", %{"itemId" => s1})
    :ok = cmd(b, "trade_lock")
    assert {:error, "INVALID_TARGET"} = cmd(a, "trade_put", %{"itemId" => s1})
    :ok = cmd(a, "trade_put", %{"itemId" => s2})
    assert %{theirs: %{locked: false}, mine: %{locked: false}} = last(b, "trade")

    :ok = cmd(a, "trade_lock")
    assert {:error, "FORBIDDEN"} = cmd(a, "trade_take", %{"itemId" => s1})
    assert {:error, "NOT_ENOUGH_ZEN"} = cmd(b, "trade_zen", %{"amount" => 5})

    # vứt món trên bàn xuống đất → món biến khỏi bàn, khóa bỏ
    :ok = cmd(a, "trade_cancel")
    open(a, b)
    :ok = cmd(a, "trade_put", %{"itemId" => s1})
    :ok = cmd(a, "drop", %{"itemId" => s1})
    Process.sleep(50)
    assert %{mine: %{items: []}} = last(a, "trade")
  end

  test "chốt hỏng (túi bên nhận đầy) → giao dịch vẫn mở, bỏ khóa, báo lỗi; không ai mất gì" do
    {a, b} = {player(), player()}
    sword = give(a, "sword_t0")
    # túi B đầy: 64 stack potion (mỗi lần một stack mới vì stack tối đa 99)
    for _ <- 1..64, do: give(b, "hp_potion_small", 99)
    open(a, b)
    :ok = cmd(a, "trade_put", %{"itemId" => sword})
    :ok = cmd(a, "trade_lock")
    :ok = cmd(b, "trade_lock")
    :ok = cmd(a, "trade_confirm")
    assert {:error, "INVENTORY_FULL"} = cmd(b, "trade_confirm")
    assert %{state: "open", error: "INVENTORY_FULL", mine: %{locked: false}} = last(a, "trade")
    assert owner(sword).character_id == a.c.id
  end

  test "luật mời: chính mình / không có / xa → lỗi; đang giao dịch → FORBIDDEN; từ chối báo người mời" do
    {a, b, c} = {player(), player(), player()}
    assert {:error, "INVALID_TARGET"} = cmd(a, "trade_request", %{"to" => a.name})
    assert {:error, "INVALID_TARGET"} = cmd(a, "trade_request", %{"to" => "KhongCo99"})
    place(b, {24, 40})
    place(a, {14, 30})
    assert {:error, "OUT_OF_RANGE"} = cmd(a, "trade_request", %{"to" => b.name})
    place(b, {15, 30})
    place(c, {16, 30})

    :ok = cmd(a, "trade_request", %{"to" => b.name})
    assert {:error, "FORBIDDEN"} = cmd(a, "trade_request", %{"to" => c.name})
    :ok = cmd(b, "trade_decline", %{"from" => a.name})
    assert %{state: "closed", result: "declined"} = last(a, "trade")
    assert {:error, "INVALID_TARGET"} = cmd(b, "trade_accept", %{"from" => a.name})

    open(a, b)
    assert {:error, "FORBIDDEN"} = cmd(c, "trade_request", %{"to" => a.name})
  end

  test "hủy: đi xa > cancelRange, mất kết nối" do
    {a, b} = {player(), player()}
    place(a, {14, 30})
    place(b, {15, 30})
    open(a, b)
    place(b, {14 + Mu.Game.Config.get(["trade", "cancelRange"]) + 2, 30})
    Process.sleep(1_200)
    assert %{state: "closed", result: "far"} = last(a, "trade")

    place(b, {15, 30})
    open(a, b)
    Process.unlink(b.s.channel_pid)
    close(b.s)
    Process.sleep(100)
    assert %{state: "closed", result: "disconnect"} = last(a, "trade")
    assert Mu.Trade.whereis(a.c.id) == nil
  end

  test "cố dupe: chốt giao dịch song song với bán chính món đó — chỉ một bên thành công" do
    {a, b} = {player(), player()}

    for _ <- 1..5 do
      sword = give(a, "sword_t0")

      res =
        [
          fn ->
            Items.trade(
              %{cid: a.c.id, items: [sword], zen: 0},
              %{cid: b.c.id, items: [], zen: 0},
              "t"
            )
          end,
          fn -> Items.sell(a.c.id, sword, nil, 500, "npc") end
        ]
        |> Task.async_stream(& &1.())
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.count(res, &match?({:ok, _}, &1)) == 1
      assert Mu.Repo.aggregate(from(i in Item, where: i.id == ^sword), :count) <= 1
    end

    assert Mu.Audit.run().problems == []
  end
end

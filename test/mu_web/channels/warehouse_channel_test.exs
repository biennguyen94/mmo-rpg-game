defmodule MuWeb.WarehouseChannelTest do
  @moduledoc "P3-M3 qua kênh thật: mở kho ở Thủ kho, gửi / rút bằng `move_item`, tầm npcRange."
  use MuWeb.ChannelCase

  alias Mu.Game.Items
  alias Mu.World.MapServer
  alias MuWeb.GameChannel

  @map "lorencia"
  @npc "lorencia_warehouse"

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  defp cmd(socket, payload) do
    Mu.RateLimit.reset()
    ref = push(socket, "cmd", payload)
    assert_reply ref, status, reply
    {status, reply}
  end

  defp place(c, {x, y}),
    do:
      MapServer.debug_update(@map, fn st -> update_in(st.players[c.id], &%{&1 | x: x, y: y}) end)

  setup do
    {a, c} = create_character()
    {:ok, _} = Items.pickup(c.id, %{serial: Mu.Ulid.generate(), template_id: "sword_t0"}, "test")
    {:ok, _, socket} = join_game(a, c)
    MapServer.debug_update(@map, fn st -> %{st | monsters: %{}} end)
    sword = Enum.find(Items.load(c.id), &(&1.template_id == "sword_t0"))
    %{a: a, c: c, socket: socket, sword: sword}
  end

  test "Thủ kho có trên map (tên, không phải cửa hàng); mở kho cần trong npcRange", %{
    c: c,
    socket: socket
  } do
    npc = Enum.find(Mu.World.Maps.get(@map).npcs, &(&1.id == @npc))
    assert %{role: "warehouse", name: "Warehouse Keeper"} = npc

    place(c, {npc.x + 4, npc.y})

    assert {:error, %{error: "OUT_OF_RANGE"}} =
             cmd(socket, %{"act" => "npc_open", "rid" => "o1", "npcId" => @npc})

    place(c, {npc.x + 1, npc.y})

    assert {:ok, _} =
             cmd(socket, %{"act" => "npc_open", "rid" => "o2", "npcId" => "npc_" <> @npc})

    assert_push "warehouse", %{npcId: @npc, slots: 120, items: []}
    refute_push "shop", _
  end

  test "gửi rồi rút qua move_item; event warehouse + player; xa Thủ kho thì không được", %{
    c: c,
    socket: socket,
    sword: sword
  } do
    place(c, {12, 31})

    assert {:ok, _} =
             cmd(socket, %{
               "act" => "move_item",
               "rid" => "d1",
               "itemId" => sword.id,
               "to" => %{"location" => "WAREHOUSE", "slot" => 7}
             })

    sid = sword.id
    assert_push "warehouse", %{items: [%{id: ^sid, slot: 7, templateId: "sword_t0"}]}
    assert_push "player", %{inventory: inv}
    refute Enum.any?(inv, &(&1.id == sid))

    # gửi lại cùng rid: trả kết quả cũ, không làm lại
    assert {:ok, _} =
             cmd(socket, %{
               "act" => "move_item",
               "rid" => "d1",
               "itemId" => sword.id,
               "to" => %{"location" => "WAREHOUSE", "slot" => 9}
             })

    assert [%{slot: 7}] = Items.load_warehouse(c.account_id)

    place(c, {20, 31})

    assert {:error, %{error: "OUT_OF_RANGE"}} =
             cmd(socket, %{
               "act" => "move_item",
               "rid" => "w0",
               "itemId" => sword.id,
               "to" => %{"location" => "INVENTORY", "slot" => 3}
             })

    place(c, {12, 31})

    assert {:ok, _} =
             cmd(socket, %{
               "act" => "move_item",
               "rid" => "w1",
               "itemId" => sword.id,
               "to" => %{"location" => "INVENTORY", "slot" => 3}
             })

    assert_push "warehouse", %{items: []}
    assert [%{slot: 3}] = Enum.filter(Items.load(c.id), &(&1.id == sid))
  end
end

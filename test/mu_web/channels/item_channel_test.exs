defmodule MuWeb.ItemChannelTest do
  @moduledoc "M4 qua kênh thật: nhặt, mặc/tháo, potion, NPC shop mua/bán, idempotent rid, reload."
  use MuWeb.ChannelCase

  import Ecto.Query, only: [from: 2]

  alias Mu.Game.{Character, Session}
  alias Mu.World.MapServer
  alias MuWeb.GameChannel
  alias Phoenix.Socket.Message

  @map "lorencia"
  @npc "lorencia_potion_merchant"

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  # test gửi dồn nhanh hơn người thật: bỏ giới hạn tần suất (đã có test riêng)
  defp cmd(socket, payload) do
    Mu.RateLimit.reset()
    ref = push(socket, "cmd", payload)
    assert_reply ref, status, reply
    {status, reply}
  end

  defp setup_player(zen \\ 0) do
    {a, c} = create_character()
    Mu.Repo.update!(Ecto.Changeset.change(c, zen: zen))
    {:ok, reply, socket} = join_game(a, c)
    # bỏ quái: test đồ không bị Spider xen vào
    MapServer.debug_update(@map, fn st -> %{st | monsters: %{}} end)
    %{a: a, c: c, socket: socket, reply: reply}
  end

  defp place(c, {x, y}) do
    MapServer.debug_update(@map, fn st -> update_in(st.players[c.id], &%{&1 | x: x, y: y}) end)
  end

  defp drop_ground(tid, {x, y}, owner, opts \\ []) do
    serial = Mu.Ulid.generate()

    g = %{
      id: "g_" <> serial,
      serial: serial,
      template_id: tid,
      x: x,
      y: y,
      owner: owner,
      protect_until: Keyword.get(opts, :protect_until, 10_000_000),
      expire_at: 10_000_000
    }

    MapServer.debug_update(@map, fn st -> %{st | ground: Map.put(st.ground, g.id, g)} end)
    g
  end

  defp last_player(acc \\ nil) do
    receive do
      %Message{event: "player", payload: p} -> last_player(p)
    after
      50 -> acc
    end
  end

  defp items(a), do: :sys.get_state(Session.whereis(a.id)).items

  test "join: có template item cho client; túi và trang bị rỗng" do
    %{reply: r} = setup_player()
    assert length(r.data.items) == 10
    sword = Enum.find(r.data.items, &(&1["templateId"] == "sword_t0"))

    assert %{"attackMin" => 3, "iconRef" => %{"group" => 0, "index" => 1}, "sellPrice" => 500} =
             sword

    assert {r.player.inventory, r.player.equipment} == {[], []}
    assert r.player.view.potions == %{"HP" => 0, "MP" => 0}
    # M5-2: client cần tầm và thông tin skill (server vẫn kiểm)
    assert {r.config.pickupRange, r.config.npcRange} == {1, 3}

    assert %{name: "Twisting Slash", range: 2, manaCost: 10, requiredLevel: 10} =
             Enum.find(r.data.skills, &(&1.id == "twisting_slash"))
  end

  test "nhặt đồ: trong 1 ô, thành item trong túi (DB), despawn; ngoài tầm/loot protect bị chặn" do
    %{c: c, socket: socket} = setup_player()
    place(c, {40, 40})
    far = drop_ground("sword_t0", {43, 40}, c.id)

    assert {:error, %{error: "OUT_OF_RANGE"}} =
             cmd(socket, %{"act" => "pickup", "rid" => "p1", "id" => far.id})

    {_, other} = create_character()
    theirs = drop_ground("shield_t0", {41, 40}, other.id)

    assert {:error, %{error: "NOT_OWNER"}} =
             cmd(socket, %{"act" => "pickup", "rid" => "p2", "id" => theirs.id})

    # hết loot protect thì ai cũng nhặt được
    free = drop_ground("helm_t0", {40, 41}, other.id, protect_until: 0)
    assert {:ok, %{rid: "p3"}} = cmd(socket, %{"act" => "pickup", "rid" => "p3", "id" => free.id})
    fid = free.id
    assert_push "despawn", %{id: ^fid}
    p = last_player()
    assert [%{templateId: "helm_t0", serial: serial, slot: 0}] = p.inventory
    assert serial == free.serial
    assert Mu.Repo.get_by(Mu.Game.Item, serial: serial)

    assert {:error, %{error: "INVALID_TARGET"}} =
             cmd(socket, %{"act" => "pickup", "rid" => "p4", "id" => free.id})

    assert {:error, %{error: "INVALID_TARGET"}} = cmd(socket, %{"act" => "pickup", "rid" => "p5"})
  end

  test "nhặt khi túi đầy: đồ trở lại mặt đất" do
    %{a: a, c: c, socket: socket} = setup_player()

    for _ <- 1..64,
        do:
          Mu.Game.Items.pickup(
            c.id,
            %{serial: Mu.Ulid.generate(), template_id: "sword_t0"},
            "test"
          )

    # Session đọc lại đồ lúc vào lại
    Process.unlink(socket.channel_pid)
    close(socket)
    Process.sleep(50)
    {:ok, _, socket} = join_game(a, c)
    MapServer.debug_update(@map, fn st -> %{st | monsters: %{}} end)
    place(c, {40, 40})
    g = drop_ground("boots_t0", {40, 40}, c.id)

    assert {:error, %{error: "INVENTORY_FULL"}} =
             cmd(socket, %{"act" => "pickup", "rid" => "f1", "id" => g.id})

    gid = g.id
    assert_push "spawn", %{id: ^gid, kind: "item"}
    assert Map.has_key?(MapServer.debug_state(@map).ground, g.id)
  end

  test "hai người cùng nhặt một món: chỉ một người có (MapServer xử lý tuần tự)" do
    %{c: c1, socket: s1} = setup_player()
    {a2, c2} = create_character()
    {:ok, _, s2} = join_game(a2, c2)
    place(c1, {40, 40})
    place(c2, {41, 40})
    g = drop_ground("ring_hp_t0", {40, 40}, c1.id, protect_until: 0)

    r1 = push(s1, "cmd", %{"act" => "pickup", "rid" => "x", "id" => g.id})
    r2 = push(s2, "cmd", %{"act" => "pickup", "rid" => "x", "id" => g.id})
    assert_reply r1, st1, _
    assert_reply r2, st2, _
    assert Enum.sort([st1, st2]) == [:error, :ok]
    assert Mu.Repo.aggregate(from(i in Mu.Game.Item, where: i.serial == ^g.serial), :count) == 1
  end

  test "mặc kiếm: chỉ số mới (đánh 7–14, cooldown 826 ms) ở client và MapServer; tháo về túi" do
    %{c: c, socket: socket} = setup_player()
    place(c, {40, 40})
    g = drop_ground("sword_t0", {40, 40}, c.id)
    {:ok, _} = cmd(socket, %{"act" => "pickup", "rid" => "a", "id" => g.id})
    [sword] = last_player().inventory

    assert {:error, %{error: "INVALID_SLOT"}} =
             cmd(socket, %{"act" => "equip", "rid" => "b", "itemId" => sword.id, "slot" => 6})

    assert {:ok, _} =
             cmd(socket, %{"act" => "equip", "rid" => "c", "itemId" => sword.id, "slot" => 5})

    p = last_player()
    assert {p.inventory, Enum.map(p.equipment, & &1.slot)} == {[], [5]}
    assert {p.view.attackMin, p.view.attackMax, p.view.cooldownMs} == {7, 14, 826}
    assert MapServer.debug_state(@map).players[c.id].stats.attack_max == 14

    assert {:ok, _} = cmd(socket, %{"act" => "unequip", "rid" => "d", "slot" => 5, "toSlot" => 3})
    p = last_player()
    assert [%{slot: 3}] = p.inventory
    assert p.view.attackMax == 7
    assert MapServer.debug_state(@map).players[c.id].stats.attack_max == 7
  end

  test "nhẫn HP: hpMax +20 (G6), HP hiện tại không tự tăng" do
    %{c: c, socket: socket} = setup_player()
    place(c, {40, 40})
    g = drop_ground("ring_hp_t0", {40, 40}, c.id)
    {:ok, _} = cmd(socket, %{"act" => "pickup", "rid" => "a", "id" => g.id})
    [ring] = last_player().inventory

    assert {:ok, _} =
             cmd(socket, %{"act" => "equip", "rid" => "b", "itemId" => ring.id, "slot" => 9})

    p = last_player()
    assert {p.view.hpMax, p.hp} == {205, 185}
  end

  test "mua potion ở NPC → dùng potion (trước khi mặc áo, Q14): hồi 50 HP, cooldown, hết thì xóa" do
    %{c: c, socket: socket} = setup_player(250)
    # đứng xa NPC (spawn cách 6 ô) → OUT_OF_RANGE (G4: ≤ 3 ô)
    assert {:error, %{error: "OUT_OF_RANGE"}} =
             cmd(socket, %{"act" => "npc_open", "rid" => "o1", "npcId" => @npc})

    place(c, {12, 26})

    assert {:ok, _} =
             cmd(socket, %{"act" => "npc_open", "rid" => "o2", "npcId" => "npc_" <> @npc})

    assert_push "shop", %{npcId: @npc, items: [%{templateId: "hp_potion_small", price: 100}]}

    assert {:ok, _} =
             cmd(socket, %{
               "act" => "buy",
               "rid" => "b1",
               "npcId" => @npc,
               "templateId" => "hp_potion_small",
               "quantity" => 2
             })

    p = last_player()
    assert {p.zen, p.view.potions["HP"]} == {50, 2}
    assert Mu.Repo.get!(Character, c.id).zen == 50

    # gửi lại cùng rid (mạng chập chờn): không mua lần hai
    assert {:ok, %{rid: "b1"}} =
             cmd(socket, %{
               "act" => "buy",
               "rid" => "b1",
               "npcId" => @npc,
               "templateId" => "hp_potion_small",
               "quantity" => 2
             })

    assert Mu.Repo.get!(Character, c.id).zen == 50

    assert {:error, %{error: "NOT_ENOUGH_ZEN"}} =
             cmd(socket, %{
               "act" => "buy",
               "rid" => "b2",
               "npcId" => @npc,
               "templateId" => "hp_potion_small"
             })

    assert {:error, %{error: "INVALID_TARGET"}} =
             cmd(socket, %{
               "act" => "buy",
               "rid" => "b3",
               "npcId" => @npc,
               "templateId" => "sword_t0"
             })

    assert {:error, %{error: "INVALID_TARGET"}} =
             cmd(socket, %{
               "act" => "buy",
               "rid" => "b4",
               "npcId" => @npc,
               "templateId" => "hp_potion_small",
               "quantity" => 0
             })

    MapServer.debug_update(@map, fn st -> update_in(st.players[c.id], &%{&1 | hp: 100}) end)
    [stack] = p.inventory
    assert {:ok, _} = cmd(socket, %{"act" => "use_item", "rid" => "u1", "itemId" => stack.id})
    p = last_player()
    assert {p.hp, p.view.potions["HP"]} == {150, 1}
    # potionCooldownMs 1000
    assert {:error, %{error: "COOLDOWN"}} =
             cmd(socket, %{"act" => "use_item", "rid" => "u2", "itemId" => stack.id})

    MapServer.tick(@map, 20)
    assert {:ok, _} = cmd(socket, %{"act" => "use_item", "rid" => "u3", "itemId" => stack.id})
    p = last_player()
    # không vượt hpMax
    assert {p.hp, p.inventory} == {185, []}

    assert {:error, %{error: "NOT_OWNER"}} =
             cmd(socket, %{"act" => "use_item", "rid" => "u4", "itemId" => stack.id})
  end

  test "bán đồ ở NPC: cộng sellPrice; đang mặc không bán được; reload còn nguyên đồ và Zen" do
    %{a: a, c: c, socket: socket} = setup_player()
    place(c, {12, 26})

    for tid <- ~w(sword_t0 armor_t0) do
      g = drop_ground(tid, {12, 26}, c.id)
      {:ok, _} = cmd(socket, %{"act" => "pickup", "rid" => "p" <> tid, "id" => g.id})
    end

    inv = last_player().inventory
    sword = Enum.find(inv, &(&1.templateId == "sword_t0"))
    armor = Enum.find(inv, &(&1.templateId == "armor_t0"))
    {:ok, _} = cmd(socket, %{"act" => "equip", "rid" => "e", "itemId" => armor.id, "slot" => 1})

    assert {:error, %{error: "INVALID_SLOT"}} =
             cmd(socket, %{"act" => "sell", "rid" => "s0", "npcId" => @npc, "itemId" => armor.id})

    assert {:ok, _} =
             cmd(socket, %{"act" => "sell", "rid" => "s1", "npcId" => @npc, "itemId" => sword.id})

    assert last_player().zen == 500

    pid = Session.whereis(a.id)
    Process.unlink(socket.channel_pid)
    DynamicSupervisor.terminate_child(Mu.Game.SessionSupervisor, pid)
    {:ok, r, _} = join_game(a, c)
    assert r.player.zen == 500
    assert r.player.inventory == []
    assert [%{templateId: "armor_t0", slot: 1}] = r.player.equipment
    # giáp vẫn tính vào chỉ số sau reload: defense 5 + 10
    assert r.player.view.defense == 15
    assert length(items(a)) == 1
  end

  test "act item khi không có tham số đúng → lỗi, không crash" do
    %{socket: socket} = setup_player()

    for p <- [
          %{"act" => "equip", "rid" => "1"},
          %{"act" => "equip", "rid" => "2", "itemId" => 5, "slot" => 5},
          %{"act" => "unequip", "rid" => "3"},
          %{"act" => "use_item", "rid" => "4", "itemId" => "x"},
          %{"act" => "sell", "rid" => "5", "npcId" => @npc},
          %{"act" => "npc_open", "rid" => "6", "npcId" => "khong_co"},
          %{"act" => "buy", "rid" => "7", "npcId" => 1, "templateId" => "x"}
        ] do
      assert {:error, %{error: code}} = cmd(socket, p)
      assert code in ~w(INVALID_TARGET INVALID_SLOT NOT_OWNER OUT_OF_RANGE), inspect(p)
    end

    assert {:error, %{error: "FORBIDDEN"}} =
             cmd(socket, %{"act" => "drop", "rid" => "8", "itemId" => "x"})
  end
end

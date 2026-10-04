defmodule MuWeb.UpgradeChannelTest do
  @moduledoc """
  P5-M2 qua kênh thật: act `upgrade {itemId, jewelId}` — Bless lên +1, trừ 1 jewel, `player` +
  event `upgrade`, audit `UPGRADE` / `JEWEL_USE` trong một transaction, `rid` idempotent, lỗi
  (đồ đang mặc, sai jewel, nhẫn, đồ người khác), Soul hỏng giảm cấp, Life thêm option,
  thành công +7 → SYSTEM cả map, chỉ số player.view tăng khi mặc đồ đã ép.
  """
  use MuWeb.ChannelCase

  import Ecto.Query, only: [from: 2]

  alias Mu.Game.{Item, ItemAudit, Items, Session}
  alias MuWeb.GameChannel
  alias Phoenix.Socket.Message

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  defp player do
    {a, c} = create_character()
    {:ok, _, socket} = join_game(a, c)
    %{a: a, c: c, s: socket}
  end

  defp cmd(p, act, payload, rid \\ nil) do
    Mu.RateLimit.reset()
    rid = rid || "r#{System.unique_integer([:positive])}"
    ref = push(p.s, "cmd", Map.merge(%{"act" => act, "rid" => rid}, payload))
    assert_reply ref, status, reply
    if status == :ok, do: :ok, else: {:error, reply.error}
  end

  # thêm đồ vào túi (như nhặt) rồi cho Session đọc lại; trả id
  defp give(p, tid, quantity \\ 1, attrs \\ %{}) do
    before = MapSet.new(Items.load(p.c.id), & &1.id)

    {:ok, _} =
      Items.pickup(
        p.c.id,
        %{serial: Mu.Ulid.generate(), template_id: tid, quantity: quantity, attrs: attrs},
        "test"
      )

    items = Items.load(p.c.id)
    :sys.replace_state(Session.whereis(p.a.id), &%{&1 | items: items})
    # stack gộp (jewel) thì id cũ, không thì món mới
    new = Enum.find(items, &(&1.template_id == tid and not MapSet.member?(before, &1.id)))
    (new || Enum.find(items, &(&1.template_id == tid and &1.location == "INVENTORY"))).id
  end

  defp item(id), do: Mu.Repo.get(Item, id)

  defp got(p, ev, acc \\ []) do
    jr = p.s.join_ref

    receive do
      %Message{event: ^ev, join_ref: ^jr, payload: x} -> got(p, ev, [x | acc])
    after
      80 -> Enum.reverse(acc)
    end
  end

  test "Bless lên +1: trừ 1 jewel, event upgrade + player, audit, rid gửi lại không ép lần hai" do
    p = player()
    sword = give(p, "sword_t0")
    bless = give(p, "jewel_bless", 3)

    assert :ok = cmd(p, "upgrade", %{"itemId" => sword, "jewelId" => bless}, "up-1")
    assert item(sword).item_level == 1
    assert item(bless).quantity == 2

    assert [%{ok: true, level: 1, option: 0, jewel: "jewel_bless", itemId: ^sword}] =
             got(p, "upgrade")

    inv = List.last(got(p, "player")).inventory
    assert Enum.find(inv, &(&1.id == sword)).level == 1

    # gửi lại cùng rid: trả kết quả cũ, không ép thêm
    assert :ok = cmd(p, "upgrade", %{"itemId" => sword, "jewelId" => bless}, "up-1")
    assert {item(sword).item_level, item(bless).quantity} == {1, 2}

    actions =
      Mu.Repo.all(from(a in ItemAudit, where: a.item_id in [^sword, ^bless], select: a.action))

    assert "UPGRADE" in actions and "JEWEL_USE" in actions

    # hết jewel: stack bị xóa
    :ok = cmd(p, "upgrade", %{"itemId" => sword, "jewelId" => bless})
    :ok = cmd(p, "upgrade", %{"itemId" => sword, "jewelId" => bless})
    assert item(sword).item_level == 3
    assert item(bless) == nil
    assert {:error, "NOT_OWNER"} = cmd(p, "upgrade", %{"itemId" => sword, "jewelId" => bless})
  end

  test "lỗi: sai loại jewel, nhẫn, ép jewel lên jewel, đồ đang mặc, đồ của người khác — không mất jewel" do
    p = player()
    sword = give(p, "sword_t0")
    soul = give(p, "jewel_soul", 2)
    bless = give(p, "jewel_bless", 2)
    ring = give(p, "ring_hp_t0")

    assert {:error, "INVALID_TARGET"} = cmd(p, "upgrade", %{"itemId" => sword, "jewelId" => soul})
    assert {:error, "INVALID_TARGET"} = cmd(p, "upgrade", %{"itemId" => ring, "jewelId" => bless})
    assert {:error, "INVALID_TARGET"} = cmd(p, "upgrade", %{"itemId" => soul, "jewelId" => bless})

    assert {:error, "INVALID_TARGET"} =
             cmd(p, "upgrade", %{"itemId" => sword, "jewelId" => sword})

    assert {:error, "INVALID_TARGET"} = cmd(p, "upgrade", %{"itemId" => sword})

    :ok = cmd(p, "equip", %{"itemId" => sword, "slot" => 5})
    assert {:error, "INVALID_SLOT"} = cmd(p, "upgrade", %{"itemId" => sword, "jewelId" => bless})

    other = player()
    theirs = give(other, "sword_t0")
    assert {:error, "NOT_OWNER"} = cmd(p, "upgrade", %{"itemId" => theirs, "jewelId" => bless})

    assert {item(soul).quantity, item(bless).quantity} == {2, 2}
  end

  test "Soul trên +6: thành công +7 (SYSTEM cả map) hoặc hỏng về +5; Life thêm option" do
    p = player()
    soul = give(p, "jewel_soul", 20)

    # 20 món +6: đủ để thấy cả thành công lẫn thất bại (70 %)
    results =
      for _ <- 1..20 do
        sword = give(p, "sword_t0", 1, %{item_level: 6})
        :ok = cmd(p, "upgrade", %{"itemId" => sword, "jewelId" => soul})
        item(sword).item_level
      end

    assert 7 in results and 5 in results
    assert Enum.all?(results, &(&1 in [5, 7]))

    assert Enum.any?(
             got(p, "chat"),
             &(&1.channel == "SYSTEM" and &1.text =~ "ép thành công Short Sword +7")
           )

    life = give(p, "jewel_life", 20)
    helm = give(p, "helm_t0")

    Enum.find(1..20, fn _ ->
      :ok = cmd(p, "upgrade", %{"itemId" => helm, "jewelId" => life})
      item(helm).option_level == 1
    end) || flunk("Life không lên option lần nào")

    assert item(helm).item_level == 0
    assert Enum.find(List.last(got(p, "player")).inventory, &(&1.id == helm)).optionLevel == 1
  end

  test "mặc đồ đã ép: player.view thủ tăng theo +N và option" do
    p = player()
    helm = give(p, "helm_t0", 1, %{item_level: 2, option_level: 1})
    _ = got(p, "player")
    :ok = cmd(p, "equip", %{"itemId" => helm, "slot" => 0})
    v = List.last(got(p, "player")).view
    base = Mu.Game.Data.item("helm_t0")["defense"]
    per = Mu.Game.Config.get(["upgrade", "life", "perOption"])

    plain = player()
    h2 = give(plain, "helm_t0")
    _ = got(plain, "player")
    :ok = cmd(plain, "equip", %{"itemId" => h2, "slot" => 0})
    v0 = List.last(got(plain, "player")).view

    assert v.defense == v0.defense + 2 * 3 + per
    assert base > 0
  end
end

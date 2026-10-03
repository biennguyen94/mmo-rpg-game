defmodule MuWeb.ChaosChannelTest do
  @moduledoc """
  P6-M3 / P6-M4 qua kênh thật + transaction: mở Chaos Goblin (Noria), xem trước công thức / tỉ
  lệ / phí, kết hợp (RNG có seed ở `Items.chaos_combine/3`: thành công ra cánh, thất bại mất đầu
  vào + phí; audit `CHAOS_IN` / `CHAOS_OUT` + Zen `CHAOS`, `mu.audit` sạch), mặc cánh (slot 7 mở,
  cấp 15, spawn có `wing`, chỉ số có hệ số cánh).
  """
  use MuWeb.ChannelCase

  import Ecto.Query, only: [from: 2]

  alias Mu.Game.{Character, Item, ItemAudit, Items, Rng, Session, ZenAudit}
  alias Mu.World.MapServer
  alias MuWeb.GameChannel
  alias Phoenix.Socket.Message

  @map "noria"
  @npc "noria_chaos_goblin"

  defp player(zen, level \\ 1) do
    {a, c} = create_character()
    {:ok, _} = ZenAudit.admin_set(c.id, zen, "test")

    Mu.Repo.update_all(from(x in Character, where: x.id == ^c.id),
      set: [map_id: @map, position_x: 36, position_y: 51, level: level]
    )

    {:ok, socket} = connect_account(a)

    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "game", %{
        "clientVersion" => client_version(),
        "characterId" => c.id
      })

    MapServer.debug_update(@map, fn st ->
      update_in(st.players[c.id], &%{&1 | x: 36, y: 51, path: []})
    end)

    %{a: a, c: c, s: socket}
  end

  defp cmd(p, act, payload) do
    Mu.RateLimit.reset()

    ref =
      push(
        p.s,
        "cmd",
        Map.merge(%{"act" => act, "rid" => "r#{System.unique_integer()}"}, payload)
      )

    assert_reply ref, status, reply
    if status == :ok, do: :ok, else: {:error, reply.error}
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

  # thêm đồ vào túi (pickup) rồi chỉnh +N / option trực tiếp trong DB; Session đọc lại
  defp give(p, tid, opts \\ []) do
    before = MapSet.new(Items.load(p.c.id), & &1.id)

    {:ok, _} =
      Items.pickup(
        p.c.id,
        %{serial: Mu.Ulid.generate(), template_id: tid, quantity: Keyword.get(opts, :q, 1)},
        "test"
      )

    id = Enum.find(Items.load(p.c.id), &(not MapSet.member?(before, &1.id))).id

    Mu.Repo.update_all(from(i in Item, where: i.id == ^id),
      set: [item_level: Keyword.get(opts, :lvl, 0), option_level: Keyword.get(opts, :opt, 0)]
    )

    :sys.replace_state(Session.whereis(p.a.id), &%{&1 | items: Items.load(p.c.id)})
    id
  end

  defp zen(p), do: Mu.Repo.get!(Character, p.c.id).zen
  defp exists?(id), do: Mu.Repo.exists?(from(i in Item, where: i.id == ^id))

  setup do
    MapServer.debug_update(@map, fn st -> %{st | monsters: %{}} end)
    :ok
  end

  test "mở Chaos Goblin → xem trước (công thức, tỉ lệ, phí) → kết hợp: đầu vào mất, phí trừ, audit sạch" do
    p = player(50_000)
    sword = give(p, "sword_t0", lvl: 6)
    chaos = give(p, "jewel_chaos", q: 2)

    :ok = cmd(p, "npc_open", %{"npcId" => "npc_" <> @npc})
    assert %{npcId: @npc, maxItems: 8} = last(p, "chaos")

    :ok = cmd(p, "chaos_preview", %{"itemIds" => [sword, chaos], "npcId" => @npc})
    assert %{recipe: "wings_1", rate: 0.2, zen: 20_000} = last(p, "chaos")
    :ok = cmd(p, "chaos_preview", %{"itemIds" => [sword], "npcId" => @npc})
    assert %{recipe: nil} = last(p, "chaos")

    :ok = cmd(p, "chaos_combine", %{"itemIds" => [sword, chaos], "npcId" => @npc})
    assert %{result: %{ok: ok?, rate: 0.2}} = last(p, "chaos")
    refute exists?(sword)
    # stack Chaos còn 1
    assert Mu.Repo.get!(Item, chaos).quantity == 1
    assert zen(p) == 30_000

    assert Mu.Repo.exists?(
             from(x in ItemAudit, where: x.item_id == ^sword and x.action == "CHAOS_IN")
           )

    wings = Enum.filter(Items.load(p.c.id), &String.starts_with?(&1.template_id, "wing_"))
    assert length(wings) == if(ok?, do: 1, else: 0)
    assert Mu.Audit.run().problems == []
  end

  test "Items.chaos_combine với RNG có seed: thành công ra cánh (CHAOS_OUT), thất bại không ra gì" do
    p = player(240_000)

    results =
      for seed <- 1..12 do
        sword = give(p, "sword_t0", lvl: 9)
        chaos = give(p, "jewel_chaos")
        {:ok, %{chaos: r}} = Items.chaos_combine(p.c.id, [sword, chaos], Rng.new(seed))
        r
      end

    assert Enum.any?(results, & &1.ok) and Enum.any?(results, &(not &1.ok))
    made = Enum.filter(Items.load(p.c.id), &String.starts_with?(&1.template_id, "wing_"))
    assert length(made) == Enum.count(results, & &1.ok)
    assert Mu.Repo.exists?(from(x in ItemAudit, where: x.action == "CHAOS_OUT"))
    assert zen(p) == 0
    assert Mu.Audit.run().problems == []
  end

  test "lỗi: thiếu Zen / không khớp / xa NPC / đồ không phải của mình" do
    p = player(5_000)
    sword = give(p, "sword_t0", lvl: 6)
    chaos = give(p, "jewel_chaos")

    assert {:error, "NOT_ENOUGH_ZEN"} =
             cmd(p, "chaos_combine", %{"itemIds" => [sword, chaos], "npcId" => @npc})

    assert exists?(sword)

    assert {:error, "INVALID_TARGET"} =
             cmd(p, "chaos_combine", %{"itemIds" => [sword], "npcId" => @npc})

    assert {:error, "NOT_OWNER"} =
             cmd(p, "chaos_preview", %{"itemIds" => [Ecto.UUID.generate()], "npcId" => @npc})

    MapServer.debug_update(@map, fn st ->
      update_in(st.players[p.c.id], &%{&1 | x: 10, y: 10})
    end)

    assert {:error, "OUT_OF_RANGE"} =
             cmd(p, "chaos_preview", %{"itemIds" => [sword, chaos], "npcId" => @npc})
  end

  test "mặc cánh: cần cấp 15, đúng class; spawn có `wing`; chỉ số có damageIncrease / absorb" do
    p = player(0, 14)
    wing = give(p, "wing_satan", lvl: 2)
    elf = give(p, "wing_elf")
    assert {:error, "REQUIREMENT_NOT_MET"} = cmd(p, "equip", %{"itemId" => wing, "slot" => 7})

    Mu.Repo.update_all(from(x in Character, where: x.id == ^p.c.id), set: [level: 15])

    :sys.replace_state(Session.whereis(p.a.id), fn s ->
      %{s | character: %{s.character | level: 15}, saved: %{s.saved | level: 15}}
    end)

    assert {:error, _} = cmd(p, "equip", %{"itemId" => elf, "slot" => 7})
    :ok = cmd(p, "equip", %{"itemId" => wing, "slot" => 7})

    e = MapServer.debug_state(@map).players[p.c.id]
    assert e.wing == "wing_satan"
    assert {e.stats.damage_increase, e.stats.absorb} == {16, 16}
    assert Enum.any?(got(p, "spawn"), &(&1[:wing] == "wing_satan"))
  end

  test "P7: cánh cấp 2 (RNG seed) ra đúng class DK, trừ 200 000 Zen; ép +10 bằng Chaos hỏng thì mất đồ; audit sạch" do
    p = player(2_000_000, 25)

    results =
      for seed <- 1..6 do
        w = give(p, "wing_satan", lvl: 7)

        ids = [
          w,
          give(p, "jewel_bless", q: 5),
          give(p, "jewel_soul", q: 5),
          give(p, "jewel_chaos", q: 2)
        ]

        {:ok, %{chaos: r}} = Items.chaos_combine(p.c.id, ids, Rng.new(seed))
        refute exists?(w)
        r
      end

    assert Enum.all?(results, &(&1.recipe == "wings_2" and &1.rate == 0.3))

    made =
      for i <- Items.load(p.c.id), String.starts_with?(i.template_id, "wing_"), do: i.template_id

    assert made == List.duplicate("wing_dragon", Enum.count(results, & &1.ok))
    assert zen(p) == 2_000_000 - 6 * 200_000

    # +9 → +10: thử tới khi có cả thành công lẫn mất đồ
    outcomes =
      for seed <- 1..8 do
        s = give(p, "sword_t0", lvl: 9)
        j = give(p, "jewel_chaos")
        {:ok, %{upgrade: u}} = Items.upgrade(p.c.id, s, j, Rng.new(seed))
        assert exists?(s) == not u.destroyed
        if u.ok, do: assert(Mu.Repo.get!(Item, s).item_level == 10)
        u
      end

    assert Enum.any?(outcomes, & &1.ok) and Enum.any?(outcomes, & &1.destroyed)
    assert Mu.Audit.run().problems == []
  end
end

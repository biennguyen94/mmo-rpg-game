defmodule MuWeb.QuestChannelTest do
  @moduledoc """
  P6-M2 (P6-2) qua kênh thật: mở Quest Master (event `quests` kèm `npcId`), nhận trong `npcRange`,
  đếm kill từ `{:map_reward, …}`, trả quest một transaction (Zen audit `QUEST`, đồ audit `QUEST`,
  vật phẩm collect bị nộp, `DONE`, `mu.audit` sạch), trả hai lần / chưa xong / bỏ quest.
  """
  use MuWeb.ChannelCase

  import Ecto.Query, only: [from: 2]

  alias Mu.Game.{Character, ItemAudit, Items, Session, ZenAudit}
  alias Mu.World.MapServer
  alias MuWeb.GameChannel
  alias Phoenix.Socket.Message

  @map "lorencia"
  @npc "lorencia_quest_master"

  defp player do
    {a, c} = create_character()
    {:ok, _} = ZenAudit.admin_set(c.id, 0, "test")
    {:ok, socket} = connect_account(a)

    {:ok, _, socket} =
      subscribe_and_join(socket, GameChannel, "game", %{
        "clientVersion" => client_version(),
        "characterId" => c.id
      })

    p = %{a: a, c: c, s: socket}
    place(p, {18, 25})
    p
  end

  defp cmd(p, act, payload \\ %{}, rid \\ nil) do
    Mu.RateLimit.reset()
    rid = rid || "r#{System.unique_integer([:positive])}"
    ref = push(p.s, "cmd", Map.merge(%{"act" => act, "rid" => rid}, payload))
    assert_reply ref, status, reply
    if status == :ok, do: :ok, else: {:error, reply.error}
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

  defp kill(p, monster, n) do
    pid = Session.whereis(p.a.id)

    for _ <- 1..n,
        do: send(pid, {:map_reward, %{exp: 0, zen: 0, monster: "m", template: monster}})

    :sys.get_state(pid)
  end

  defp set_level(p, level) do
    Mu.Repo.update_all(from(c in Character, where: c.id == ^p.c.id), set: [level: level])

    :sys.replace_state(Session.whereis(p.a.id), fn s ->
      %{s | character: %{s.character | level: level}, saved: %{s.saved | level: level}}
    end)
  end

  defp give(p, tid, quantity) do
    {:ok, _} =
      Items.pickup(
        p.c.id,
        %{serial: Mu.Ulid.generate(), template_id: tid, quantity: quantity},
        "test"
      )

    :sys.replace_state(Session.whereis(p.a.id), &%{&1 | items: Items.load(p.c.id)})
  end

  defp bag(p, tid) do
    Items.load(p.c.id)
    |> Enum.filter(&(&1.template_id == tid and &1.location == "INVENTORY"))
    |> Enum.map(& &1.quantity)
    |> Enum.sum()
  end

  setup do
    MapServer.debug_update(@map, fn st -> %{st | monsters: %{}} end)
    :ok
  end

  test "mở NPC → nhận → hạ 10 Spider → trả: Zen + potion + EXP, audit QUEST, DONE, audit sạch" do
    p = player()
    :ok = cmd(p, "npc_open", %{"npcId" => "npc_" <> @npc})
    assert %{npcId: @npc, available: avail, active: []} = last(p, "quests")
    assert Enum.any?(avail, &(&1.id == "q_spider"))

    :ok = cmd(p, "quest_accept", %{"questId" => "q_spider", "npcId" => @npc})
    assert %{active: [%{id: "q_spider", objectives: [%{have: 0, need: 10}]}]} = last(p, "quests")

    # chưa xong → REQUIREMENT_NOT_MET
    assert {:error, "REQUIREMENT_NOT_MET"} =
             cmd(p, "quest_turnin", %{"questId" => "q_spider", "npcId" => @npc})

    kill(p, "spider", 12)
    kill(p, "hound", 1)
    assert %{active: [%{objectives: [%{have: 10}], complete: true}]} = last(p, "quests")

    rid = "turnin-1"
    :ok = cmd(p, "quest_turnin", %{"questId" => "q_spider", "npcId" => @npc}, rid)
    # gửi lại cùng rid: kết quả cũ, không thưởng lần hai
    :ok = cmd(p, "quest_turnin", %{"questId" => "q_spider", "npcId" => @npc}, rid)

    assert %{questId: "q_spider"} = last(p, "quest_done")
    assert %{done: ["q_spider"], active: []} = last(p, "quests")
    c = Mu.Repo.get!(Character, p.c.id)
    assert c.zen == 300
    assert c.experience == 100 or c.level > 1
    assert bag(p, "hp_potion_small") == 5

    assert Mu.Repo.exists?(
             from(z in "zen_audit_log",
               where: z.character_id == type(^p.c.id, :binary_id) and z.reason == "QUEST"
             )
           )

    assert Mu.Repo.exists?(from(x in ItemAudit, where: x.action == "QUEST"))

    # trả lần hai (rid khác) / nhận lại → lỗi
    assert {:error, "INVALID_TARGET"} =
             cmd(p, "quest_turnin", %{"questId" => "q_spider", "npcId" => @npc})

    assert {:error, "FORBIDDEN"} =
             cmd(p, "quest_accept", %{"questId" => "q_spider", "npcId" => @npc})

    assert Mu.Audit.run().problems == []
  end

  test "collect: nộp vật phẩm khi trả (nhiều stack); thiếu thì không nộp gì" do
    p = player()
    set_level(p, 18)
    :ok = cmd(p, "quest_accept", %{"questId" => "q_hunter", "npcId" => @npc})
    kill(p, "hunter", 15)
    give(p, "hp_potion_medium", 6)

    assert {:error, "REQUIREMENT_NOT_MET"} =
             cmd(p, "quest_turnin", %{"questId" => "q_hunter", "npcId" => @npc})

    assert bag(p, "hp_potion_medium") == 6
    give(p, "hp_potion_medium", 99)
    :ok = cmd(p, "quest_turnin", %{"questId" => "q_hunter", "npcId" => @npc})
    assert bag(p, "hp_potion_medium") == 95
    assert Mu.Repo.get!(Character, p.c.id).zen == 6000
    assert Mu.Repo.exists?(from(x in ItemAudit, where: x.action == "QUEST_IN"))
    assert Mu.Audit.run().problems == []
  end

  test "xa NPC → OUT_OF_RANGE; chưa đủ cấp; bỏ quest; tối đa 5 quest" do
    p = player()
    place(p, {30, 30})

    assert {:error, "OUT_OF_RANGE"} =
             cmd(p, "quest_accept", %{"questId" => "q_spider", "npcId" => @npc})

    place(p, {18, 25})

    assert {:error, "REQUIREMENT_NOT_MET"} =
             cmd(p, "quest_accept", %{"questId" => "q_goblin", "npcId" => @npc})

    assert {:error, "INVALID_TARGET"} =
             cmd(p, "quest_accept", %{"questId" => "khong_co", "npcId" => @npc})

    set_level(p, 12)

    for q <- ~w(q_spider q_budge q_bull q_ring q_hound),
        do: :ok = cmd(p, "quest_accept", %{"questId" => q, "npcId" => @npc})

    assert {:error, "FORBIDDEN"} =
             cmd(p, "quest_accept", %{"questId" => "q_goblin", "npcId" => @npc})

    kill(p, "spider", 3)
    :ok = cmd(p, "quest_abandon", %{"questId" => "q_spider"})
    assert {:error, "INVALID_TARGET"} = cmd(p, "quest_abandon", %{"questId" => "q_spider"})
    :ok = cmd(p, "quest_accept", %{"questId" => "q_goblin", "npcId" => @npc})

    # nhận lại quest đã bỏ: tiến độ từ 0
    :ok = cmd(p, "quest_abandon", %{"questId" => "q_goblin"})
    :ok = cmd(p, "quest_accept", %{"questId" => "q_spider", "npcId" => @npc})
    :ok = cmd(p, "quest_list")
    v = last(p, "quests")
    assert %{objectives: [%{have: 0}]} = Enum.find(v.active, &(&1.id == "q_spider"))
  end

  test "tiến độ còn sau khi Session tắt (đọc lại DB)" do
    p = player()
    :ok = cmd(p, "quest_accept", %{"questId" => "q_spider", "npcId" => @npc})
    kill(p, "spider", 4)
    assert %{"q_spider" => %{progress: %{"0" => 4}}} = Mu.Game.QuestStore.load(p.c.id)
  end
end

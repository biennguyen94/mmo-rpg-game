defmodule Mu.Game.QuestsTest do
  @moduledoc "Luật quest thuần (P6-M2, P6-2): nhận, đếm kill, collect / level, view."
  use ExUnit.Case, async: true

  alias Mu.Game.{Data, Quests}

  defp active(pr \\ %{}), do: %{state: "ACTIVE", progress: pr}

  test "quests.json: 10 quest, cấp 1 → 28, mỗi bản ghi có sourceType / version / verified" do
    qs = Data.quests()
    assert length(qs) == 10
    assert Enum.all?(qs, &(&1["minLevel"] in 1..28))
    assert Enum.all?(qs, &(Map.has_key?(&1, "sourceType") and Map.has_key?(&1, "verified")))
    assert hd(qs)["id"] == "q_spider"
  end

  test "nhận: không có / đã nhận / đã xong / chưa đủ cấp / đủ maxActive" do
    assert Quests.can_accept("khong_co", 1, %{}) == {:error, "INVALID_TARGET"}
    assert Quests.can_accept("q_spider", 1, %{}) == :ok
    assert Quests.can_accept("q_spider", 1, %{"q_spider" => active()}) == {:error, "FORBIDDEN"}

    assert Quests.can_accept("q_spider", 1, %{"q_spider" => %{state: "DONE", progress: %{}}}) ==
             {:error, "FORBIDDEN"}

    assert Quests.can_accept("q_goblin", 11, %{}) == {:error, "REQUIREMENT_NOT_MET"}

    five = Map.new(~w(q_budge q_bull q_ring q_hound q_grow), &{&1, active()})
    assert Quests.can_accept("q_spider", 30, five) == {:error, "FORBIDDEN"}
  end

  test "kill: đếm đúng quái, dừng ở count; quest khác / đã xong không đổi" do
    st = %{"q_spider" => active(%{"0" => 9}), "q_budge" => active()}
    assert [{"q_spider", %{"0" => 10}}] = Quests.on_kill(st, "spider")
    assert Quests.on_kill(%{"q_spider" => active(%{"0" => 10})}, "spider") == []
    assert Quests.on_kill(%{"q_spider" => %{state: "DONE", progress: %{}}}, "spider") == []
    assert Quests.on_kill(st, "hound") == []

    # hai mục tiêu kill trong một quest
    assert [{"q_golem", %{"1" => 1}}] = Quests.on_kill(%{"q_golem" => active()}, "agon")
  end

  test "collect đếm cả các stack trong túi (không tính đồ đang mặc), level so với cấp" do
    q = Data.quest("q_hunter")

    items = [
      %{template_id: "hp_potion_medium", quantity: 4, location: "INVENTORY", slot: 0},
      %{template_id: "hp_potion_medium", quantity: 7, location: "INVENTORY", slot: 1}
    ]

    assert [%{type: "kill", have: 15}, %{type: "collect", have: 10, need: 10}] =
             Quests.objectives(q, %{"0" => 15}, 18, items)

    assert Quests.complete?(q, %{"0" => 15}, 18, items)
    refute Quests.complete?(q, %{"0" => 14}, 18, items)
    refute Quests.complete?(q, %{"0" => 15}, 18, tl(items))

    g = Data.quest("q_grow")
    refute Quests.complete?(g, %{}, 9, [])
    assert Quests.complete?(g, %{}, 10, [])
  end

  test "view: active (tiến độ), done, available theo cấp" do
    st = %{"q_spider" => %{state: "DONE", progress: %{}}, "q_budge" => active(%{"0" => 3})}
    v = Quests.view(st, 5, [])
    assert v.done == ["q_spider"]
    assert [%{id: "q_budge", complete: false, objectives: [%{have: 3, need: 12}]}] = v.active
    ids = Enum.map(v.available, & &1.id)
    assert "q_bull" in ids and "q_grow" in ids
    refute "q_hound" in ids or "q_spider" in ids
  end
end

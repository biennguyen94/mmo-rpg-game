defmodule HacLong.Game.Chaos15fTest do
  @moduledoc """
  Phase 15f (docs/ITEMS_PHASE15B.md §9): Máy Hỗn Nguyên thêm dòng cho chính món đồ (Pha Excellent, Pha May mắn).
  """
  use ExUnit.Case, async: true

  alias HacLong.Game.{Chaos, Data, Engine, Gear, Rng}

  setup do
    on_exit(&Rng.clear/0)
    :ok
  end

  defp setup_p(g, up) do
    {:ok, p} = Engine.new_player("Thử", "dk")

    p =
      %{p | gold: 1_000_000, gear: [g]}
      |> Map.put(:upgrades, %{g.uid => up})
      |> Engine.add_item("jewel_chaos", 5)
      |> Engine.add_item("jewel_life", 5)
      |> Engine.add_item("jewel_bless", 5)

    p
  end

  test "Pha Excellent: thêm 1 dòng, giữ cấp nâng và uid; tối đa 3 dòng" do
    g = %{Gear.new("item_0_3", 1, %{str: 2}) | uid: "#S"}
    p = setup_p(g, 7)
    r = Data.chaos("add_exc")

    Rng.put_sequence([0.0, 0.0])
    {res, q} = Chaos.combine(p, "add_exc", "#S")
    assert res.chaos.result == "success"
    assert [%{uid: "#S", exc: [line], bonus: %{str: 2}}] = q.gear
    assert line in Gear.exc_pool("weapon")
    assert q.upgrades["#S"] == 7
    assert q.gold == p.gold - r.gold and q.inv["jewel_chaos"] == 4 and q.inv["jewel_life"] == 3
    assert Chaos.rate(r, 7) == Float.round(r.rate + 2 * r.per_up, 3)

    full = setup_p(Map.put(g, :exc, ~w(atk_pct crit heal_kill)), 7)
    assert {%{ok: false, msg: m}, _} = Chaos.combine(full, "add_exc", "#S")
    assert m =~ "đủ dòng Excellent"
  end

  test "Pha Excellent thất bại: mất món, nguyên liệu, vàng" do
    g = %{Gear.new("item_8_5", 1, %{}) | uid: "#A"}
    p = setup_p(g, 5)
    Rng.put_sequence([0.99])
    {res, q} = Chaos.combine(p, "add_exc", "#A")
    assert res.chaos.result == "fail" and q.gear == [] and q.upgrades == %{}
    assert q.gold == p.gold - Data.chaos("add_exc").gold
  end

  test "Pha May mắn: thêm May mắn; món đã có hoặc chưa đủ +3 thì không nhận; cánh không nhận" do
    g = %{Gear.new("item_8_5", 1, %{}) | uid: "#A"}
    Rng.put_sequence([0.0])
    {res, q} = Chaos.combine(setup_p(g, 3), "add_luck", "#A")
    assert res.chaos.result == "success"
    assert [%{luck: true}] = q.gear

    assert {%{ok: false, msg: m}, _} =
             Chaos.combine(setup_p(Map.put(g, :luck, true), 3), "add_luck", "#A")

    assert m =~ "đã có May mắn"
    assert {%{ok: false}, _} = Chaos.combine(setup_p(g, 2), "add_luck", "#A")

    w = %{Gear.plain("wing_dk_1") | uid: "#W"}
    assert {%{ok: false}, _} = Chaos.combine(setup_p(w, 9), "add_luck", "#W")
  end
end

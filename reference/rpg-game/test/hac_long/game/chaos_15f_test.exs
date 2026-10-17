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

  test "Pha Excellent: thêm 1 dòng, giữ cấp nâng và uid; tối đa đủ 6 dòng như MU (B-16)" do
    g = %{Gear.new("item_0_3", 1) | uid: "#S"}
    p = setup_p(g, 7)
    r = Data.chaos("add_exc")

    Rng.put_sequence([0.0, 0.0])
    {res, q} = Chaos.combine(p, "add_exc", "#S")
    assert res.chaos.result == "success"
    assert [%{uid: "#S", exc: [line], opt: 1}] = q.gear
    assert line in Gear.exc_pool("weapon")
    assert q.upgrades["#S"] == 7
    assert q.gold == p.gold - r.gold and q.inv["jewel_chaos"] == 4 and q.inv["jewel_life"] == 3
    assert Chaos.rate(r, 7) == Float.round(r.rate + 2 * r.per_up, 3)

    # 3 dòng vẫn thêm được (trước B-16 là trần)
    three = setup_p(Map.put(g, :exc, ~w(atk_pct crit heal_kill)), 7)
    Rng.put_sequence([0.0, 0.0])
    assert {%{ok: true}, q3} = Chaos.combine(three, "add_exc", "#S")
    assert length(hd(q3.gear).exc) == 4

    full = setup_p(Map.put(g, :exc, Gear.exc_pool("weapon")), 7)
    assert length(Gear.exc_pool("weapon")) == 6
    assert {%{ok: false, msg: m}, _} = Chaos.combine(full, "add_exc", "#S")
    assert m =~ "đủ dòng Excellent"
  end

  test "Pha Excellent thất bại: giữ món (cấp nâng, dòng không đổi), mất nguyên liệu, vàng" do
    g = %{Gear.new("item_8_5", 1) | uid: "#A"}
    p = setup_p(g, 5)
    Rng.put_sequence([0.99])
    {res, q} = Chaos.combine(p, "add_exc", "#A")
    assert res.chaos.result == "fail" and q.gear == p.gear and q.upgrades == p.upgrades
    assert res.msg =~ "còn nguyên"

    assert Enum.all?(Data.chaos("add_exc").items, fn {id, n} ->
             Map.get(q.inv, id, 0) == Map.get(p.inv, id, 0) - n
           end)

    assert q.gold == p.gold - Data.chaos("add_exc").gold
  end

  test "Pha May mắn: thêm May mắn; món đã có hoặc chưa đủ +3 thì không nhận; cánh không nhận" do
    g = %{Gear.new("item_8_5", 1) | uid: "#A"}
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

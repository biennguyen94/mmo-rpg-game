defmodule HacLong.Game.Items15cTest do
  @moduledoc """
  Phase 15c (docs/ITEMS_PHASE15B.md §6): đồ bậc 7–8, nhẫn (2 ô) + dây chuyền, thưởng đủ bộ giáp, đồ Excellent.
  """
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine, Gear, Rng}

  setup do
    on_exit(&Rng.clear/0)
    :ok
  end

  defp player(cls, attrs \\ %{}) do
    {:ok, p} = Engine.new_player("Thử", cls)
    Map.merge(p, attrs)
  end

  @rules Data.rules()

  test "bậc 7–8: vũ khí cấp 32, bộ giáp cấp 27 / 32 cho mỗi lớp; Thợ Rèn bán" do
    assert %{level: 32, tier: 8, classes: ["dk", "mg"]} = Data.item("item_1_8")
    assert %{level: 27, tier: 7, set: "Hắc Long"} = Data.item("item_8_16")
    assert %{level: 32, tier: 8, classes: ["dw"]} = Data.item("item_8_22")
    assert %{level: 32, tier: 8, classes: ["elf"]} = Data.item("item_8_24")
    assert "item_1_8" in Data.shop() and "item_8_24" in Data.shop()
  end

  test "nhẫn vào ô trống (ring1 rồi ring2), dây chuyền cộng tấn công, nhẫn cộng máu / thủ; không bán ở cửa hàng" do
    p =
      player("dw", %{level: 40})
      |> Engine.add_item("item_13_8", 2)
      |> Engine.add_item("item_13_12")

    base = Engine.derived(p)
    {%{ok: true}, p} = Engine.equip(p, "item_13_8")
    {%{ok: true}, p} = Engine.equip(p, "item_13_8")
    assert p.equip.ring1 == "item_13_8" and p.equip.ring2 == "item_13_8"
    assert Engine.derived(p).maxHp == base.maxHp + 50

    {%{ok: true}, p} = Engine.equip(p, "item_13_12")
    assert p.equip.pendant == "item_13_12"
    assert Engine.derived(p).atk == base.atk + 3

    {%{ok: true}, p} = Engine.unequip(p, "ring2")
    assert p.equip.ring2 == nil and p.inv["item_13_8"] == 1
    refute "item_13_8" in Data.shop() or "item_13_12" in Data.shop()
    refute Map.has_key?(Data.starters("dk"), :ring1)
  end

  test "đồ rơi loại \"jewelry\" ra nhẫn hoặc dây chuyền hợp cấp" do
    for _ <- 1..30 do
      g = Gear.roll(30, Gear.weights(), "jewelry", "elf")
      assert Data.item(g.base).slot in ~w(ring pendant)
    end
  end

  test "thưởng đủ bộ: đủ 5 món bộ bậc ≥ 2 thì cộng thủ %, công %, máu; thiếu một món hoặc bộ khởi đầu thì không" do
    sb = @rules.set_bonus
    # bộ khởi đầu (Da, bậc 1) đủ 5 món nhưng không có thưởng
    p = player("dk")
    assert %{name: "Da", have: 5, need: 5, active: false} = Engine.set_bonus(p)

    # bộ Đồng (bậc 2) đủ 5 món
    bronze = %{
      helm: "item_7_0",
      armor: "item_8_0",
      pants: "item_9_0",
      gloves: "item_10_0",
      boots: "item_11_0"
    }

    q = %{p | level: 10, equip: Map.merge(p.equip, bronze)}
    assert %{name: "Đồng", tier: 2, active: true, hp: hp} = Engine.set_bonus(q)
    assert hp == sb.hp_per_tier * 2
    off = %{q | equip: %{q.equip | boots: "item_11_5"}}
    refute Engine.set_bonus(off).active

    d_on = Engine.derived(q)
    d_off = Engine.derived(off)
    assert d_on.maxHp - d_off.maxHp == hp
    assert d_on.atk > d_off.atk

    # Đấu Sĩ không đội mũ: đủ bộ là 4 món
    mg = %{player("mg") | equip: Map.merge(player("mg").equip, Map.delete(bronze, :helm))}
    assert %{need: 4, active: true} = Engine.set_bonus(mg)
  end

  test "Excellent: dòng đúng loại đồ, cộng vào chỉ số, lưu / nạp, bán đắt hơn" do
    g = Gear.new("item_0_3", 0, %{})
    assert Gear.excellent(g, 0) == g

    Rng.put_sequence([0.0, 0.99, 0.1, 0.5, 0.9])
    w = Gear.excellent(g, 1.0)
    assert w.exc != [] and Enum.all?(w.exc, &(&1 in ~w(atk_pct crit heal_kill mp_kill)))

    arm = Gear.excellent(Gear.new("item_8_5", 0, %{}), 1.0)
    assert Enum.all?(arm.exc, &(&1 in ~w(hp_pct dmg_red gold_pct)))

    # mặc vũ khí Excellent "atk_pct": tấn công tăng theo %
    p = player("dk", %{level: 20})
    sword = %{Gear.new("item_0_3", 0, %{}) | uid: "#EXC"} |> Map.put(:exc, ["atk_pct", "crit"])
    plain = %{sword | uid: "#PLN"} |> Map.delete(:exc)
    {pe, _} = Gear.add(p, sword)
    {%{ok: true}, pe} = Engine.equip(pe, "#EXC")
    {pp, _} = Gear.add(p, plain)
    {%{ok: true}, pp} = Engine.equip(pp, "#PLN")
    opt = @rules.excellent.options.weapon
    # làm tròn một lần trên tổng nên lệch tối đa 1
    assert_in_delta Engine.derived(pe).atk, Engine.derived(pp).atk * (1 + opt.atk_pct), 1
    assert_in_delta Engine.derived(pe).crit, Engine.derived(pp).crit + opt.crit, 1.0e-9
    assert Gear.exc_stats(pe).atk_pct == opt.atk_pct

    r = Gear.resolve(sword)
    assert r.excellent and r.sell == Gear.price(plain) * @rules.excellent.price_mult
    assert [%{id: "atk_pct", value: v} | _] = r.exc_lines
    assert v == opt.atk_pct

    # lưu (JSON, khóa chuỗi) rồi nạp lại giữ dòng Excellent; dòng lạ bị bỏ
    saved =
      sword |> Jason.encode!() |> Jason.decode!() |> Map.put("exc", ["atk_pct", "crit", "xxx"])

    assert [%{exc: ["atk_pct", "crit"]}] = Gear.load([saved])
  end

  test "Excellent giảm sát thương bị chặn ở max_dmg_red" do
    p = player("dk", %{level: 20})

    gs =
      for {base, i} <- Enum.with_index(~w(item_8_5 item_9_5 item_10_5 item_11_5 item_7_5)) do
        %{Gear.new(base, 0, %{}) | uid: "#A#{i}"} |> Map.put(:exc, ["dmg_red"])
      end

    p =
      Enum.reduce(gs, p, fn g, p ->
        p |> Gear.add(g) |> elem(0) |> Engine.equip(g.uid) |> elem(1)
      end)

    assert Gear.exc_stats(p).dmg_red ==
             min(5 * @rules.excellent.options.armor.dmg_red, @rules.excellent.max_dmg_red)

    assert Engine.derived(p).excAbsorb == Gear.exc_stats(p).dmg_red
  end
end

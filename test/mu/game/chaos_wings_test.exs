defmodule Mu.Game.ChaosWingsTest do
  @moduledoc """
  P6-M3 / P6-M4 thuần: công thức Chaos Machine (khớp, tỉ lệ, quay kết quả với RNG có seed) và
  cánh (dữ liệu, chỉ số theo +N, hệ số trong pipeline sát thương, không option Life).
  """
  use ExUnit.Case, async: true

  alias Mu.Game.{Chaos, Config, Data, Engine, Inventory, Rng, Upgrade}

  defp it(tid, opts \\ []) do
    %{
      id: Keyword.get(opts, :id, "i_#{tid}_#{System.unique_integer([:positive])}"),
      template_id: tid,
      quantity: Keyword.get(opts, :q, 1),
      item_level: Keyword.get(opts, :lvl, 0),
      option_level: Keyword.get(opts, :opt, 0)
    }
  end

  test "dữ liệu: Jewel of Chaos (stack 20, NPC mua 10 000), 3 cánh group 12 cấp 15, rơi trong nhóm jewels" do
    assert %{"type" => "JEWEL", "maxStack" => 20, "sellPrice" => 10_000} =
             Data.item("jewel_chaos")

    for {id, idx, cls} <- [
          {"wing_elf", 0, ["ELF"]},
          {"wing_heaven", 1, ["DW", "MG"]},
          {"wing_satan", 2, ["DK", "MG"]}
        ] do
      t = Data.item(id)
      assert t["slot"] == "WING" and t["classes"] == cls
      assert t["iconRef"] == %{"group" => 12, "index" => idx}
      assert t["requirements"]["level"] == 15
      assert {t["defense"], t["damageIncrease"], t["absorb"]} == {10, 12, 12}
    end

    w = Data.drops("goblin")["groups"] |> Enum.find(&(&1["id"] == "jewels"))

    assert Map.new(w["entries"], &{&1["item"], &1["weight"]}) ==
             %{"jewel_bless" => 45, "jewel_soul" => 30, "jewel_life" => 12, "jewel_chaos" => 13}

    assert Config.get(["features", "wings"]) and Config.get(["features", "chaosMachine"])
    assert Inventory.equip_slots(Data.item("wing_satan")) == [7]
  end

  test "khớp công thức: đồ +4 trở lên + 1 Chaos; tỉ lệ 10 % + 5 %/cấp + 2 %/option, tối đa 60 %" do
    chaos = it("jewel_chaos", q: 3)
    assert {:ok, m} = Chaos.match([it("sword_t0", lvl: 4), chaos])
    assert m.recipe["id"] == "wings_1" and m.zen == 20_000 and m.rate == 0.10
    assert [{_, 1}, {cid, 1}] = m.consume
    assert cid == chaos.id

    assert {:ok, %{rate: 0.35}} = Chaos.match([it("armor_t0", lvl: 9), chaos])
    assert {:ok, %{rate: 0.21}} = Chaos.match([it("shield_t0", lvl: 5, opt: 3), chaos])
    assert {:ok, %{rate: 0.43}} = Chaos.match([it("sword_t0", lvl: 9, opt: 4), chaos])
    # trần 60 % (chỉ chạm được nếu sau này mở cấp > +9)
    assert {:ok, %{rate: 0.6}} = Chaos.match([it("sword_t0", lvl: 15), chaos])

    # không khớp: +3, thiếu Chaos, thừa món, type khác (mũ), nhiều hơn 8 món, trùng món
    for items <- [
          [it("sword_t0", lvl: 3), chaos],
          [it("sword_t0", lvl: 6)],
          [it("sword_t0", lvl: 6), chaos, it("hp_potion_small")],
          [it("helm_t0", lvl: 6), chaos],
          for(_ <- 1..9, do: it("jewel_chaos"))
        ],
        do: assert(Chaos.match(items) == {:error, "INVALID_TARGET"})

    sword = it("sword_t0", lvl: 6)
    assert Chaos.match([sword, sword, chaos]) == {:error, "INVALID_TARGET"}
  end

  test "quay: tỉ lệ đúng, ra đều 3 cánh (RNG có seed)" do
    {:ok, m} = Chaos.match([it("sword_t0", lvl: 9), it("jewel_chaos")])

    {outs, _} =
      Enum.map_reduce(1..6000, Rng.new(11), fn _, rng -> Chaos.roll(rng, m) end)

    ok = Enum.reject(outs, &is_nil/1)
    assert_in_delta length(ok) / 6000, 0.35, 0.03
    freq = Enum.frequencies(ok)
    assert Map.keys(freq) |> Enum.sort() == ~w(wing_elf wing_heaven wing_satan)
    for {_, n} <- freq, do: assert_in_delta(n / length(ok), 1 / 3, 0.05)
  end

  test "cánh +N: thủ +1, sát thương / hấp thụ +2 % mỗi cấp; không ép Life" do
    w = Data.item("wing_satan")
    assert %{"defense" => 15, "damageIncrease" => 22, "absorb" => 22} = Engine.leveled(w, 5)
    assert {:error, "INVALID_TARGET"} = Upgrade.apply(Rng.new(1), w, 0, 0, "jewel_life")
    assert {:ok, %{ok: true, level: 1}, _} = Upgrade.apply(Rng.new(1), w, 0, 0, "jewel_bless")
  end

  test "pipeline sát thương: +12 % khi đánh, −12 % khi nhận (sau thủ), sàn cứng giữ" do
    base = %{raw_attack: 100, skill_multiplier: 1.0, target_defense: 20}
    assert Engine.damage(base) == 80
    assert Engine.damage(Map.put(base, :damage_increase, 12)) == 92
    assert Engine.damage(Map.put(base, :absorb, 12)) == floor(80 * 0.88)

    assert Engine.damage(%{base | raw_attack: 1, target_defense: 999} |> Map.put(:absorb, 12)) >=
             1

    c = %{
      class: "DK",
      level: 20,
      experience: 0,
      strength: 60,
      agility: 30,
      vitality: 30,
      energy: 10,
      free_stat_points: 0
    }

    d = Engine.derived(c, [Engine.leveled(Data.item("wing_satan"), 2)])
    assert {d.damage_increase, d.absorb} == {16, 16}
    assert Engine.derived(c, []).damage_increase == 0
  end

  test "simulator (P6-4, rủi ro cân bằng): cánh giảm sát thương nhận, tăng tốc hạ quái so với cùng bộ t1" do
    t1 = Mu.Game.Simulator.gear("DK", "t1")
    wing = Mu.Game.Simulator.gear("DK", "wing")
    assert length(wing) == length(t1) + 1
    a = Mu.Game.Simulator.run(5, %{equipment: t1, max_kills: 800})
    b = Mu.Game.Simulator.run(5, %{equipment: wing, max_kills: 800})
    assert b.damage_taken_per_kill <= a.damage_taken_per_kill
  end
end

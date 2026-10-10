defmodule HacLong.Game.Wings15eTest do
  @moduledoc """
  Phase 15e (docs/ITEMS_PHASE15B.md §8): cánh cấp 3 và dòng phụ của cánh.
  """
  use ExUnit.Case, async: true

  alias HacLong.Game.{Chaos, Data, Engine, Gear, Rng}

  setup do
    on_exit(&Rng.clear/0)
    :ok
  end

  @wo Map.new(Data.rules().wing_options.by_tier, &{&1.tier, &1})

  defp player(cls) do
    {:ok, p} = Engine.new_player("Thử", cls)
    %{p | level: 45, gold: 1_000_000}
  end

  defp wear(p, g) do
    {p, :kept} = Gear.add(p, g)
    {%{ok: true}, p} = Engine.equip(p, g.uid)
    p
  end

  defp wing3_input(p, up) do
    g = Gear.plain("wing_#{p.cls}_2")

    p =
      %{p | gear: [g]}
      |> Map.put(:upgrades, %{g.uid => up})
      |> Engine.add_item("jewel_bless", 10)
      |> Engine.add_item("jewel_soul", 10)
      |> Engine.add_item("jewel_chaos", 3)
      |> Engine.add_item("jewel_life", 3)

    {p, g.uid}
  end

  test "cánh cấp 3 cho cả 4 lớp, cấp 45, mạnh hơn cấp 2, có hình gốc" do
    for cls <- ~w(dk dw elf mg) do
      w3 = Data.item("wing_#{cls}_3")
      w2 = Data.item("wing_#{cls}_2")
      assert %{slot: "wing", tier: 3, level: 45} = w3
      assert w3.dmg > w2.dmg and w3.absorb > w2.absorb and w3.def > w2.def
      assert w3[:ref] =~ ~r{^12/3[6-9]$}
    end
  end

  test "Máy Hỗn Nguyên: cánh cấp 2 +9 → cánh cấp 3 đúng lớp, có một dòng cánh" do
    {p, uid} = wing3_input(player("dw"), 9)
    # bốc 0.0: thành công; 0.4 → dòng thứ hai (mp)
    Rng.put_sequence([0.0, 0.4])
    {r, q} = Chaos.combine(p, "wing3", uid)
    assert r.chaos == %{result: "success", out: "wing_dw_3"}
    assert [%{base: "wing_dw_3", wopt: "mp"}] = q.gear
    assert q.gold == p.gold - Data.chaos("wing3").gold

    # cánh cấp 2 dưới +9 không nhận; cánh cấp 1 không nhận
    {p8, uid8} = wing3_input(player("dw"), 8)
    assert {%{ok: false}, _} = Chaos.combine(p8, "wing3", uid8)
    g1 = Gear.plain("wing_dw_1")
    p1 = %{p | gear: [g1]} |> Map.put(:upgrades, %{g1.uid => 11})
    assert {%{ok: false}, _} = Chaos.combine(p1, "wing3", g1.uid)
  end

  test "ghép cánh cấp 2 cũng có dòng; cánh cấp 1 thì không" do
    g = Gear.plain("wing_dk_1")
    p = %{player("dk") | gear: [g]} |> Map.put(:upgrades, %{g.uid => 5})

    p =
      p
      |> Engine.add_item("jewel_bless", 5)
      |> Engine.add_item("jewel_soul", 5)
      |> Engine.add_item("jewel_chaos", 2)

    Rng.put_sequence([0.0, 0.0])
    {%{chaos: %{result: "success"}}, q} = Chaos.combine(p, "wing2", g.uid)
    assert [%{base: "wing_dk_2", wopt: "hp"}] = q.gear

    refute Map.has_key?(Gear.wing_option(%{Gear.plain("wing_dk_1") | uid: "#W1"}), :wopt)
  end

  test "dòng cánh cộng máu / MP / bỏ qua phòng thủ khi mặc" do
    p = player("dk")
    base = Engine.derived(p)

    hp = Engine.derived(wear(p, Map.put(Gear.plain("wing_dk_3"), :wopt, "hp")))
    plain = Engine.derived(wear(p, Gear.plain("wing_dk_3")))
    assert hp.maxHp == plain.maxHp + @wo[3].hp

    mp = Engine.derived(wear(p, Map.put(Gear.plain("wing_dk_3"), :wopt, "mp")))
    assert mp.maxMp == base.maxMp + @wo[3].mp

    ig = Engine.derived(wear(p, Map.put(Gear.plain("wing_dk_2"), :wopt, "ignore_def")))
    assert ig.ignoreDef == @wo[2].ignore_def
    assert plain.ignoreDef == 0

    # hình nhân vật: cánh cấp 3
    assert Engine.look(wear(p, Gear.plain("wing_dk_3"))).wing == %{cls: "dk", tier: 3}
  end

  test "lưu / nạp giữ dòng cánh; dòng lạ bị bỏ; tooltip có giá trị" do
    g = Map.put(Gear.plain("wing_elf_3"), :wopt, "ignore_def")
    [l] = g |> Jason.encode!() |> Jason.decode!() |> List.wrap() |> Gear.load()
    assert l.wopt == "ignore_def"

    [bad] =
      g
      |> Jason.encode!()
      |> Jason.decode!()
      |> Map.put("wopt", "xxx")
      |> List.wrap()
      |> Gear.load()

    refute Map.has_key?(bad, :wopt)

    r = Gear.resolve(g)
    assert r.wopt == "ignore_def" and r.wopt_value == @wo[3].ignore_def
  end
end

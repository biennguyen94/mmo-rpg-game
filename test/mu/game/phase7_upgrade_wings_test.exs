defmodule Mu.Game.Phase7UpgradeWingsTest do
  @moduledoc """
  P7-M2 / P7-M3 thuần (RNG có seed): ép +10 / +11 bằng Jewel of Chaos (50 % / 45 %, thất bại mất
  đồ, chỉ số +10 / +11 gấp đôi); cánh cấp 2 ở Chaos Machine (cánh cấp 1 +5↑ + 5 Bless + 5 Soul +
  2 Chaos + 200 000 Zen, ra đúng class).
  """
  use ExUnit.Case, async: true

  alias Mu.Game.{Chaos, Data, Engine, Rng, Upgrade}

  @sword Data.item("sword_t0")

  defp it(tid, opts \\ []) do
    %{
      id: "i_#{tid}_#{System.unique_integer([:positive])}",
      template_id: tid,
      quantity: Keyword.get(opts, :q, 1),
      item_level: Keyword.get(opts, :lvl, 0),
      option_level: 0
    }
  end

  defp many(level, n \\ 4000) do
    {res, _} =
      Enum.map_reduce(1..n, Rng.new(3), fn _, rng ->
        {:ok, r, rng} = Upgrade.apply(rng, @sword, level, 0, "jewel_chaos")
        {r, rng}
      end)

    res
  end

  test "+9 → +10 (50 %), +10 → +11 (45 %) bằng Chaos; thất bại mất đồ; +11 hết bảng" do
    for {l, p} <- [{9, 0.5}, {10, 0.45}] do
      res = many(l)
      assert_in_delta Enum.count(res, & &1.ok) / length(res), p, 0.03
      assert Enum.all?(res, &if(&1.ok, do: &1.level == l + 1, else: &1.destroyed))
    end

    # Chaos chỉ dùng cho +9 / +10; Bless / Soul không ép quá +9
    assert {:error, "INVALID_TARGET"} = Upgrade.apply(Rng.new(1), @sword, 8, 0, "jewel_chaos")
    assert {:error, "INVALID_TARGET"} = Upgrade.apply(Rng.new(1), @sword, 9, 0, "jewel_soul")
    assert {:error, "FORBIDDEN"} = Upgrade.apply(Rng.new(1), @sword, 11, 0, "jewel_chaos")
    # cánh ép được +10 bằng Chaos
    assert {:ok, _, _} = Upgrade.apply(Rng.new(1), Data.item("wing_satan"), 9, 0, "jewel_chaos")
  end

  test "chỉ số: +10 / +11 cộng gấp đôi levelBonus" do
    assert Enum.map([0, 9, 10, 11], &Engine.bonus_levels/1) == [0, 9, 11, 13]
    base = @sword["attackMax"]
    assert Engine.leveled(@sword, 9)["attackMax"] == base + 27
    assert Engine.leveled(@sword, 10)["attackMax"] == base + 33
    assert Engine.leveled(@sword, 11)["attackMax"] == base + 39
  end

  test "dữ liệu cánh cấp 2: 4 cánh theo class, cấp 25, +20 % / −20 %, thủ 20, group 12 / 3–6" do
    for {id, idx, cls} <- [
          {"wing_spirit", 3, ["ELF"]},
          {"wing_soul", 4, ["DW"]},
          {"wing_dragon", 5, ["DK"]},
          {"wing_darkness", 6, ["MG"]}
        ] do
      t = Data.item(id)
      assert {t["classes"], t["iconRef"]["index"], t["requirements"]["level"]} == {cls, idx, 25}
      assert {t["defense"], t["damageIncrease"], t["absorb"]} == {20, 20, 20}
    end
  end

  test "công thức cánh 2: cánh cấp 1 +5↑ + 5 Bless + 5 Soul + 2 Chaos; tỉ lệ 20 % + 5 %/cấp; ra đúng class" do
    mats = [it("jewel_bless", q: 6), it("jewel_soul", q: 5), it("jewel_chaos", q: 2)]
    assert {:ok, m} = Chaos.match([it("wing_satan", lvl: 5) | mats])
    assert {m.recipe["id"], m.rate, m.zen} == {"wings_2", 0.2, 200_000}
    assert {:ok, %{rate: 0.4}} = Chaos.match([it("wing_elf", lvl: 9) | mats])

    # không khớp: cánh +4, thiếu Chaos, cánh cấp 2 làm đầu vào
    assert {:error, _} = Chaos.match([it("wing_satan", lvl: 4) | mats])
    assert {:error, _} = Chaos.match([it("wing_satan", lvl: 6) | Enum.take(mats, 2)])
    assert {:error, _} = Chaos.match([it("wing_dragon", lvl: 9) | mats])

    {:ok, m} = Chaos.match([it("wing_heaven", lvl: 9) | mats])

    for {cls, out} <- [
          {"DK", "wing_dragon"},
          {"DW", "wing_soul"},
          {"ELF", "wing_spirit"},
          {"MG", "wing_darkness"}
        ] do
      {outs, _} = Enum.map_reduce(1..400, Rng.new(9), fn _, r -> Chaos.roll(r, m, cls) end)
      ok = Enum.reject(outs, &is_nil/1)
      assert Enum.uniq(ok) == [out]
      assert_in_delta length(ok) / 400, 0.4, 0.08
    end

    # công thức cánh cấp 1 vẫn ra ngẫu nhiên 3 cánh (không theo class)
    {:ok, w1} = Chaos.match([it("sword_t0", lvl: 9), it("jewel_chaos")])
    {outs, _} = Enum.map_reduce(1..600, Rng.new(4), fn _, r -> Chaos.roll(r, w1, "DK") end)
    assert outs |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length() == 3
  end
end

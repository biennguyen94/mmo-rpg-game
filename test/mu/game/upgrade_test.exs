defmodule Mu.Game.UpgradeTest do
  @moduledoc "P5-M2: ép jewel theo bảng KB_CONFIG §5 + Jewel of Life (P5-4 A), hàm thuần, RNG có seed."
  use ExUnit.Case, async: true

  alias Mu.Game.{Config, Data, Rng, Upgrade}

  @sword Data.item("sword_t0")

  defp try_many(level, option, jewel, n \\ 4000) do
    {res, _} =
      Enum.map_reduce(1..n, Rng.new(7), fn _, rng ->
        {:ok, r, rng} = Upgrade.apply(rng, @sword, level, option, jewel)
        {r, rng}
      end)

    res
  end

  test "Bless +0 … +5 → +1 … +6 luôn thành công; dùng Bless từ +6 / Soul dưới +6 → INVALID_TARGET" do
    for l <- 0..5 do
      assert {:ok, %{ok: true, level: to, option: 0}, _} =
               Upgrade.apply(Rng.new(1), @sword, l, 0, "jewel_bless")

      assert to == l + 1
      assert {:error, "INVALID_TARGET"} = Upgrade.apply(Rng.new(1), @sword, l, 0, "jewel_soul")
    end

    assert {:error, "INVALID_TARGET"} = Upgrade.apply(Rng.new(1), @sword, 6, 0, "jewel_bless")
  end

  test "Soul +6/+7/+8: tỉ lệ 70/60/50 %, hỏng giảm 1 cấp; +9 → FORBIDDEN" do
    for {l, p} <- [{6, 0.7}, {7, 0.6}, {8, 0.5}] do
      res = try_many(l, 0, "jewel_soul")
      ok = Enum.count(res, & &1.ok)
      assert_in_delta ok / length(res), p, 0.03
      assert Enum.all?(res, &(&1.level == if(&1.ok, do: l + 1, else: l - 1)))
    end

    assert {:error, "FORBIDDEN"} = Upgrade.apply(Rng.new(1), @sword, 9, 0, "jewel_soul")
    assert {:error, "FORBIDDEN"} = Upgrade.apply(Rng.new(1), @sword, 9, 0, "jewel_bless")
  end

  test "Life: option +1 với 50 %, hỏng không đổi, tối đa 4; giữ nguyên +N" do
    res = try_many(3, 1, "jewel_life")
    assert_in_delta Enum.count(res, & &1.ok) / length(res), 0.5, 0.03
    assert Enum.all?(res, &(&1.level == 3 and &1.option == if(&1.ok, do: 2, else: 1)))
    max = Config.get(["upgrade", "life", "maxOption"])
    assert {:error, "FORBIDDEN"} = Upgrade.apply(Rng.new(1), @sword, 0, max, "jewel_life")
  end

  test "nhẫn / jewel / potion không ép được; khiên, giáp ép được; cùng seed cùng kết quả" do
    for id <- ~w(ring_hp_t0 jewel_bless hp_potion_small) do
      assert {:error, "INVALID_TARGET"} =
               Upgrade.apply(Rng.new(1), Data.item(id), 0, 0, "jewel_bless")
    end

    for id <- ~w(shield_t0 helm_t0 armor_t0) do
      assert {:ok, %{ok: true, level: 1}, _} =
               Upgrade.apply(Rng.new(1), Data.item(id), 0, 0, "jewel_bless")
    end

    assert try_many(7, 0, "jewel_soul", 50) == try_many(7, 0, "jewel_soul", 50)
  end

  test "Engine: option Jewel of Life cộng +4 / cấp vào đòn (vũ khí) hoặc thủ (giáp)" do
    per = Config.get(["upgrade", "life", "perOption"])
    s = Mu.Game.Engine.leveled(@sword, 2, 3)
    assert s["attackMax"] == @sword["attackMax"] + 2 * 3 + 3 * per
    helm = Data.item("helm_t0")
    assert Mu.Game.Engine.leveled(helm, 0, 2)["defense"] == helm["defense"] + 2 * per
  end
end

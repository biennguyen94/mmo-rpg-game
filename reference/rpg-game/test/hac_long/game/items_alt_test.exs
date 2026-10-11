defmodule HacLong.Game.ItemsAltTest do
  @moduledoc """
  Phase 19 (docs/ITEMS_PHASE15B.md §13): món phụ (`alt`) — vũ khí, khiên, bộ giáp khác tên / hình / yêu cầu chỉ số
  nhưng chỉ số và giá như món chính cùng bậc; chỉ rơi, không bán, không làm đồ khởi đầu / đồ thay.
  """
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Gear, Rng}

  setup do
    on_exit(&Rng.clear/0)
    :ok
  end

  defp mu, do: Data.items() |> Enum.filter(fn {_, it} -> it[:sourceType] == "MU_ITEM_TXT" end)
  defp alts, do: Enum.filter(mu(), fn {_, it} -> it[:alt] end)
  defp mains, do: Enum.reject(mu(), fn {_, it} -> it[:alt] end)

  test "có món phụ ở vũ khí, khiên và bộ giáp" do
    slots = alts() |> Enum.map(fn {_, it} -> it.slot end) |> MapSet.new()
    assert MapSet.subset?(MapSet.new(~w(weapon shield armor)), slots)
  end

  test "vũ khí / khiên phụ: công, thủ, cấp, giá như món chính cùng bậc và cùng lớp" do
    for {id, a} <- alts(), a.slot in ~w(weapon shield) do
      main =
        Enum.find_value(mains(), fn {_, m} ->
          if m.slot == a.slot and m.tier == a.tier and Enum.any?(a.classes, &(&1 in m.classes)),
            do: m
        end)

      assert main, "#{id} không có món chính cùng bậc"

      for k <- ~w(atk atkMin atkMax def level price)a,
          do: assert(a[k] == main[k], "#{id} #{k}: #{inspect(a[k])} ≠ #{inspect(main[k])}")
    end
  end

  test "món phụ không bán, không làm đồ khởi đầu, không làm đồ thay" do
    ids = alts() |> Enum.map(&elem(&1, 0)) |> MapSet.new()
    refute Enum.any?(Data.shop(), &(&1 in ids))

    for cls <- ~w(dk dw elf mg), {_, id} <- Data.starters(cls), do: refute(id in ids)

    for {old, _} <- Data.items(),
        Data.legacy?(old),
        cls <- ~w(dk dw elf mg),
        do: refute(Data.replacement(old, cls) in ids)
  end

  test "khiên chính đủ 8 bậc và đều có bán" do
    shields = for {id, it} <- mains(), it.slot == "shield", do: {it.tier, id}
    assert shields |> Enum.map(&elem(&1, 0)) |> Enum.sort() == Enum.to_list(1..8)
    assert Enum.all?(shields, fn {_, id} -> id in Data.shop() end)
  end

  test "bộ riêng của Đấu Sĩ không có mũ, đủ bộ 4 món" do
    for {_, it} <- alts(), it.classes == ["mg"] do
      refute it.slot == "helm"
      assert Data.set_size(it.set, "mg") == 4
    end
  end

  test "đồ rơi bốc được cả món phụ, bậc dưới vẫn còn trong danh sách" do
    picks =
      for i <- 0..99 do
        # ô đã chọn (vũ khí): i/100 chọn món trong danh sách; 0.5: độ hiếm
        Rng.put_sequence([i / 100, 0.5])
        g = Gear.roll(32, Gear.weights(), "weapon", "dk")
        Data.items()[g.base]
      end

    assert Enum.any?(picks, & &1[:alt])
    assert picks |> Enum.map(& &1.tier) |> Enum.uniq() |> length() == 2
  end
end

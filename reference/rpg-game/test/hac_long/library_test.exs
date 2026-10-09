defmodule HacLong.LibraryTest do
  # Phase 14: Thư viện sinh từ dữ liệu game
  use ExUnit.Case, async: true

  alias HacLong.Library
  alias HacLong.Game.Data

  setup_all do
    %{lib: Library.build()}
  end

  test "đủ quái của mọi vùng (cả trùm), có chỉ số và nơi xuất hiện", %{lib: lib} do
    n =
      Enum.reduce(Data.zones(), length(Data.side_monsters()), fn z, acc ->
        acc + length(z.monsters) + 1
      end)

    assert length(lib.monsters) == n
    bat = Enum.find(lib.monsters, &(&1.id == "bat"))
    assert bat.hp > 0 and bat.atk > 0 and bat.where != []
    wolf = Enum.find(lib.monsters, &(&1.id == "wolf"))
    assert wolf.boss and wolf.where != []
  end

  test "mọi vật phẩm có mặt; bình máu có nguồn cửa hàng và quái rơi", %{lib: lib} do
    assert length(lib.items) == map_size(Data.items())
    pot = Enum.find(lib.items, &(&1.id == "potion_s"))
    assert Enum.any?(pot.sources, &(&1 =~ "Bán:"))
    assert Enum.any?(pot.sources, &(&1 =~ "rơi"))
  end

  test "bản đồ: không có Nhà riêng, có cấp quái và cổng", %{lib: lib} do
    refute Enum.any?(lib.maps, &(&1.id == "home"))
    f = Enum.find(lib.maps, &(&1.id == "forest_1"))
    assert f.min >= 1 and f.to != [] and "bat" in f.monsters
  end
end

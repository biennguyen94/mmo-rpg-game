defmodule HacLong.Game.ItemBuildTest do
  @moduledoc "Phase 15b: dựng đồ từ nháp Item.txt theo ITEM_PICK (docs/ITEMS_PHASE15B.md)."
  use ExUnit.Case, async: true

  alias HacLong.Game.ItemBuild

  defp draft(ref, name, extra) do
    [g, i] = String.split(ref, "/")
    Map.merge(%{"id" => "item_#{g}_#{i}", "ref" => ref, "name" => name, "req" => %{}}, extra)
  end

  defp drafts do
    Map.new(
      [
        draft("0/1", "Short Sword", %{"atkMin" => 3, "atkMax" => 7, "req" => %{"str" => 60}}),
        draft("0/2", "Rapier", %{
          "atkMin" => 9,
          "atkMax" => 15,
          "req" => %{"str" => 50, "agi" => 40}
        }),
        draft("5/0", "Skull Staff", %{"atkMin" => 3, "atkMax" => 5}),
        draft("6/0", "Small Shield", %{"def" => 1, "req" => %{"str" => 70}}),
        draft("7/5", "Leather Helm", %{"def" => 5}),
        draft("8/5", "Leather Armor", %{"def" => 10}),
        draft("9/5", "Leather Pants", %{"def" => 7}),
        draft("10/5", "Leather Gloves", %{"def" => 2}),
        draft("11/5", "Leather Boots", %{"def" => 2})
      ],
      &{&1["ref"], &1}
    )
  end

  @pick %{
    "sourceType" => "MU_ITEM_TXT",
    "version" => 1,
    "verified" => false,
    "req_mult" => 0.5,
    "no_req_tiers" => [1],
    "levels" => %{"weapon" => [1, 5], "set" => [1], "shield" => [4]},
    "stats" => %{
      "staff_atk" => [10],
      "set_def" => [26],
      "set_def_mult" => 1.0,
      "shield_def" => [3]
    },
    "prices" => %{
      "weapon" => [0, 100],
      "set" => [200],
      "shield" => [90],
      "piece_weight" => %{"armor" => 1.0, "helm" => 0.5}
    },
    "pieces" => %{"helm" => "Mũ", "armor" => "Giáp"},
    "no_helm" => ["mg"],
    "weapons" => %{
      "dk" => [%{"ref" => "0/1", "name" => "Kiếm Ngắn"}, %{"ref" => "0/2", "name" => "Kiếm Mảnh"}],
      "dw" => [%{"ref" => "5/0", "name" => "Gậy Đầu Lâu", "mode" => "staff"}],
      "mg" => "dk"
    },
    "shields" => [%{"ref" => "6/0", "name" => "Khiên Nhỏ"}],
    "sets" => %{"dk" => [%{"index" => 5, "name" => "Da"}], "mg" => "dk"}
  }

  setup do
    {:ok, items, warns} = ItemBuild.build(drafts(), @pick)
    %{by: Map.new(items, &{&1["id"], &1}), warns: warns}
  end

  test "vũ khí: công = trung bình của file, cấp và giá theo bậc, lớp gộp khi dùng chung danh sách",
       %{by: by} do
    r = by["item_0_2"]

    assert %{
             "atk" => 12,
             "atkMin" => 9,
             "atkMax" => 15,
             "level" => 5,
             "price" => 100,
             "tier" => 2
           } = r

    assert r["classes"] == ["dk", "mg"] and r["name"] == "Kiếm Mảnh" and r["mu_name"] == "Rapier"
    assert r["req"] == %{"str" => 25, "agi" => 20}
    assert %{"sourceType" => "MU_ITEM_TXT", "version" => 1, "verified" => false} = r
  end

  test "bậc trong no_req_tiers không đòi chỉ số (đồ khởi đầu); khiên vẫn đòi", %{by: by} do
    assert by["item_0_1"]["req"] == %{}
    assert by["item_6_0"]["req"] == %{"str" => 35}
    assert %{"def" => 3, "level" => 4, "price" => 90} = by["item_6_0"]
  end

  test "gậy: công theo staff_atk, khoảng thấp ~ cao theo tỉ lệ của file", %{by: by} do
    assert %{"atk" => 10, "atkMin" => 8, "atkMax" => 13, "classes" => ["dw"]} = by["item_5_0"]
  end

  test "bộ giáp: tổng thủ = set_def × mult chia theo tỉ lệ; mg không có mũ; giá nhân trọng số", %{
    by: by
  } do
    pieces = for id <- ~w(item_7_5 item_8_5 item_9_5 item_10_5 item_11_5), do: by[id]
    assert Enum.map(pieces, & &1["def"]) == [5, 10, 7, 2, 2]
    assert by["item_7_5"]["classes"] == ["dk"] and by["item_8_5"]["classes"] == ["dk", "mg"]
    assert by["item_8_5"]["name"] == "Giáp Da" and by["item_8_5"]["set"] == "Da"
    assert by["item_7_5"]["price"] == 100 and by["item_8_5"]["price"] == 200
    # khóa chưa có trong `pieces` thì dùng tên ô
    assert by["item_9_5"]["name"] == "pants Da"
  end

  test "piece_weight \"def\": giá món trong bộ chia theo tỉ lệ thủ, đủ bộ bằng giá bậc" do
    pick = put_in(@pick, ["prices", "piece_weight"], "def")
    {:ok, items, []} = ItemBuild.build(drafts(), pick)
    set = Enum.filter(items, &(&1["set"] == "Da"))
    # làm tròn từng món nên lệch vài vàng
    assert abs((Enum.map(set, & &1["price"]) |> Enum.sum()) - 200) <= 2
    assert Enum.find(set, &(&1["slot"] == "armor"))["price"] == round(200 * 10 / 26)
  end

  test "món không có trong Item.txt thành cảnh báo, không làm hỏng cả bảng" do
    pick = put_in(@pick, ["shields"], [%{"ref" => "6/99", "name" => "?"}])
    assert {:ok, items, ["không có 6/99 trong Item.txt"]} = ItemBuild.build(drafts(), pick)
    refute Enum.any?(items, &(&1["slot"] == "shield"))
  end
end

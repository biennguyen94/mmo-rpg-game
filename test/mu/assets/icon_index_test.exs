defmodule Mu.Assets.IconIndexTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mu.Assets.IconIndex
  alias Mu.Game.Data

  # file giả (copy placeholder của dự án, chỉ đổi tên) — không phải asset MU
  @png File.read!(Path.expand("../../../priv/static/assets/icons/placeholder.png", __DIR__))

  test "parse tên file" do
    assert {:ok, %{group: 0, index: 1, bucket: 9, excellent: true, ancient: false}} =
             IconIndex.parse_name("item_0_1_9_e.png")

    assert {:ok, %{group: 14, index: 1, bucket: nil, excellent: false}} =
             IconIndex.parse_name("item_14_1.png")

    assert {:ok, %{ancient: true}} = IconIndex.parse_name("item_8_5_0_a.png")
    assert :error = IconIndex.parse_name("sword.png")
    assert :error = IconIndex.parse_name("item_0_1.jpg")
  end

  test "bucket §4.2" do
    assert Enum.map([0, 2, 3, 6, 9, 10, 15, 20], &IconIndex.bucket/1) == [
             0,
             0,
             3,
             5,
             9,
             9,
             15,
             15
           ]
  end

  test "thứ tự thử §4.3" do
    assert IconIndex.candidates(0, 1, 5, true) == [
             "item_0_1_5_e.png",
             "item_0_1_5.png",
             "item_0_1_3_e.png",
             "item_0_1_3.png",
             "item_0_1_0_e.png",
             "item_0_1_0.png",
             "item_0_1_e.png",
             "item_0_1.png"
           ]

    assert IconIndex.candidates(0, 1, 3, false) == [
             "item_0_1_3.png",
             "item_0_1_3.png",
             "item_0_1_0.png",
             "item_0_1.png",
             "item_0_1.png"
           ]
  end

  test "build: chọn file theo fallback, custom, thiếu → placeholder, tên lạ, Ancient bỏ" do
    files =
      ~w(item_0_1_0.png item_0_1_9_e.png item_7_5.png item_14_1_3.png junk.png item_8_5_0_a.png)

    r = IconIndex.build(files, Data.items(), ["ring_hp_t0.png"])

    assert r.map["0/1"]["0"] == "items/item_0_1_0.png"
    assert r.map["0/1"]["9e"] == "items/item_0_1_9_e.png"
    # cấp 9 không Excellent: không dùng icon _e, lùi về bucket 0
    assert r.map["0/1"]["9"] == "items/item_0_1_0.png"

    assert r.map["7/5"] ==
             Map.new(
               for(
                 b <- [0, 3, 5, 7, 9, 11, 13, 15],
                 e <- ["", "e"],
                 do: {"#{b}#{e}", "items/item_7_5.png"}
               )
             )

    # chỉ có bucket 3: cấp 0 vẫn thiếu
    assert r.map["14/1"]["0"] == "placeholder.png"
    assert r.map["14/1"]["3"] == "items/item_14_1_3.png"
    assert r.map["custom/ring_hp_t0"] == %{"0" => "custom/ring_hp_t0.png"}
    assert r.map["8/5"] == %{"0" => "placeholder.png"}
    assert r.map["_placeholder"] == "placeholder.png"

    assert "hp_potion_small" in r.missing and "armor_t0" in r.missing
    refute "sword_t0" in r.missing or "helm_t0" in r.missing or "ring_hp_t0" in r.missing
    assert r.unparsed == ["junk.png"]
    assert r.ancient_skipped == ["item_8_5_0_a.png"]
    assert r.used == ~w(item_0_1_0.png item_0_1_9_e.png item_14_1_3.png item_7_5.png)
  end

  @tag :tmp_dir
  test "mix mu.icons.index: chép đúng file dùng, ghi map + báo cáo; input rỗng vẫn exit 0", %{
    tmp_dir: dir
  } do
    input = Path.join(dir, "in")
    out = Path.join(dir, "out")
    report = Path.join(dir, "ICON_REPORT.md")
    File.mkdir_p!(input)

    for f <- ~w(item_0_1_0.png item_6_0.png item_99_9.png note.png),
        do: File.write!(Path.join(input, f), @png)

    log =
      capture_io(fn ->
        Mix.Tasks.Mu.Icons.Index.run(["--input", input, "--out", out, "--report", report])
      end)

    assert log =~ "CẢNH BÁO: armor_t0 chưa có icon"

    assert File.ls!(Path.join(out, "icons/items")) |> Enum.sort() == [
             "item_0_1_0.png",
             "item_6_0.png"
           ]

    map = Path.join(out, "icon_map.json") |> File.read!() |> Jason.decode!()
    assert map["6/0"]["0"] == "items/item_6_0.png"
    md = File.read!(report)
    assert md =~ "**4** file"
    assert md =~ "| 32×32 | 4 |"
    assert md =~ "note.png"

    # input không tồn tại: toàn bộ placeholder, không lỗi
    log =
      capture_io(fn ->
        Mix.Tasks.Mu.Icons.Index.run([
          "--input",
          Path.join(dir, "khong_co"),
          "--out",
          out,
          "--report",
          report
        ])
      end)

    assert log =~ "mọi item dùng placeholder"
    map = Path.join(out, "icon_map.json") |> File.read!() |> Jason.decode!()
    assert map["0/1"] == %{"0" => "placeholder.png"}
    assert File.ls!(Path.join(out, "icons/items")) == []
  end

  test "placeholder.png của dự án là PNG 32×32" do
    assert IconIndex.png_size(@png) == {32, 32}
  end
end

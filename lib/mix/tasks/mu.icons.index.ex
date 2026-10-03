defmodule Mix.Tasks.Mu.Icons.Index do
  @shortdoc "Quét icon item (private), chép sang priv/static, sinh icon_map.json + ICON_REPORT"
  @moduledoc """
      mix mu.icons.index
      mix mu.icons.index --input DIR --out DIR --report PATH

  - Input: `--input`, hoặc `ITEM_ICONS_DIR`, mặc định `assets_src/private/item_icons/`
    (asset MU-derived, **không bao giờ vào git/Docker**: `KB_ASSETS §2.2`).
  - Output (mặc định `priv/static/assets`): `icons/items/*.png` (chỉ file được dùng) và
    `icon_map.json` — cả hai gitignore.
  - Báo cáo: `docs/ICON_REPORT.md` (không chứa ảnh).
  - Input rỗng/không có: mọi item trỏ placeholder, in cảnh báo, **exit 0**.
  Quy tắc chọn icon: `Mu.Assets.IconIndex`.
  """
  use Mix.Task

  alias Mu.Assets.IconIndex
  alias Mu.Game.Data

  @impl true
  def run(args) do
    {o, _, _} = OptionParser.parse(args, strict: [input: :string, out: :string, report: :string])
    root = File.cwd!()

    input =
      o[:input] || System.get_env("ITEM_ICONS_DIR") ||
        Path.join(root, "assets_src/private/item_icons")

    out = o[:out] || Path.join(root, "priv/static/assets")
    report = o[:report] || Path.join(root, "docs/ICON_REPORT.md")
    custom_dir = Path.join(root, "priv/static/assets/icons/custom")

    files =
      if File.dir?(input),
        do: input |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".png")) |> Enum.sort(),
        else: []

    if files == [] do
      Mix.shell().info("CẢNH BÁO: không có icon trong #{input} — mọi item dùng placeholder")
    end

    custom = if File.dir?(custom_dir), do: File.ls!(custom_dir), else: []
    r = IconIndex.build(files, Data.items(), custom)

    items_out = Path.join(out, "icons/items")
    File.rm_rf!(items_out)
    File.mkdir_p!(items_out)
    for f <- r.used, do: File.cp!(Path.join(input, f), Path.join(items_out, f))

    File.write!(Path.join(out, "icon_map.json"), Jason.encode!(r.map, pretty: true) <> "\n")

    sizes =
      files
      |> Enum.map(&IconIndex.png_size(File.read!(Path.join(input, &1))))
      |> Enum.frequencies()

    File.mkdir_p!(Path.dirname(report))
    File.write!(report, report_md(input, files, r, sizes))

    for id <- r.missing, do: Mix.shell().info("CẢNH BÁO: #{id} chưa có icon → placeholder")

    Mix.shell().info(
      "icon_map.json: #{length(r.used)} file dùng, #{length(r.missing)} item placeholder"
    )
  end

  defp report_md(input, files, r, sizes) do
    size_rows =
      for {size, n} <- Enum.sort_by(sizes, fn {_, n} -> -n end) do
        label =
          if size,
            do: "#{elem(size, 0)}×#{elem(size, 1)}",
            else: "không đọc được (không phải PNG)"

        "| #{label} | #{n} |"
      end

    """
    # ICON_REPORT — kết quả `mix mu.icons.index`

    > File sinh tự động, không sửa tay. Không chứa ảnh. Quy tắc: `KB_ITEM_REFERENCE §4`, `KB_ASSETS §2.2`.

    - Input: `#{Path.relative_to_cwd(input)}` — **#{length(files)}** file `.png`
    - File được dùng (chép sang `priv/static/assets/icons/items/`): **#{length(r.used)}**
    - Item Phase 1 dùng placeholder: **#{length(r.missing)}** #{if r.missing == [], do: "", else: "(" <> Enum.join(r.missing, ", ") <> ")"}
    - Tên file không parse được: #{length(r.unparsed)}#{if r.unparsed == [], do: "", else: " — " <> Enum.join(r.unparsed, ", ")}
    - Biến thể Ancient bị bỏ (`items.ancientVariants = false`): #{length(r.ancient_skipped)}

    ## Kích thước pixel (trả lời A6)

    | Kích thước | Số file |
    |---|---|
    #{if size_rows == [], do: "| (không có file) | 0 |", else: Enum.join(size_rows, "\n")}
    """
  end
end

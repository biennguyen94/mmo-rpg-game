defmodule Mix.Tasks.HacLong.Icons do
  @shortdoc "Quét bộ hình đồ (đổi theo cấp +N), chép vào priv/static và sinh bảng tra"
  @moduledoc """
  Quét thư mục hình đồ của anh, chép sang `priv/static/assets/mu_items/` và ghi bảng tra
  `priv/static/assets/item_icons.json` (xem `HacLong.Game.ItemIcons` cho cách đặt tên file):

      mix hac_long.icons                      # thư mục mặc định assets_src/private/item_icons
      mix hac_long.icons --src ~/hinh-do      # hoặc HL_ITEM_ICONS_DIR=~/hinh-do
      mix hac_long.icons --no-trim            # chép nguyên, không cắt viền trong suốt

  Máy có ImageMagick (`convert`) thì cắt bỏ viền trong suốt quanh món đồ khi chép (hình gốc MU để
  món đồ nhỏ giữa khung lớn, đặt vào ô túi đồ trông rất bé); không có thì chép nguyên.

  Không có thư mục / không có hình: ghi bảng rỗng, game dùng icon cũ, **không lỗi** (thoát 0).
  Tải lại trang là thấy hình mới (không cần build lại server).

  Hình gốc MU (CLAUDE.md §7): thư mục nguồn, `priv/static/assets/mu_items/` và bảng tra đều bị git / Docker
  bỏ qua; máy chủ thật chạy lại lệnh này sau khi đặt hình.
  """
  use Mix.Task

  alias HacLong.Game.{Data, ItemIcons}

  @out_dir "priv/static/assets/mu_items"
  @out_map "priv/static/assets/item_icons.json"

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [src: :string, trim: :boolean])
    convert = opts[:trim] != false && System.find_executable("convert")
    src = opts[:src] || System.get_env("HL_ITEM_ICONS_DIR") || "assets_src/private/item_icons"
    Mix.Task.run("compile")

    files =
      case File.ls(src) do
        {:ok, fs} -> Enum.filter(fs, &(Path.extname(&1) in ~w(.png .webp)))
        _ -> []
      end

    if files == [], do: Mix.shell().info("Không có hình trong #{src}: dùng icon có sẵn của game.")

    {map, skipped} = ItemIcons.build(files, "mu_items")
    File.mkdir_p!(@out_dir)

    for f <- files,
        Path.basename(f) not in skipped,
        do: copy(convert, Path.join(src, f), Path.join(@out_dir, f))

    File.write!(@out_map, Jason.encode!(map, pretty: true) <> "\n")

    Mix.shell().info(
      "Đã ghi #{@out_map}: #{map_size(map)} món, #{length(files) - length(skipped)} hình."
    )

    if skipped != [],
      do: Mix.shell().info("Bỏ qua (tên không đúng mẫu): #{Enum.join(skipped, ", ")}")

    missing =
      for {id, it} <- Data.items(),
          it.slot in ~w(weapon armor shield wing helm pants gloves boots),
          not Map.has_key?(map, it[:ref] || "") and not Map.has_key?(map, "custom/#{id}"),
          !it[:legacy],
          do: id

    if missing != [],
      do:
        Mix.shell().info(
          "Chưa có hình riêng (dùng icon cũ): #{Enum.join(Enum.sort(missing), ", ")}"
        )
  end

  defp copy(nil, from, to), do: File.cp!(from, to)

  defp copy(convert, from, to) do
    case System.cmd(convert, [from, "-trim", "+repage", to], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> File.cp!(from, to)
    end
  end
end

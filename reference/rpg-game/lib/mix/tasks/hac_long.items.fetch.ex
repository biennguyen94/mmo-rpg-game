defmodule Mix.Tasks.HacLong.Items.Fetch do
  @shortdoc "Tải Item.txt và chép hình đồ vào assets_src/private/ — không vào git"
  @moduledoc """
  Lấy dữ liệu đồ gốc MU về máy (anh chốt nguồn 2026-10-10, `docs/ITEMS_PHASE15B.md`):

      mix hac_long.items.fetch                       # Item.txt từ nguồn mặc định
      mix hac_long.items.fetch --url https://…/Item.txt
      HL_ITEM_TXT_URL=https://…/Item.txt mix hac_long.items.fetch

      # hình: chép từ bản clone repo hình của anh (biennguyen94/mmo-rpg-game-items, thư mục item_ref)
      mix hac_long.items.fetch --icons-from ../../../mmo-rpg-game-items/item_ref/items
      HL_ITEM_ICONS_SRC=… mix hac_long.items.fetch

  Ghi `assets_src/private/items/Item.txt` và `assets_src/private/item_icons/`. Thư mục `assets_src/private/`
  bị git và Docker bỏ qua (CLAUDE.md §7): mỗi máy (máy dev, máy chủ) tự chạy lệnh này, rồi
  `mix hac_long.items.import` (Item.txt) và `mix hac_long.icons` (hình).

  Hình: chỉ chép hình của đồ đang có trong game (`ref` trong `ITEMS`, mọi mức `_N`, cả biến thể `_e` cho đồ
  Excellent; bỏ `_a`), không chép cả bộ 8 000 hình.

  Tải dùng `curl` có sẵn trên máy (theo `HTTPS_PROXY` nếu có). Lỗi mạng thì báo và thoát 0, không làm hỏng build.
  """
  use Mix.Task

  @default_url "https://raw.githubusercontent.com/afrokick/muonlinejs/master/tools/Item.txt"
  @out "assets_src/private/items/Item.txt"
  @icons "assets_src/private/item_icons"

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [url: :string, icons_from: :string])

    case opts[:icons_from] || System.get_env("HL_ITEM_ICONS_SRC") do
      nil -> item_txt(opts[:url] || System.get_env("HL_ITEM_TXT_URL") || @default_url)
      src -> icons(src)
    end
  end

  defp item_txt(url) do
    File.mkdir_p!(Path.dirname(@out))
    tmp = @out <> ".part"

    case curl(url, tmp) do
      :ok ->
        File.rename!(tmp, @out)
        Mix.shell().info("Đã tải #{url} → #{@out} (#{File.stat!(@out).size} byte).")
        Mix.shell().info("Tiếp theo: mix hac_long.items.import")

      {:error, why} ->
        File.rm(tmp)
        Mix.shell().info("Không tải được #{url}: #{why}. Giữ nguyên #{@out} (nếu có).")
    end
  end

  defp icons(src) do
    Mix.Task.run("compile")

    refs =
      for {_, it} <- HacLong.Game.Data.items(), ref = it[:ref], into: MapSet.new() do
        "item_" <> String.replace(ref, "/", "_") <> "_"
      end

    case File.ls(src) do
      {:ok, files} ->
        File.mkdir_p!(@icons)

        picked =
          for f <- files,
              Path.extname(f) in ~w(.png .webp),
              not String.ends_with?(Path.rootname(f), "_a"),
              Enum.any?(refs, &String.starts_with?(f, &1)) do
            File.cp!(Path.join(src, f), Path.join(@icons, f))
          end

        Mix.shell().info(
          "Đã chép #{length(picked)} hình (#{MapSet.size(refs)} món) từ #{src} → #{@icons}."
        )

        Mix.shell().info("Tiếp theo: mix hac_long.icons")

      {:error, why} ->
        Mix.shell().info("Không đọc được #{src}: #{why}.")
    end
  end

  defp curl(url, path) do
    case System.find_executable("curl") do
      nil ->
        {:error, "máy không có curl"}

      exe ->
        case System.cmd(exe, ["-fsSL", "--max-time", "60", "-o", path, url],
               stderr_to_stdout: true
             ) do
          {_, 0} -> :ok
          {out, code} -> {:error, "curl thoát #{code} #{String.trim(out)}"}
        end
    end
  end
end

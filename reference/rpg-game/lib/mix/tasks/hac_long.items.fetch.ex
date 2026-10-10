defmodule Mix.Tasks.HacLong.Items.Fetch do
  @shortdoc "Tải Item.txt (và hình đồ nếu có danh sách) vào assets_src/private/ — không vào git"
  @moduledoc """
  Tải dữ liệu đồ gốc MU về máy (anh chốt nguồn 2026-10-10, `docs/ITEMS_PHASE15B.md`):

      mix hac_long.items.fetch                       # Item.txt từ nguồn mặc định
      mix hac_long.items.fetch --url https://…/Item.txt
      HL_ITEM_TXT_URL=https://…/Item.txt mix hac_long.items.fetch

  Ghi `assets_src/private/items/Item.txt`. Thư mục `assets_src/private/` bị git và Docker bỏ qua
  (CLAUDE.md §7): mỗi máy (máy dev, máy chủ) tự chạy lệnh này rồi `mix hac_long.items.import`.

  Hình đồ: chép tay vào `assets_src/private/item_icons/` rồi chạy `mix hac_long.icons`.

  Dùng `curl` có sẵn trên máy (theo `HTTPS_PROXY` nếu có). Lỗi mạng thì báo và thoát 0, không làm hỏng build.
  """
  use Mix.Task

  @default_url "https://raw.githubusercontent.com/afrokick/muonlinejs/master/tools/Item.txt"
  @out "assets_src/private/items/Item.txt"

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [url: :string])
    url = opts[:url] || System.get_env("HL_ITEM_TXT_URL") || @default_url
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

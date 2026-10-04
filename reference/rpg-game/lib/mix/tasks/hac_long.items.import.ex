defmodule Mix.Tasks.HacLong.Items.Import do
  @shortdoc "Đọc Item.txt → priv/items_raw.json + priv/items_from_txt.json (nháp đồ Hắc Long)"
  @moduledoc """
  Đọc `Item.txt` của anh (`HacLong.Game.ItemTxt`):

      mix hac_long.items.import                         # mặc định assets_src/items/Item.txt
      mix hac_long.items.import đường/dẫn/Item.txt

  Ghi:

  - `priv/items_raw.json`: mọi dòng đọc được, giữ nguyên số trong file;
  - `priv/items_from_txt.json`: nháp đồ Hắc Long (vũ khí, khiên, giáp, mũ, quần, găng, giày, cánh)
    với `ref`, `classes`, `req` gốc. **Chưa thay đồ trong game**: bước ghép vào `priv/game_data/items.json`
    (chọn món cho từng vùng / cửa hàng, giá, hệ số yêu cầu chỉ số) xem `docs/INTEGRATION_PLAN.md §10`.

  Không có file thì báo và thoát 0.
  """
  use Mix.Task

  alias HacLong.Game.ItemTxt

  @impl true
  def run(args) do
    path = List.first(args) || "assets_src/items/Item.txt"

    case File.read(path) do
      {:ok, bin} ->
        text = if String.valid?(bin), do: bin, else: :unicode.characters_to_binary(bin, :latin1)
        {items, warns} = ItemTxt.parse(text)
        drafts = items |> Enum.map(&ItemTxt.to_item/1) |> Enum.reject(&is_nil/1)
        write("priv/items_raw.json", %{source: Path.basename(path), items: items})
        write("priv/items_from_txt.json", %{source: Path.basename(path), items: drafts})

        by_group = items |> Enum.frequencies_by(& &1.group) |> Enum.sort()
        Mix.shell().info("Đọc #{length(items)} món (#{length(drafts)} đồ mặc được) từ #{path}.")

        for {g, n} <- by_group,
            do: Mix.shell().info("  nhóm #{g} #{ItemTxt.groups()[g]}: #{n}")

        for {n, why, name} <- Enum.take(warns, 30),
            do: Mix.shell().info("  ⚠ dòng #{n}: #{why} (#{inspect(name)})")

        if length(warns) > 30, do: Mix.shell().info("  … và #{length(warns) - 30} cảnh báo khác")

      {:error, _} ->
        Mix.shell().info("Không thấy #{path}. Đặt Item.txt vào assets_src/items/ rồi chạy lại.")
    end
  end

  defp write(path, data), do: File.write!(path, Jason.encode!(data, pretty: true) <> "\n")
end

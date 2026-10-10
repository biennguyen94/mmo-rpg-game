defmodule Mix.Tasks.HacLong.Items.Build do
  @shortdoc "Dựng đồ Hắc Long từ Item.txt theo item_pick.json (--preview: chỉ ghi bảng xem trước)"
  @moduledoc """
  Phase 15b (`docs/ITEMS_PHASE15B.md`):

      mix hac_long.items.fetch            # tải Item.txt (một lần mỗi máy)
      mix hac_long.items.import           # Item.txt → assets_src/private/items/items_from_txt.json
      mix hac_long.items.build --preview  # ghi docs/ITEMS_PICK.md để duyệt, không đổi game

  Đọc bảng chọn và các hệ số ở `priv/game_data/item_pick.json` (`HacLong.Game.ItemBuild`).
  Thiếu nháp Item.txt thì báo và thoát 0.
  """
  use Mix.Task

  alias HacLong.Game.ItemBuild

  @drafts "assets_src/private/items/items_from_txt.json"
  @pick "priv/game_data/item_pick.json"
  @preview "docs/ITEMS_PICK.md"

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [preview: :boolean])

    with {:ok, bin} <- File.read(@drafts),
         %{"items" => list} <- Jason.decode!(bin) do
      drafts = Map.new(list, &{&1["ref"], &1})
      pick = @pick |> File.read!() |> Jason.decode!() |> Map.fetch!("ITEM_PICK")
      {:ok, items, warns} = ItemBuild.build(drafts, pick)

      for w <- warns, do: Mix.shell().info("Cảnh báo: #{w}")

      if opts[:preview] do
        File.write!(@preview, table(items, pick))
        Mix.shell().info("Đã ghi #{@preview}: #{length(items)} món.")
      else
        Mix.shell().info(
          "#{length(items)} món. Ghép vào items.json làm ở M2; giờ dùng --preview."
        )
      end
    else
      _ -> Mix.shell().info("Chưa có #{@drafts}: chạy mix hac_long.items.import trước.")
    end
  end

  @slot_vi [
    {"weapon", "Vũ khí"},
    {"shield", "Khiên"},
    {"helm", "Mũ"},
    {"armor", "Giáp"},
    {"pants", "Quần"},
    {"gloves", "Găng"},
    {"boots", "Giày"}
  ]

  defp table(items, pick) do
    count = items |> Enum.frequencies_by(& &1["slot"])

    head = """
    # Bảng chọn đồ Phase 15b (xem trước, sinh tự động)

    > Sinh bằng `mix hac_long.items.build --preview` từ `priv/game_data/item_pick.json`
    > (req_mult #{pick["req_mult"]}, set_def_mult #{get_in(pick, ["stats", "set_def_mult"])}).
    > **Đừng sửa tay file này**: sửa `item_pick.json` rồi chạy lại. Giải thích: `docs/ITEMS_PHASE15B.md`.

    Tổng #{length(items)} món: #{Enum.map_join(@slot_vi, ", ", fn {k, v} -> "#{v} #{count[k] || 0}" end)}.

    """

    sections =
      for {slot, vi} <- @slot_vi, rows = Enum.filter(items, &(&1["slot"] == slot)), rows != [] do
        stat = if slot == "weapon", do: "Công (thấp~cao)", else: "Thủ"

        lines =
          for it <- rows do
            power =
              if slot == "weapon",
                do: "#{it["atk"]} (#{it["atkMin"]}~#{it["atkMax"]})",
                else: "#{it["def"]}"

            req = it["req"] |> Enum.sort() |> Enum.map_join(" ", fn {k, v} -> "#{k} #{v}" end)
            req = if req == "", do: "—", else: req

            "| #{it["tier"]} | #{it["level"]} | #{it["name"]} | #{it["mu_name"]} | `#{it["ref"]}` | " <>
              "#{Enum.join(it["classes"], ", ")} | #{power} | #{req} | #{it["price"]} |"
          end

        """
        ## #{vi}

        | Bậc | Cấp | Tên | Tên gốc | Hình | Lớp | #{stat} | Yêu cầu | Giá |
        |---|---|---|---|---|---|---|---|---|
        #{Enum.join(lines, "\n")}
        """
      end

    head <> Enum.join(sections, "\n")
  end
end

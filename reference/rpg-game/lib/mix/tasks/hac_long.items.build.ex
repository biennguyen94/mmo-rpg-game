defmodule Mix.Tasks.HacLong.Items.Build do
  @shortdoc "Dựng đồ Hắc Long từ Item.txt theo item_pick.json (--preview: chỉ ghi bảng xem trước)"
  @moduledoc """
  Phase 15b (`docs/ITEMS_PHASE15B.md`):

      mix hac_long.items.fetch            # tải Item.txt (một lần mỗi máy)
      mix hac_long.items.import           # Item.txt → assets_src/private/items/items_from_txt.json
      mix hac_long.items.build --preview  # ghi docs/ITEMS_PICK.md để duyệt, không đổi game
      mix hac_long.items.build            # ghi priv/game_data/items_mu.json (đồ trong game) + docs/ITEMS_PICK.md

  Ghi thêm tên gốc (`mu_name`) làm bản tiếng Anh của tên đồ trong `priv/static/i18n/en.json`.

  `items_mu.json` (khóa `ITEMS_MU`) được `HacLong.Game.Data` gộp vào `ITEMS`; đồ cũ trong `ITEM_PICK.legacy`
  thôi bán / rơi và được đổi sang đồ mới khi nạp nhân vật. Xóa `items_mu.json` là game về đồ cũ.

  Đọc bảng chọn và các hệ số ở `priv/game_data/item_pick.json` (`HacLong.Game.ItemBuild`).
  Thiếu nháp Item.txt thì báo và thoát 0.
  """
  use Mix.Task

  alias HacLong.Game.ItemBuild

  @drafts "assets_src/private/items/items_from_txt.json"
  @pick "priv/game_data/item_pick.json"
  @preview "docs/ITEMS_PICK.md"
  @out "priv/game_data/items_mu.json"
  @items "priv/game_data/items.json"
  # thứ tự khóa trong items_mu.json (dễ đọc, diff ổn định)
  @keys ~w(name mu_name slot tier level classes atk atkMin atkMax def hp req price set ref icon doll
           sourceType version verified)

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [preview: :boolean])

    with {:ok, bin} <- File.read(@drafts),
         %{"items" => list} <- Jason.decode!(bin) do
      drafts = Map.new(list, &{&1["ref"], &1})
      pick = @pick |> File.read!() |> Jason.decode!() |> Map.fetch!("ITEM_PICK")
      legacy = @items |> File.read!() |> Jason.decode!() |> Map.fetch!("ITEMS")
      {:ok, items, warns} = ItemBuild.build(drafts, pick, legacy)

      for w <- warns, do: Mix.shell().info("Cảnh báo: #{w}")

      File.write!(@preview, table(items, pick))
      Mix.shell().info("Đã ghi #{@preview}: #{length(items)} món.")

      unless opts[:preview] do
        File.write!(@out, encode(items))
        Mix.shell().info("Đã ghi #{@out}. Chạy mix test rồi khởi động lại server.")
        english(items)
      end
    else
      _ -> Mix.shell().info("Chưa có #{@drafts}: chạy mix hac_long.items.import trước.")
    end
  end

  # bản tiếng Anh: tên gốc trong Item.txt (`mu_name`) làm bản dịch tên tiếng Việt
  @en "priv/static/i18n/en.json"
  defp english(items) do
    en = @en |> File.read!() |> Jason.decode!()
    names = Map.merge(en["names"], Map.new(items, &{&1["name"], &1["mu_name"]}))
    File.write!(@en, Jason.encode!(%{en | "names" => names}))
    Mix.shell().info("Đã ghi tên tiếng Anh của #{length(items)} món vào #{@en}.")
  end

  # JSON giữ thứ tự món và thứ tự khóa (Jason.OrderedObject)
  defp encode(items) do
    objs =
      for it <- items do
        {it["id"], Jason.OrderedObject.new(for k <- @keys, Map.has_key?(it, k), do: {k, it[k]})}
      end

    Jason.encode!(%{"ITEMS_MU" => Jason.OrderedObject.new(objs)}, pretty: true) <> "\n"
  end

  @slot_vi [
    {"weapon", "Vũ khí"},
    {"shield", "Khiên"},
    {"helm", "Mũ"},
    {"armor", "Giáp"},
    {"pants", "Quần"},
    {"gloves", "Găng"},
    {"boots", "Giày"},
    {"ring", "Nhẫn"},
    {"pendant", "Dây chuyền"}
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
        stat = if slot == "weapon", do: "Công (thấp~cao)", else: "Chỉ số"

        lines =
          for it <- rows do
            power =
              cond do
                slot == "weapon" -> "#{it["atk"]} (#{it["atkMin"]}~#{it["atkMax"]})"
                it["def"] -> "#{it["def"]} thủ"
                it["hp"] -> "+#{it["hp"]} máu"
                it["atk"] -> "+#{it["atk"]} công"
                true -> ""
              end

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

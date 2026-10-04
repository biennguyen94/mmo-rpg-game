defmodule HacLong.Game.ItemTxt do
  @moduledoc """
  Đọc `Item.txt` (dữ liệu đồ của anh, định dạng mô tả ở `docs/kb/KB_ITEM_REFERENCE.md §1` của repo
  ngoài) thành danh sách bản ghi, và đổi sang dạng đồ của Hắc Long (`to_item/1`). Hàm thuần.

  Định dạng:

  - Mỗi nhóm: dòng chỉ có số nhóm, các dòng đồ, `end`. Dòng `//…` là chú thích.
  - Dòng đồ: `Index ItemSlot Skill X Y Serial Option Drop "Tên" giá_trị…`. Giữa các cột có thể là
    tab hoặc dấu cách, số tab đệm không cố định → tách theo khoảng trắng, không theo vị trí cột.
  - Cột sau tên theo nhóm (`@layout`); nhóm 0–11 có thêm 6 cờ lớp `DW DK ELF MG DL SUM`
    (0 = không dùng, 1 = lớp gốc trở lên, 2 / 3 = chỉ bậc tiến hóa).
  """

  @groups %{
    0 => "Sword",
    1 => "Axe",
    2 => "Scepter",
    3 => "Spear",
    4 => "Bow/Crossbow",
    5 => "Staff",
    6 => "Shield",
    7 => "Helm",
    8 => "Armor",
    9 => "Pants",
    10 => "Gloves",
    11 => "Boots",
    12 => "Wing/Orb/Seed",
    13 => "Pet/Ring/Pendant",
    14 => "Potion/Jewel/Quest",
    15 => "Scroll"
  }

  @weapon ~w(itemLvl dmgMin dmgMax speed durability magicDur magicPwr reqLvl str agi ene vit command type)
  @defense ~w(itemLvl def defRate durability reqLvl str agi ene vit command type)
  @layout Map.merge(
            Map.new(0..5, &{&1, @weapon}),
            Map.new(6..11, &{&1, @defense})
          )
          |> Map.merge(%{
            12 => ~w(itemLvl def durability reqLvl ene str agi command zen),
            13 => ~w(itemLvl durability ice poison light fire earth wind water type),
            14 => ~w(valor itemLvl),
            15 => ~w(itemLvl reqLvl ene zen)
          })
  @class_cols ~w(DW DK ELF MG DL SUM)
  # cờ lớp MU → lớp Hắc Long (DL, SUM không có trong game)
  @classes %{"DW" => "dw", "DK" => "dk", "ELF" => "elf", "MG" => "mg"}

  def groups, do: @groups

  @doc """
  Đọc nội dung file. Trả về `{bản_ghi, cảnh_báo}`; mỗi bản ghi:
  `%{group, index, name, slotMU, x, y, values: %{cột => số}, classTier: %{"DW" => n, …} | nil, line}`.
  """
  def parse(text) when is_binary(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.with_index(1)
    |> Enum.reduce({[], [], nil}, fn {line, n}, {items, warns, group} ->
      s = String.trim(line)

      cond do
        s == "" or String.starts_with?(s, "//") ->
          {items, warns, group}

        s == "end" ->
          {items, warns, nil}

        group == nil and s =~ ~r/^\d+$/ ->
          {items, warns, String.to_integer(s)}

        group == nil ->
          {items, warns, group}

        true ->
          case parse_line(line, group, n) do
            {:ok, rec} -> {[rec | items], warns, group}
            {:warn, w} -> {items, [w | warns], group}
          end
      end
    end)
    |> then(fn {items, warns, _} -> {Enum.reverse(items), Enum.reverse(warns)} end)
  end

  defp parse_line(line, group, n) do
    with [_, head, name, tail] <- Regex.run(~r/^([^"]*)"([^"]*)"(.*)$/, line),
         head = String.split(head),
         true <- length(head) >= 8 || {:warn, {n, "thiếu cột trước tên", name}},
         {:ok, head} <- ints(head, n, name),
         tail = tail |> String.split("//") |> hd() |> String.split(),
         {:ok, vals} <- ints(tail, n, name) do
      cols = Map.get(@layout, group, [])
      flags? = group in 0..11

      if length(vals) < length(cols) + if(flags?, do: 6, else: 0) do
        {:warn, {n, "thiếu cột sau tên (#{length(vals)})", name}}
      else
        values = cols |> Enum.zip(vals) |> Map.new()

        tiers =
          if flags?,
            do: @class_cols |> Enum.zip(Enum.slice(vals, length(cols), 6)) |> Map.new()

        [index, slot, _skill, x, y | _] = head

        {:ok,
         %{
           group: group,
           index: index,
           name: name,
           slotMU: slot,
           x: x,
           y: y,
           values: values,
           classTier: tiers,
           line: n
         }}
      end
    else
      nil -> {:warn, {n, "không có tên trong dấu \"\"", String.slice(String.trim(line), 0, 60)}}
      {:warn, _} = w -> w
    end
  end

  defp ints(list, n, name) do
    Enum.reduce_while(list, {:ok, []}, fn v, {:ok, acc} ->
      case Integer.parse(v) do
        {i, ""} -> {:cont, {:ok, [i | acc]}}
        _ -> {:halt, {:warn, {n, "giá trị không phải số: #{v}", name}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      w -> w
    end
  end

  @doc """
  Đổi một bản ghi sang dạng đồ Hắc Long (nháp, chưa dùng trong game). `nil` nếu nhóm không phải đồ
  mặc được (bình, ngọc, nhiệm vụ, sách: nhóm 13–15 làm tay).

  - `id` = `item_{group}_{index}`, `ref` = `"group/index"` (khóa tra icon).
  - Vũ khí: `atkMin` / `atkMax` (đòn thấp / cao, như MU), `atk` = trung bình (công thức hiện tại
    của Hắc Long dùng một số). Giáp / khiên / cánh: `def`.
  - `level`: cấp yêu cầu (`reqLvl` nếu có, không thì `itemLvl`).
  - `req`: yêu cầu STR / AGI / VIT / ENE **gốc** trong file (chưa nhân hệ số; xem `INTEGRATION_PLAN §10`).
  - `classes`: các lớp mặc được: cờ **== 1** (lớp gốc; cờ 2, 3 là bậc tiến hóa mà Hắc Long không có,
    như quy tắc `KB_ITEM_REFERENCE §3.1`).
  """
  def to_item(%{group: g} = r) when g in 0..12 do
    v = r.values
    slot = slot(g)

    base = %{
      id: "item_#{g}_#{r.index}",
      ref: "#{g}/#{r.index}",
      name: r.name,
      slot: slot,
      level: if((v["reqLvl"] || 0) > 0, do: v["reqLvl"], else: v["itemLvl"] || 1),
      itemLvl: v["itemLvl"],
      req: v |> Map.take(~w(str agi vit ene)) |> Map.filter(fn {_, n} -> n > 0 end),
      cells: [r.x, r.y],
      classes: classes(r.classTier)
    }

    stats =
      if g in 0..5,
        do: %{
          atkMin: v["dmgMin"],
          atkMax: v["dmgMax"],
          atk: round((v["dmgMin"] + v["dmgMax"]) / 2),
          speed: v["speed"],
          magic: v["magicPwr"]
        },
        else: %{def: v["def"] || 0}

    Map.merge(base, stats)
  end

  def to_item(_r), do: nil

  defp slot(g) when g in 0..5, do: "weapon"
  defp slot(6), do: "shield"
  defp slot(7), do: "helm"
  defp slot(8), do: "armor"
  defp slot(9), do: "pants"
  defp slot(10), do: "gloves"
  defp slot(11), do: "boots"
  defp slot(12), do: "wing"

  defp classes(nil), do: nil

  defp classes(tiers) do
    for {mu, hl} <- @classes, tiers[mu] == 1, do: hl
  end
end

defmodule Mu.Assets.IconIndex do
  @moduledoc """
  Dựng `icon_map.json` từ bộ icon item (`KB_ITEM_REFERENCE §4`, `KB_ASSETS §2.2`). Hàm thuần;
  `mix mu.icons.index` lo đọc/chép file.

  - Tên file input: `item_{group}_{index}[_{bucket}][_e][_a].png`. `_a` (Ancient) bỏ qua khi
    `items.ancientVariants = false`. Tên khác → "không parse được".
  - Với mỗi template có `iconRef {group, index}`, mỗi bucket `items.iconBuckets` và có/không
    Excellent, chọn file theo thứ tự §4.3; khóa map: `"{bucket}"` hoặc `"{bucket}e"`.
  - Template `iconRef {custom}` → `custom/{templateId}.png` nếu dự án có file đó.
  - Không có file cho bucket 0 → `"0": "placeholder.png"` (client hiện placeholder) và template
    nằm trong `missing` (Phase 1 mọi item là +0).
  - Giá trị là đường dẫn tương đối so với `priv/static/assets/icons/`.
  """

  alias Mu.Game.Config

  @placeholder "placeholder.png"

  @doc "`{:ok, %{group, index, bucket, excellent, ancient}}` hoặc `:error`."
  def parse_name(name) do
    case Regex.run(~r/^item_(\d+)_(\d+)(?:_(\d+))?(_e)?(_a)?\.png$/, name) do
      [_ | caps] ->
        [g, i | rest] = caps ++ List.duplicate("", 5 - length(caps))
        [b, e, a] = Enum.take(rest, 3)

        {:ok,
         %{
           group: String.to_integer(g),
           index: String.to_integer(i),
           bucket: if(b == "", do: nil, else: String.to_integer(b)),
           excellent: e == "_e",
           ancient: a == "_a"
         }}

      nil ->
        :error
    end
  end

  @doc "`bucket(level)` (§4.2): bucket lớn nhất ≤ min(level, 15)."
  def bucket(level) do
    buckets = Config.get(["items", "iconBuckets"])
    l = min(level, Enum.max(buckets))
    buckets |> Enum.filter(&(&1 <= l)) |> Enum.max()
  end

  @doc """
  Thứ tự tên file thử cho `(group, index, level, excellent)` (§4.3, bước 1–5). Ở các bucket
  thấp hơn chỉ thử `_e` khi item là Excellent (đọc §4.3 theo `{ex}` như bước 1, 4; DEC-38).
  """
  def candidates(g, i, level, excellent) do
    b = bucket(level)
    ex = if excellent, do: "_e", else: ""
    lower = Config.get(["items", "iconBuckets"]) |> Enum.filter(&(&1 < b)) |> Enum.sort(:desc)

    ["item_#{g}_#{i}_#{b}#{ex}.png", "item_#{g}_#{i}_#{b}.png"] ++
      Enum.flat_map(
        lower,
        &Enum.uniq(["item_#{g}_#{i}_#{&1}#{ex}.png", "item_#{g}_#{i}_#{&1}.png"])
      ) ++
      ["item_#{g}_#{i}#{ex}.png", "item_#{g}_#{i}.png"]
  end

  @doc """
  `files`: tên file input; `templates`: map templateId → template; `custom`: tên file trong
  `icons/custom/`. Trả `%{map, used, missing, unparsed, ancient_skipped}`.
  """
  def build(files, templates, custom \\ []) do
    ancient? = Config.get(["items", "ancientVariants"])
    {parsed, unparsed} = Enum.split_with(files, &(parse_name(&1) != :error))

    {usable, ancient_skipped} =
      Enum.split_with(parsed, fn f -> ancient? or not elem(parse_name(f), 1).ancient end)

    available = MapSet.new(usable)
    custom = MapSet.new(custom)

    {map, used, missing} =
      templates
      |> Enum.sort_by(fn {id, _} -> id end)
      |> Enum.reduce({%{}, MapSet.new(), []}, fn {id, t}, {map, used, missing} ->
        case t["iconRef"] do
          %{"custom" => c} ->
            file = c <> ".png"

            if MapSet.member?(custom, file),
              do: {Map.put(map, "custom/" <> c, %{"0" => "custom/" <> file}), used, missing},
              else: {Map.put(map, "custom/" <> c, %{"0" => @placeholder}), used, [id | missing]}

          %{"group" => g, "index" => i} ->
            entry =
              for b <- Config.get(["items", "iconBuckets"]),
                  ex <- [false, true],
                  file = Enum.find(candidates(g, i, b, ex), &MapSet.member?(available, &1)),
                  into: %{},
                  do: {"#{b}#{if ex, do: "e"}", "items/" <> file}

            used = Enum.reduce(Map.values(entry), used, &MapSet.put(&2, Path.basename(&1)))

            # Phase 1 mọi item +0: thiếu icon bucket 0 thì coi như thiếu, trỏ placeholder
            if Map.has_key?(entry, "0"),
              do: {Map.put(map, "#{g}/#{i}", entry), used, missing},
              else:
                {Map.put(map, "#{g}/#{i}", Map.put(entry, "0", @placeholder)), used,
                 [id | missing]}
        end
      end)

    %{
      map: Map.put(map, "_placeholder", @placeholder),
      used: MapSet.to_list(used) |> Enum.sort(),
      missing: Enum.sort(missing),
      unparsed: Enum.sort(unparsed),
      ancient_skipped: Enum.sort(ancient_skipped)
    }
  end

  @doc "Kích thước `{w, h}` đọc từ header PNG, `nil` nếu không phải PNG."
  def png_size(<<137, "PNG", 13, 10, 26, 10, _len::32, "IHDR", w::32, h::32, _::binary>>),
    do: {w, h}

  def png_size(_), do: nil
end

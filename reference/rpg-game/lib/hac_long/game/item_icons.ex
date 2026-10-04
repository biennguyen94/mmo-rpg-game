defmodule HacLong.Game.ItemIcons do
  @moduledoc """
  Bộ hình đồ của anh, đổi theo cấp nâng +N. Hàm thuần (`mix hac_long.icons` quét thư mục và ghi file).

  Tên file (PNG / WebP):

  - `item_{group}_{index}.png` — hình mặc định của đồ có `ref: "group/index"` (đồ lấy từ `Item.txt`);
  - `item_{group}_{index}_{N}.png` — hình dùng từ cấp **+N** trở lên (vd `_0`, `_5`, `_10`);
  - `{id}.png`, `{id}_{N}.png` — cho đồ Hắc Long chưa có `ref` (vd `broadsword_7.png`);
  - đuôi `_e` / `_a` (biến thể Excellent / Ancient của bộ hình) được giữ trong bảng nhưng game chưa dùng.

  Bảng tra (`priv/static/assets/item_icons.json`):
  `%{"0/1" => %{"0" => "items/item_0_1_0.png", "5" => "items/item_0_1_5.png"}, "custom/broadsword" => …}`.
  Client chọn mức lớn nhất ≤ cấp nâng của món; không có hình thì dùng icon cũ.
  """

  @re ~r/^(?:item_(\d+)_(\d+)|([a-z][a-z0-9_]*?))(?:_(\d+))?(_[ea])?\.(png|webp)$/

  @doc """
  Từ danh sách tên file, trả về `{bảng_tra, bỏ_qua}`. `prefix` là thư mục con (trong
  `priv/static/assets/`) chứa hình sau khi chép.
  """
  def build(files, prefix \\ "items") do
    Enum.reduce(Enum.sort(files), {%{}, []}, fn f, {map, skipped} ->
      case Regex.run(@re, f, capture: :all_but_first) do
        [g, i, "", lv | rest] when g != "" ->
          {put(map, "#{g}/#{i}", lv, rest, "#{prefix}/#{f}"), skipped}

        ["", "", id, lv | rest] ->
          {put(map, "custom/#{id}", lv, rest, "#{prefix}/#{f}"), skipped}

        [g, i] ->
          {put(map, "#{g}/#{i}", "", [], "#{prefix}/#{f}"), skipped}

        ["", "", id] ->
          {put(map, "custom/#{id}", "", [], "#{prefix}/#{f}"), skipped}

        _ ->
          {map, [f | skipped]}
      end
    end)
    |> then(fn {map, skipped} -> {map, Enum.reverse(skipped)} end)
  end

  defp put(map, key, lv, rest, path) do
    level = if lv in ["", nil], do: "0", else: lv

    suffix =
      rest
      |> List.first()
      |> case do
        "_e" -> "e"
        "_a" -> "a"
        _ -> ""
      end

    k = level <> suffix
    # có số cấp trong tên (`_0`) thì ưu tiên hơn file không số
    add = if lv in ["", nil], do: &Map.put_new(&1, k, path), else: &Map.put(&1, k, path)
    Map.update(map, key, %{k => path}, add)
  end

  @doc "Đường dẫn hình cho món `key` ở cấp nâng `level` (mức lớn nhất ≤ cấp), nil nếu không có."
  def pick(map, key, level) do
    with %{} = m <- map[key] do
      m
      |> Enum.filter(fn {k, _} -> k =~ ~r/^\d+$/ and String.to_integer(k) <= level end)
      |> Enum.max_by(fn {k, _} -> String.to_integer(k) end, fn -> nil end)
      |> case do
        {_, path} -> path
        nil -> nil
      end
    end
  end
end

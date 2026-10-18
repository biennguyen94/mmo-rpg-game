defmodule HacLong.Game.Blessing do
  @moduledoc """
  Đài Phúc Lành (Phase 2, DECISIONS B-26): thay đá dịch chuyển cũ (ô `W` trên bản đồ, việc đi lại đã có bảng
  chọn bản đồ). Chạm vào đài:

  - nhận phúc lành của bản đồ đó trong `RULES.blessing.battles` trận (+`pct` kinh nghiệm / vàng / tấn công /
    phòng thủ / máu tối đa, loại theo bản đồ); chạm đài khác thì thay phúc lành cũ;
  - đài thành **điểm hồi sinh**: gục ngã ở bản đồ thường thì về đứng cạnh đài này thay vì về Nhà.

  Trạng thái trong nhân vật: `blessing: %{map, kind, left} | nil` (`left` 0 = hết phúc lành, vẫn là điểm hồi sinh).
  Hàm thuần.
  """
  alias HacLong.Game.Data
  alias HacLong.World.Maps

  @r Data.rules().blessing
  @kinds @r.kinds

  def rules, do: @r

  @doc "Loại phúc lành của bản đồ `map_id` (nil: Làng, hoặc bản đồ không có đài)."
  def kind(map_id) do
    case Enum.find_index(altars(), &(&1 == map_id)) do
      nil -> nil
      i -> Enum.at(@kinds, rem(i, length(@kinds)))
    end
  end

  # các bản đồ có đài, trừ Làng (Làng chỉ là điểm hồi sinh)
  defp altars, do: Maps.waystone_ids() |> Enum.reject(&(&1 == "village")) |> Enum.sort()

  @doc "Chạm đài ở bản đồ `map`: nhận phúc lành, ghi điểm hồi sinh. Trả về `{tin, nhân_vật}`."
  def touch(p, map) do
    case kind(map.id) do
      nil ->
        {"✨ Đài Phúc Lành ở #{map.name}: gục ngã sẽ hồi sinh ở đây.",
         Map.put(p, :blessing, %{map: map.id, kind: nil, left: 0})}

      k ->
        {"✨ Đài Phúc Lành ở #{map.name}: +#{round(@r.pct * 100)}% #{label(k)} trong #{@r.battles} trận. Gục ngã sẽ hồi sinh ở đây.",
         Map.put(p, :blessing, %{map: map.id, kind: k, left: @r.battles})}
    end
  end

  @doc "Tên loại phúc lành."
  def label("xp"), do: "kinh nghiệm"
  def label("gold"), do: "vàng"
  def label("atk"), do: "tấn công"
  def label("def"), do: "phòng thủ"
  def label("hp"), do: "máu tối đa"
  def label(_), do: ""

  @doc "Phần trăm cộng thêm cho `key` (:xp, :gold, :atk, :def, :hp) đang có."
  def bonus(p, key) do
    case Map.get(p, :blessing) do
      %{kind: k, left: left} when is_binary(k) and left > 0 ->
        if k == Atom.to_string(key), do: @r.pct, else: 0

      _ ->
        0
    end
  end

  @doc "Hết một trận: phúc lành bớt một trận (điểm hồi sinh giữ nguyên)."
  def tick(p) do
    case Map.get(p, :blessing) do
      %{left: left} = b when left > 0 -> Map.put(p, :blessing, %{b | left: left - 1})
      _ -> p
    end
  end

  @doc "Chỗ hồi sinh khi gục: cạnh đài đã chạm (nếu bản đồ còn đài), không thì nil (về Nhà)."
  def respawn(p) do
    with %{map: id} <- Map.get(p, :blessing),
         %{waystone: %{spawn: {x, y}}} <- Maps.get(id) do
      %{map: id, x: x, y: y}
    else
      _ -> nil
    end
  end

  @doc "Đọc từ database (khóa chuỗi)."
  def load(%{"map" => id} = b) when is_binary(id) do
    if Maps.get(id) do
      k = if b["kind"] in @kinds, do: b["kind"]
      %{map: id, kind: k, left: if(k && is_integer(b["left"]), do: max(b["left"], 0), else: 0)}
    end
  end

  def load(_), do: nil

  @doc "Cho client: `%{map, name, kind, label, pct, left}`."
  def view(p) do
    case Map.get(p, :blessing) do
      %{map: id, kind: k, left: left} ->
        %{
          map: id,
          name: (Maps.get(id) || %{name: id}).name,
          kind: k,
          label: label(k),
          pct: @r.pct,
          left: left
        }

      _ ->
        nil
    end
  end
end

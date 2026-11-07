defmodule HacLong.World.Weather do
  @moduledoc """
  Thời tiết chung cả server (DECISIONS "Bản đồ đẹp hơn", B5): đổi mỗi `RULES.weather.slot_min` phút theo giờ Việt Nam.
  Mỗi vùng (nền bản đồ; Làng và Hồ Long Vương riêng) bốc một loại theo trọng số `RULES.weather.regions`, từ mốc giờ và
  tên vùng, nên mọi bản đồ cùng vùng, mọi người chơi đều thấy như nhau mà không cần trạng thái. Chỉ là hình, không đổi
  luật chơi. Bản đồ tháp / sự kiện (`private`) không có thời tiết (client vẽ theo nền tầng).

  Ép một loại (để thử): `config :hac_long, :weather, "storm"` hoặc biến môi trường `WEATHER`.
  """
  alias HacLong.Game.Data

  @utc_offset 7 * 3600

  defp rules, do: Data.rules().weather

  @doc "Vùng thời tiết của bản đồ `map` (`HacLong.World.Maps`), nil nếu không có thời tiết."
  def region(%{private: true}), do: nil
  def region(%{id: "village"}), do: "village"
  def region(%{fish: "lake"}), do: "lake"

  def region(%{floor: floor}) when is_binary(floor) do
    r = floor |> String.split("/") |> List.last()
    if Map.has_key?(rules().regions, String.to_atom(r)), do: r, else: "village"
  end

  def region(_), do: nil

  @doc "Loại thời tiết ở bản đồ `map` lúc `now` (chuỗi, nil nếu không có)."
  def kind(map, now \\ DateTime.utc_now()) do
    case region(map) do
      nil -> nil
      r -> forced() || pick(r, slot(now))
    end
  end

  @doc "Mốc giờ (số thứ tự khoảng `slot_min` phút, giờ Việt Nam)."
  def slot(now), do: div(DateTime.to_unix(now) + @utc_offset, rules().slot_min * 60)

  @doc "Loại thời tiết của vùng `region` ở mốc `slot` (hàm thuần)."
  def pick(region, slot) do
    opts = Map.fetch!(rules().regions, String.to_atom(region))
    total = opts |> Enum.map(&Enum.at(&1, 1)) |> Enum.sum()
    roll = rem(:erlang.phash2({slot, region}), total)

    opts
    |> Enum.reduce_while(roll, fn [k, w], left ->
      if left < w, do: {:halt, k}, else: {:cont, left - w}
    end)
  end

  @doc """
  Mức cộng của thời tiết ở bản đồ `map` lúc `now` (anh duyệt): `%{kind, element, pct}` — kỹ năng hệ `element` gây thêm
  `pct` sát thương khi đánh quái; nil nếu bản đồ không có thời tiết.
  """
  def bonus(map, now \\ DateTime.utc_now()) do
    with k when is_binary(k) <- kind(map, now),
         %{element: el, pct: pct} <- Map.get(rules()[:bonus] || %{}, String.to_atom(k)) do
      %{kind: k, element: el, pct: pct}
    else
      _ -> nil
    end
  end

  defp forced do
    case Application.get_env(:hac_long, :weather) || System.get_env("WEATHER") do
      k when is_binary(k) and k != "" -> k
      _ -> nil
    end
  end
end

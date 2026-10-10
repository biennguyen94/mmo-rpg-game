defmodule HacLong.TienLen.Wire do
  @moduledoc """
  Đổi dữ liệu bàn Tiến Lên sang dạng gửi được qua kênh (JSON): lá bài thành mã (`"3S"`,
  `"10H"`), bộ bài thành `%{type, cards}`, tuple thành danh sách, MapSet thành danh sách.
  Chỉ dùng cho dữ liệu đã chiếu theo ghế (`Room.view/2`, sự kiện công khai).
  """
  alias HacLong.TienLen.{Card, Combination}

  def encode(%Card{} = c), do: Card.to_code(c)
  def encode(%Combination{type: t, cards: cards}), do: %{type: t, cards: encode(cards)}
  def encode(%MapSet{} = s), do: s |> MapSet.to_list() |> encode()
  def encode(%DateTime{} = d), do: d
  def encode(%_{} = s), do: s |> Map.from_struct() |> encode()
  def encode(m) when is_map(m), do: Map.new(m, fn {k, v} -> {key(k), encode(v)} end)
  def encode(l) when is_list(l), do: Enum.map(l, &encode/1)
  def encode(t) when is_tuple(t), do: t |> Tuple.to_list() |> encode()
  def encode(pid) when is_pid(pid) or is_reference(pid), do: nil
  def encode(v), do: v

  defp key(k) when is_atom(k) or is_binary(k), do: k
  defp key(k), do: to_string(k)
end

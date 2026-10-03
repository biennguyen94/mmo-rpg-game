defmodule Mu.World.Collision do
  @moduledoc """
  Định dạng `collision.bin` (OPEN_QUESTIONS D4): `width × height` byte theo hàng
  (`index = y × width + x`), `0` đi được, `1` chặn. Sinh từ `tiles` + `walkable` của map JSON
  bằng `mix mu.maps.build`. Hàm thuần, không đọc file lúc biên dịch.
  """

  @doc "Sinh collision từ map JSON đã decode (khóa chuỗi)."
  def from_map(%{"tiles" => rows, "walkable" => walkable}) do
    walkable = MapSet.new(walkable)

    for row <- rows, ch <- String.graphemes(row), into: <<>> do
      if MapSet.member?(walkable, ch), do: <<0>>, else: <<1>>
    end
  end

  @doc "Ô `(x, y)` có đi được không theo collision `bin` rộng `width` (ngoài biên: không)."
  def walkable?(bin, width, height, x, y)
      when is_integer(x) and is_integer(y) and x >= 0 and y >= 0 and x < width and y < height,
      do: :binary.at(bin, y * width + x) == 0

  def walkable?(_, _, _, _, _), do: false
end

defmodule HacLong.Game.EventRooms do
  @moduledoc """
  Phòng sự kiện theo mốc chuyển sinh (`RULES.event_rooms`, DECISIONS "Sự kiện đánh chung theo phòng"). Hàm thuần.

  Quảng Trường Quỷ, Lâu Đài Máu, Hỗn Chiến Thành: người có số lần chuyển sinh trong cùng một khoảng `bands` vào chung
  một phòng; quái của phòng mạnh theo mốc cao nhất của khoảng (`k/1`, tối đa `max_rebirths`).
  """

  alias HacLong.Game.Data

  @bands Data.rules().event_rooms.bands
  @max_rebirths Data.rules().character.max_rebirths

  @doc "Số phòng."
  def count, do: length(@bands)

  @doc "Phòng (0…) của người chuyển sinh `k` lần."
  def band(k) do
    k = k || 0
    Enum.find_index(@bands, fn [lo, hi] -> k >= lo and k <= hi end) || count() - 1
  end

  @doc "Mốc chuyển sinh quái của phòng mạnh theo (mốc cao nhất của khoảng, tối đa `max_rebirths`)."
  def k(band), do: min(Enum.at(@bands, band) |> List.last(), @max_rebirths)

  @doc "Nhãn phòng cho giao diện, vd \"CS 2–3\", \"CS 10+\"."
  def label(band) do
    [lo, hi] = Enum.at(@bands, band)

    cond do
      hi >= @max_rebirths and lo >= @max_rebirths -> "CS #{lo}+"
      lo == hi -> "CS #{lo}"
      true -> "CS #{lo}–#{hi}"
    end
  end
end

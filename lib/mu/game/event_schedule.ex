defmodule Mu.Game.EventSchedule do
  @moduledoc """
  Lịch event theo giờ UTC (P6-M5, P6-5 / P6-6) — **hàm thuần**, đồng hồ truyền vào.

  Event cấu hình `%{"everyHours", "offsetHours", "durationMinutes", "announceMinutes"}`: bắt đầu ở
  phút 0 của các giờ `h` với `(h − offsetHours) mod everyHours = 0` (tính theo giây Unix nên qua
  ngày vẫn đúng vì 24 chia hết cho chu kỳ dùng ở đây), kéo dài `durationMinutes`.
  """

  @doc """
  Pha của event tại `now` (giây Unix): `{:running, start, ends}` đang diễn ra,
  `{:announce, start}` còn ≤ `announceMinutes` phút tới lần kế, ngược lại `{:idle, start_kế}`.
  """
  def phase(now, cfg) do
    period = cfg["everyHours"] * 3600
    offset = cfg["offsetHours"] * 3600
    start = Integer.floor_div(now - offset, period) * period + offset
    ends = start + cfg["durationMinutes"] * 60
    next = start + period

    cond do
      now < ends -> {:running, start, ends}
      now >= next - cfg["announceMinutes"] * 60 -> {:announce, next}
      true -> {:idle, next}
    end
  end
end

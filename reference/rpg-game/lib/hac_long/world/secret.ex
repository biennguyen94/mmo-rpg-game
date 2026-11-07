defmodule HacLong.World.Secret do
  @moduledoc """
  Động Bí Ẩn (DECISIONS "Bản đồ đẹp hơn" B2, "Động Bí Ẩn"), số ở `RULES.secret`.

  - **Đêm** tính theo giờ Việt Nam lùi 12 tiếng (20 giờ hôm nay → 5 giờ mai là một đêm, `night_of/1`).
  - **Cửa mở** (`open?/1`): ban đêm (`HacLong.World.Clock`) và đêm đó nằm trong `open_chance` số đêm (chọn cố định theo đêm).
  - **Người đầu tiên mỗi đêm** (`found/4`): báo cả server, ghi Bia (`HacLong.World.SecretRecords`), không tính bot.
  - **Trùm đêm** (`boss_due?/2`): mỗi đêm cửa mở, thức giấc một lần lúc `boss_at/1` (ngẫu nhiên cố định theo đêm trong
    khung `boss_from_h..boss_to_h`). `HacLong.World.SecretWatch` thả trùm, báo động sắp sụp, đưa người ra khi trời sáng.
  - **Đếm đêm** (`visit/2`): `secret: %{nights, last}` trong nhân vật (thành tựu Kẻ Đi Đêm).
  """
  alias HacLong.Game.Data
  alias HacLong.World.Clock

  @utc_offset 7 * 3600

  def rules, do: Data.rules().secret
  def map_id, do: rules().map

  @doc "Ngày của đêm đang diễn ra (giờ Việt Nam lùi 12 tiếng)."
  def night_of(now) do
    now |> DateTime.add(@utc_offset - 12 * 3600, :second) |> DateTime.to_date()
  end

  @doc "Đêm `date` cửa động có mở không (cố định theo đêm, khoảng `open_chance` số đêm)."
  def open_night?(date),
    do: rem(:erlang.phash2({:secret_open, date}), 1000) < round(rules().open_chance * 1000)

  @doc "Cửa động đang mở: ban đêm và đêm nay là đêm mở. Ép để thử: biến môi trường `SECRET_OPEN` = 1 / 0."
  def open?(now \\ DateTime.utc_now()) do
    case System.get_env("SECRET_OPEN") do
      "1" -> true
      "0" -> false
      _ -> Clock.night?(now) and open_night?(night_of(now))
    end
  end

  @doc "Lúc trùm đêm thức giấc trong đêm `date` (UTC), ngẫu nhiên cố định theo đêm trong khung giờ."
  def boss_at(date) do
    r = rules()
    span = rem(r.boss_to_h - r.boss_from_h + 24, 24) * 3600
    offset = rem(:erlang.phash2({:secret_boss, date}), max(span, 1))

    # 0 giờ đêm `date` theo giờ Việt Nam lùi 12 tiếng = 12 giờ trưa ngày `date` giờ VN
    {:ok, noon} = DateTime.new(date, ~T[12:00:00], "Etc/UTC")

    noon
    |> DateTime.add(-@utc_offset, :second)
    |> DateTime.add((r.boss_from_h - 12) * 3600 + offset, :second)
  end

  @doc "Tới giờ trùm đêm thức giấc (cửa mở, đã qua `boss_at/1`)."
  def boss_due?(now), do: open?(now) and DateTime.compare(now, boss_at(night_of(now))) != :lt

  @doc "Còn ≤ `warn_min` phút là trời sáng (5 giờ giờ Việt Nam)."
  def collapse_soon?(now) do
    h = Clock.hour(now)
    h >= 5 - rules().warn_min / 60 and h < 5
  end

  @doc "Người chơi `p` (`uid`) vừa vào động: người đầu tiên đêm nay thì báo cả server, ghi Bia. Trả `:announced` | `:ok`."
  def found(map, p, uid, now \\ DateTime.utc_now()) do
    night = night_of(now)
    key = {__MODULE__, map.id, night}

    if :persistent_term.get(key, nil) == nil and not HacLong.Bots.bot?(uid) do
      :persistent_term.put(key, p.name)
      HacLong.World.SecretRecords.record(uid, p.name, "found", night)
      HacLong.Chat.system("🌙 #{p.name} là người đầu tiên đêm nay tìm ra #{map.name}!")
      :announced
    else
      :ok
    end
  end

  @doc "Đếm đêm đã vào động (mỗi đêm một lần)."
  def visit(p, now \\ DateTime.utc_now()) do
    night = Date.to_iso8601(night_of(now))
    s = load(Map.get(p, :secret))

    if s.last == night,
      do: Map.put(p, :secret, s),
      else: Map.put(p, :secret, %{nights: s.nights + 1, last: night})
  end

  @doc "Đọc `secret` đã lưu (khóa chuỗi hoặc atom)."
  def load(nil), do: %{nights: 0, last: nil}

  def load(m) when is_map(m),
    do: %{nights: m[:nights] || m["nights"] || 0, last: m[:last] || m["last"]}

  def load(_), do: load(nil)
end

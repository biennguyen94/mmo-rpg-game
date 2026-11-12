defmodule HacLong.SkyEvent do
  @moduledoc """
  Sự kiện trên trời (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long"), đối xứng `HacLong.LakeEvent`. Số ở `RULES.sky`.

  - **Chim Lạc** (`bird`): mỗi `bird.every` giây, vào lúc ngẫu nhiên, lượn ở một ô trời của Đồi Sáo Diều (`spots/0`,
    gần mép đồi) trong `bird.stay` giây. Có người cảm hóa được (`fly_away/0`) hoặc hết giờ thì bay đi.
  - **Đàn Hạc** (`flock`): như trên với `flock.every` / `flock.stay`; không bay đi khi có người thả trúng.
  - **Mưa sao băng** (`meteor`): ban đêm (`HacLong.World.Clock.night?/0`) mỗi `meteor.every` giây rơi `meteor.count`
    Mảnh Sao ở ô đi được của đồi, mỗi viên ở `meteor.stay` giây; nhặt (`take_star/1`, Session kiểm chỗ đứng) thì mất.
  - Long Phượng Hội đã bỏ hẳn (DECISIONS "Thú thành vật phẩm"): Hắc Long ghép ở Lão Hỗn Nguyên (`HacLong.Game.DragonEgg`).

  Trạng thái chỉ trong bộ nhớ; client nhận `{:sky, public}` qua `topic/0` (kênh đẩy xuống `sky`).
  `config :hac_long, :sky_event, auto: false` (test) thì không tự hẹn giờ; quản trị gọi `summon/2`.
  """
  use GenServer

  alias HacLong.Chat
  alias HacLong.Game.Data
  alias HacLong.World.Maps

  @topic "sky_event"

  def topic, do: @topic
  defp r, do: Data.rules().sky
  defp map_id, do: r().map

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @pk_warn_ms Data.rules().slay.event_pk.warn_min * 60_000

  @doc """
  Đang được đồ sát trên bản đồ này không (DECISIONS "Đồ sát ở Hồ / Đồi theo giờ sự kiện"): từ lúc báo sắp xuất hiện
  tới lúc xuất hiện; ngoài khung đó bản đồ là vùng an toàn.
  """
  def pk_open? do
    case GenServer.whereis(__MODULE__) do
      nil -> false
      pid -> GenServer.call(pid, :pk)
    end
  end

  defp call(msg, default) do
    case GenServer.whereis(__MODULE__) do
      nil -> default
      pid -> GenServer.call(pid, msg)
    end
  end

  @doc "`{ô Chim Lạc, ô Đàn Hạc}` đang có (nil nếu không)."
  def tiles, do: call(:tiles, {nil, nil})

  @doc "Trạng thái cho client."
  def public, do: call(:public, public(%{bird: nil, flock: nil, stars: []}))

  @doc "Nhặt Mảnh Sao ở ô `{x, y}` của đồi: `:ok` nếu còn (và xóa), `:error` nếu không có."
  def take_star(at), do: call({:take_star, at}, :error)

  @doc "Có người cảm hóa được Chim Lạc: bay đi ngay."
  def fly_away, do: GenServer.cast(__MODULE__, {:gone, :bird})

  @doc "Gọi ngay (quản trị / test): `:bird`, `:flock` (ô `at` hoặc ngẫu nhiên), `:meteor` (một trận sao băng)."
  def summon(kind, at \\ nil), do: GenServer.call(__MODULE__, {:summon, kind, at})

  @doc """
  Các ô trời Chim Lạc / Đàn Hạc có thể hiện: trong `spot_depth` hàng trên mép trời của cột (thấy được khi đứng trên đồi;
  dây diều không giới hạn nên ô nào cũng thả tới).
  """
  def spots do
    m = Maps.get(map_id())

    for x <- 0..(m.width - 1),
        e = HacLong.Game.Kite.edge(m, x),
        e != nil,
        y <- max(0, e - r().spot_depth + 1)..e,
        do: {x, y}
  end

  # ô đi được của đồi (sao băng rơi), trừ cổng / NPC
  defp ground do
    m = Maps.get(map_id())

    for y <- 0..(m.height - 1),
        x <- 0..(m.width - 1),
        Maps.tile(m, x, y) in [",", ":", "*"],
        Maps.walkable?(m, x, y),
        do: {x, y}
  end

  # ---------- Tiến trình ----------

  @impl true
  def init(:ok) do
    auto = Application.get_env(:hac_long, :sky_event, [])[:auto] != false

    if auto do
      schedule(:bird)
      schedule(:flock)
      Process.send_after(self(), :meteor, r().meteor.every * 1000)
    end

    {:ok, %{bird: nil, flock: nil, stars: [], auto: auto}}
  end

  @impl true
  def handle_call(:pk, _from, s), do: {:reply, s[:pk] == true, s}
  def handle_call(:tiles, _from, s), do: {:reply, {tile_of(s.bird), tile_of(s.flock)}, s}
  def handle_call(:public, _from, s), do: {:reply, public(s), s}

  def handle_call({:take_star, at}, _from, s) do
    t = now()

    case Enum.split_with(s.stars, &(&1.at == at and &1.until > t)) do
      {[_ | _], rest} ->
        s = %{s | stars: rest}
        broadcast(s)
        {:reply, :ok, s}

      _ ->
        {:reply, :error, s}
    end
  end

  def handle_call({:summon, kind, at}, _from, s) when kind in [:bird, :flock] do
    s = rise(s, kind, at)
    {:reply, public(s), s}
  end

  def handle_call({:summon, :meteor, _}, _from, s) do
    s = shower(s)
    {:reply, public(s), s}
  end

  @impl true
  def handle_cast({:gone, kind}, s), do: {:noreply, gone(s, kind)}

  @impl true
  def handle_info({:pk_warn, :bird}, s) do
    Chat.system(
      "⚔ Chim Lạc sắp xuất hiện ở Đồi Sáo Diều trong #{div(@pk_warn_ms, 60_000)} phút! Từ giờ tới lúc đó Đồi Sáo Diều được đồ sát."
    )

    {:noreply, Map.put(s, :pk, true)}
  end

  def handle_info({:rise, kind}, s) do
    schedule(kind)
    {:noreply, rise(s, kind, nil)}
  end

  def handle_info({:gone, kind, ref}, s) do
    if match?(%{ref: ^ref}, s[kind]), do: {:noreply, gone(s, kind)}, else: {:noreply, s}
  end

  def handle_info(:meteor, s) do
    Process.send_after(self(), :meteor, r().meteor.every * 1000)
    {:noreply, if(HacLong.World.Clock.night?(), do: shower(s), else: s)}
  end

  def handle_info({:stars_gone, ref}, s) do
    t = now()
    stars = Enum.reject(s.stars, &(&1.ref == ref or &1.until <= t))

    if length(stars) != length(s.stars) do
      s = %{s | stars: stars}
      broadcast(s)
      {:noreply, s}
    else
      {:noreply, s}
    end
  end

  # ---------- Nội bộ ----------

  defp rules(:bird), do: r().bird
  defp rules(:flock), do: r().flock

  # lần hiện kế tiếp: một lúc ngẫu nhiên trong `every` giây tới
  defp schedule(kind) do
    every = rules(kind).every * 1000
    stay = rules(kind).stay * 1000

    delay = every - rem(now(), every) + :rand.uniform(every - stay)
    Process.send_after(self(), {:rise, kind}, delay)

    # Chim Lạc: báo trước `RULES.slay.event_pk.warn_min` phút, mở đồ sát trên bản đồ tới lúc hiện
    if kind == :bird,
      do: Process.send_after(self(), {:pk_warn, kind}, max(0, delay - @pk_warn_ms))
  end

  defp rise(s, kind, at) do
    # Chim Lạc đã hiện: hết giờ đồ sát trên bản đồ
    s = if kind == :bird, do: Map.put(s, :pk, false), else: s
    other = tile_of(s[if(kind == :bird, do: :flock, else: :bird)])
    tile = at || spots() |> Enum.reject(&(&1 == other)) |> Enum.random()
    ref = make_ref()
    stay = rules(kind).stay * 1000
    Process.send_after(self(), {:gone, kind, ref}, stay)
    s = Map.put(s, kind, %{tile: tile, until: now() + stay, ref: ref})

    if kind == :bird,
      do:
        Chat.system(
          "🐦 Chim Lạc đang lượn trên Đồi Sáo Diều! Thả diều trúng chỗ nó lượn để cảm hóa."
        )

    broadcast(s)
    s
  end

  defp gone(s, kind) do
    if s[kind] do
      s = Map.put(s, kind, nil)
      broadcast(s)
      s
    else
      s
    end
  end

  defp shower(s) do
    m = r().meteor
    ref = make_ref()
    taken = MapSet.new(s.stars, & &1.at)
    until = now() + m.stay * 1000

    new =
      ground()
      |> Enum.reject(&MapSet.member?(taken, &1))
      |> Enum.take_random(m.count)
      |> Enum.map(&%{at: &1, until: until, ref: ref})

    Process.send_after(self(), {:stars_gone, ref}, m.stay * 1000)
    s = %{s | stars: s.stars ++ new}
    broadcast(s)
    s
  end

  defp tile_of(nil), do: nil
  defp tile_of(%{tile: t}), do: t

  defp public(s) do
    t = now()
    {b, bl} = pub(s.bird)
    {f, fl} = pub(s.flock)

    %{
      bird: b,
      birdLeft: bl,
      flock: f,
      flockLeft: fl,
      stars: for(%{at: {x, y}, until: u} <- s.stars, u > t, do: [x, y])
    }
  end

  defp pub(nil), do: {nil, 0}
  defp pub(%{tile: {x, y}, until: u}), do: {[x, y], max(0, u - now())}

  defp broadcast(s), do: Phoenix.PubSub.broadcast(HacLong.PubSub, @topic, {:sky, public(s)})

  defp now, do: System.system_time(:millisecond)
end

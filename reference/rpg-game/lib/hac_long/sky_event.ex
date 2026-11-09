defmodule HacLong.SkyEvent do
  @moduledoc """
  Sự kiện trên trời (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long"), đối xứng `HacLong.LakeEvent`. Số ở `RULES.sky`.

  - **Chim Lạc** (`bird`): mỗi `bird.every` giây, vào lúc ngẫu nhiên, lượn ở một ô trời của Đồi Sáo Diều (`spots/0`,
    gần mép đồi) trong `bird.stay` giây. Có người cảm hóa được (`fly_away/0`) hoặc hết giờ thì bay đi.
  - **Đàn Hạc** (`flock`): như trên với `flock.every` / `flock.stay`; không bay đi khi có người thả trúng.
  - **Mưa sao băng** (`meteor`): ban đêm (`HacLong.World.Clock.night?/0`) mỗi `meteor.every` giây rơi `meteor.count`
    Mảnh Sao ở ô đi được của đồi, mỗi viên ở `meteor.stay` giây; nhặt (`take_star/1`, Session kiểm chỗ đứng) thì mất.
  - **Long Phượng Hội** (`hoi`): kiểm mỗi `@tick_ms`: Long Vương đang nổi (`HacLong.LakeEvent.tile/0`) và Chim Lạc
    đang lượn, chưa có hội, đã qua `hoi.cooldown` giây từ hội trước → vòng sáng ở Tế Đàn (`hoi.at`, `hoi.radius`) trong
    `hoi.stay` giây, báo cả server. Làm lễ ở `HacLong.Game.DragonEgg`.

  Trạng thái chỉ trong bộ nhớ; client nhận `{:sky, public}` qua `topic/0` (kênh đẩy xuống `sky`).
  `config :hac_long, :sky_event, auto: false` (test) thì không tự hẹn giờ; quản trị gọi `summon/2`.
  """
  use GenServer

  alias HacLong.Chat
  alias HacLong.Game.Data
  alias HacLong.World.Maps

  @topic "sky_event"
  @tick_ms 5_000

  def topic, do: @topic
  defp r, do: Data.rules().sky
  defp map_id, do: r().map

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  defp call(msg, default) do
    case GenServer.whereis(__MODULE__) do
      nil -> default
      pid -> GenServer.call(pid, msg)
    end
  end

  @doc "`{ô Chim Lạc, ô Đàn Hạc}` đang có (nil nếu không)."
  def tiles, do: call(:tiles, {nil, nil})

  @doc "Long Phượng Hội đang diễn ra: `%{id, at: {x, y}, until}` hoặc nil."
  def hoi, do: call(:hoi, nil)

  @doc "Trạng thái cho client."
  def public, do: call(:public, public(%{bird: nil, flock: nil, stars: [], hoi: nil}))

  @doc "Nhặt Mảnh Sao ở ô `{x, y}` của đồi: `:ok` nếu còn (và xóa), `:error` nếu không có."
  def take_star(at), do: call({:take_star, at}, :error)

  @doc "Có người cảm hóa được Chim Lạc: bay đi ngay."
  def fly_away, do: GenServer.cast(__MODULE__, {:gone, :bird})

  @doc "Gọi ngay (quản trị / test): `:bird`, `:flock` (ô `at` hoặc ngẫu nhiên), `:meteor` (một trận sao băng), `:hoi`."
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
      Process.send_after(self(), :tick, @tick_ms)
    end

    {:ok, %{bird: nil, flock: nil, stars: [], hoi: nil, hoi_next: 0, auto: auto}}
  end

  @impl true
  def handle_call(:tiles, _from, s), do: {:reply, {tile_of(s.bird), tile_of(s.flock)}, s}
  def handle_call(:hoi, _from, s), do: {:reply, s.hoi, s}
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

  def handle_call({:summon, :hoi, _}, _from, s) do
    s = start_hoi(s)
    {:reply, public(s), s}
  end

  @impl true
  def handle_cast({:gone, kind}, s), do: {:noreply, gone(s, kind)}

  @impl true
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

  def handle_info(:tick, s) do
    Process.send_after(self(), :tick, @tick_ms)

    if s.bird && s.hoi == nil && now() >= s.hoi_next && HacLong.LakeEvent.tile() != nil,
      do: {:noreply, start_hoi(s)},
      else: {:noreply, s}
  end

  def handle_info({:hoi_end, id}, %{hoi: %{id: id}} = s) do
    s = %{s | hoi: nil}
    broadcast(s)
    {:noreply, s}
  end

  def handle_info({:hoi_end, _}, s), do: {:noreply, s}

  # ---------- Nội bộ ----------

  defp rules(:bird), do: r().bird
  defp rules(:flock), do: r().flock

  # lần hiện kế tiếp: một lúc ngẫu nhiên trong `every` giây tới
  defp schedule(kind) do
    every = rules(kind).every * 1000
    stay = rules(kind).stay * 1000

    Process.send_after(
      self(),
      {:rise, kind},
      every - rem(now(), every) + :rand.uniform(every - stay)
    )
  end

  defp rise(s, kind, at) do
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

  defp start_hoi(s) do
    h = r().hoi
    id = System.unique_integer([:positive])
    Process.send_after(self(), {:hoi_end, id}, h.stay * 1000)
    hoi = %{id: id, at: List.to_tuple(h.at), until: now() + h.stay * 1000}

    Chat.system(
      "🐉🐦 Long Phượng Hội! Long Vương và Chim Lạc cùng hiện, vòng sáng mở ở Tế Đàn trong #{div(h.stay, 60)} phút. Ai có đủ hai thần thú hãy đến làm lễ!"
    )

    s = %{s | hoi: hoi, hoi_next: now() + (h.stay + h.cooldown) * 1000}
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
      stars: for(%{at: {x, y}, until: u} <- s.stars, u > t, do: [x, y]),
      hoi:
        s.hoi &&
          %{at: Tuple.to_list(s.hoi.at), left: max(0, s.hoi.until - t), radius: r().hoi.radius}
    }
  end

  defp pub(nil), do: {nil, 0}
  defp pub(%{tile: {x, y}, until: u}), do: {[x, y], max(0, u - now())}

  defp broadcast(s), do: Phoenix.PubSub.broadcast(HacLong.PubSub, @topic, {:sky, public(s)})

  defp now, do: System.system_time(:millisecond)
end

defmodule HacLong.LakeEvent do
  @moduledoc """
  Long Vương nổi ở Hồ Long Vương (DECISIONS "Long Vương nổi mỗi giờ"): mỗi `RULES.fishing.dragon.every` giây, vào một
  lúc ngẫu nhiên trong khoảng đó, Ngài nổi ở **một ô nước ngẫu nhiên** (ô câu được: trong tầm `reach` của một ô đi được
  cạnh nước) trong `stay` giây. Chỉ thả câu trúng đúng ô đó mới có cơ hội (`HacLong.Game.Fishing.cast/4`). Có người câu
  được (`dive/0`) hoặc hết giờ thì Ngài lặn.

  Trạng thái chỉ trong bộ nhớ; mọi người chơi nhận `{:lake, public}` qua `topic/0` (kênh đẩy xuống client `lake`).
  `config :hac_long, :lake_event, auto: false` (test) thì không tự hẹn giờ; quản trị gọi `summon/0`.
  """
  use GenServer

  alias HacLong.Game.Data
  alias HacLong.World.Maps

  @topic "lake_event"
  @map "long_vuong_lake"

  def topic, do: @topic
  def map_id, do: @map

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Ô Long Vương đang nổi `{x, y}` (nil nếu chưa nổi). Không chạy (test) thì nil."
  def tile do
    case GenServer.whereis(__MODULE__) do
      nil -> nil
      pid -> GenServer.call(pid, :tile)
    end
  end

  @doc "Trạng thái cho client: `%{tile: [x, y] | nil, left: mili giây còn lại}`."
  def public do
    case GenServer.whereis(__MODULE__) do
      nil -> %{tile: nil, left: 0}
      pid -> GenServer.call(pid, :public)
    end
  end

  @doc "Gọi Ngài nổi ngay (quản trị / test), ở ô `at` hoặc ô ngẫu nhiên. Trả về trạng thái."
  def summon(at \\ nil), do: GenServer.call(__MODULE__, {:summon, at})

  @doc "Có người câu được: Ngài lặn ngay."
  def dive, do: GenServer.cast(__MODULE__, :dive)

  @doc "Các ô Long Vương có thể nổi: ô nước trong tầm `reach` của một ô đi được đứng cạnh nước."
  def spots do
    m = Maps.get(@map)
    reach = Data.rules().fishing.dragon.reach

    stands =
      for y <- 0..(m.height - 1),
          x <- 0..(m.width - 1),
          Maps.walkable?(m, x, y),
          Enum.any?([{1, 0}, {-1, 0}, {0, 1}, {0, -1}], fn {dx, dy} ->
            Maps.water?(m, x + dx, y + dy)
          end),
          do: {x, y}

    for y <- 0..(m.height - 1),
        x <- 0..(m.width - 1),
        Maps.water?(m, x, y),
        Enum.any?(stands, fn {sx, sy} -> max(abs(sx - x), abs(sy - y)) <= reach end),
        do: {x, y}
  end

  @impl true
  def init(:ok) do
    if Application.get_env(:hac_long, :lake_event, [])[:auto] != false, do: schedule()
    {:ok, %{tile: nil, until: 0, ref: nil}}
  end

  @impl true
  def handle_call(:tile, _from, s), do: {:reply, s.tile, s}
  def handle_call(:public, _from, s), do: {:reply, public(s), s}

  def handle_call({:summon, at}, _from, s) do
    s = rise(s, at)
    {:reply, public(s), s}
  end

  @impl true
  def handle_cast(:dive, s), do: {:noreply, sink(s)}

  @impl true
  def handle_info(:rise, s) do
    schedule()
    {:noreply, rise(s, nil)}
  end

  def handle_info({:sink, ref}, %{ref: ref} = s), do: {:noreply, sink(s)}
  def handle_info({:sink, _}, s), do: {:noreply, s}

  defp rules, do: Data.rules().fishing.dragon

  # lần nổi kế tiếp: một lúc ngẫu nhiên trong `every` giây tới (trung bình mỗi `every` một lần)
  defp schedule do
    every = rules().every * 1000

    Process.send_after(
      self(),
      :rise,
      every - rem(now(), every) + :rand.uniform(every - rules().stay * 1000)
    )
  end

  defp rise(s, at) do
    tile = at || Enum.random(spots())
    ref = make_ref()
    Process.send_after(self(), {:sink, ref}, rules().stay * 1000)
    s = %{s | tile: tile, until: now() + rules().stay * 1000, ref: ref}
    broadcast(s)
    s
  end

  defp sink(%{tile: nil} = s), do: s

  defp sink(s) do
    s = %{s | tile: nil, until: 0, ref: nil}
    broadcast(s)
    s
  end

  defp public(%{tile: nil}), do: %{tile: nil, left: 0}
  defp public(%{tile: {x, y}, until: u}), do: %{tile: [x, y], left: max(0, u - now())}

  defp broadcast(s), do: Phoenix.PubSub.broadcast(HacLong.PubSub, @topic, {:lake, public(s)})

  defp now, do: System.system_time(:millisecond)
end

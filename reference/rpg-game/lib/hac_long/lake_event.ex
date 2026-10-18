defmodule HacLong.LakeEvent do
  @moduledoc """
  Sự kiện ở Hồ Long Vương, mỗi loại một ô nước ngẫu nhiên câu tới được (trong tầm `reach` của một ô đi được cạnh nước):

  - **Long Vương nổi** (DECISIONS "Long Vương nổi mỗi giờ"): mỗi `RULES.fishing.dragon.every` giây, vào một lúc ngẫu
    nhiên trong khoảng đó, Ngài nổi trong `stay` giây. Chỉ thả câu trúng đúng ô đó mới có cơ hội
    (`HacLong.Game.Fishing.cast/5`). Có người câu được (`dive/0`) hoặc hết giờ thì Ngài lặn.
  - **Đàn Cá Vàng** (DECISIONS "Đàn Cá Vàng, việc của Ông Lão"): như trên với `RULES.fishing.school.every` / `stay`;
    thả trúng ô đó thì dễ ra Cá Chép Vàng, thêm Long Khí. Đàn không tan khi có người câu.

  Trạng thái chỉ trong bộ nhớ; mọi người chơi nhận `{:lake, public}` qua `topic/0` (kênh đẩy xuống client `lake`).
  `config :hac_long, :lake_event, auto: false` (test) thì không tự hẹn giờ; quản trị gọi `summon/1`, `school_summon/1`.
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
  def tile, do: tiles() |> elem(0)

  @doc "`{ô Long Vương, ô Đàn Cá Vàng}` đang có (nil nếu không)."
  def tiles do
    case GenServer.whereis(__MODULE__) do
      nil -> {nil, nil}
      pid -> GenServer.call(pid, :tiles)
    end
  end

  @doc "Trạng thái cho client: `%{tile, left, school, schoolLeft}` (ô `[x, y]` hoặc nil, mili giây còn lại)."
  def public do
    case GenServer.whereis(__MODULE__) do
      nil -> public(%{dragon: nil, school: nil})
      pid -> GenServer.call(pid, :public)
    end
  end

  @doc "Gọi Ngài nổi ngay (quản trị / test), ở ô `at` hoặc ô ngẫu nhiên. Trả về trạng thái."
  def summon(at \\ nil), do: GenServer.call(__MODULE__, {:rise, :dragon, at})

  @doc "Gọi Đàn Cá Vàng hiện ngay (quản trị / test)."
  def school_summon(at \\ nil), do: GenServer.call(__MODULE__, {:rise, :school, at})

  @doc "Có người câu được: Ngài lặn ngay."
  def dive, do: GenServer.cast(__MODULE__, {:sink, :dragon})

  @doc "Các ô sự kiện có thể hiện: ô nước trong tầm `reach` của một ô đi được đứng cạnh nước."
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
    if Application.get_env(:hac_long, :lake_event, [])[:auto] != false do
      schedule(:dragon)
      schedule(:school)
    end

    {:ok, %{dragon: nil, school: nil}}
  end

  @impl true
  def handle_call(:tiles, _from, s), do: {:reply, {tile_of(s.dragon), tile_of(s.school)}, s}
  def handle_call(:public, _from, s), do: {:reply, public(s), s}

  def handle_call({:rise, kind, at}, _from, s) do
    s = rise(s, kind, at)
    {:reply, public(s), s}
  end

  @impl true
  def handle_cast({:sink, kind}, s), do: {:noreply, sink(s, kind)}

  @impl true
  def handle_info({:rise, kind}, s) do
    schedule(kind)
    {:noreply, rise(s, kind, nil)}
  end

  def handle_info({:sink, kind, ref}, s) do
    if match?(%{ref: ^ref}, s[kind]), do: {:noreply, sink(s, kind)}, else: {:noreply, s}
  end

  defp rules(:dragon), do: Data.rules().fishing.dragon
  defp rules(:school), do: Data.rules().fishing.school

  # lần hiện kế tiếp: một lúc ngẫu nhiên trong `every` giây tới (trung bình mỗi `every` một lần)
  defp schedule(kind) do
    every = rules(kind).every * 1000
    stay = rules(kind).stay * 1000

    Process.send_after(
      self(),
      {:rise, kind},
      every - rem(now(), every) + :rand.uniform(every - stay)
    )
  end

  # hai sự kiện không trùng ô
  defp rise(s, kind, at) do
    other = tile_of(s[other(kind)])
    tile = at || spots() |> Enum.reject(&(&1 == other)) |> Enum.random()
    ref = make_ref()
    stay = rules(kind).stay * 1000
    Process.send_after(self(), {:sink, kind, ref}, stay)
    s = Map.put(s, kind, %{tile: tile, until: now() + stay, ref: ref})
    broadcast(s)
    s
  end

  defp other(:dragon), do: :school
  defp other(:school), do: :dragon

  defp sink(s, kind) do
    if s[kind] do
      s = Map.put(s, kind, nil)
      broadcast(s)
      s
    else
      s
    end
  end

  defp tile_of(nil), do: nil
  defp tile_of(%{tile: t}), do: t

  defp public(s) do
    {t, l} = pub(s.dragon)
    {st, sl} = pub(s.school)
    %{tile: t, left: l, school: st, schoolLeft: sl}
  end

  defp pub(nil), do: {nil, 0}
  defp pub(%{tile: {x, y}, until: u}), do: {[x, y], max(0, u - now())}

  defp broadcast(s), do: Phoenix.PubSub.broadcast(HacLong.PubSub, @topic, {:lake, public(s)})

  defp now, do: System.system_time(:millisecond)
end

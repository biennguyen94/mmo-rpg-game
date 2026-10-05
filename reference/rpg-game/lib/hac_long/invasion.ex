defmodule HacLong.Invasion do
  @moduledoc """
  Sự kiện Golden Invasion (Phase 7, F1 / F4; số ở `RULES.invasion`).

  - Theo lịch: bắt đầu ở mỗi mốc `every_hours` giờ tròn giờ Việt Nam (0h, 2h, 4h… với 2 giờ), kéo dài
    `minutes` phút. `next_start/2` là hàm thuần (test với đồng hồ giả).
  - Lúc bắt đầu: mỗi bản đồ trong `maps` nhận số quái vàng ghi ở đó (`MapServer.invade/2`), không hồi sinh.
    Quái vàng mạnh hơn `strength_mult`, thưởng × `reward_mult`, rơi ngọc `jewel_chance` (`HacLong.World`).
  - Hạ hết quái vàng một bản đồ thì trùm vàng của vùng xuất hiện ở đó (`boss: true`; câu 7-B), rơi ngọc
    chắc chắn. Hạ trùm vàng thì bản đồ đó xong; mọi bản đồ xong thì sự kiện kết thúc sớm.
  - Hết giờ: quái vàng chưa ai đánh biến mất (đang đánh thì đánh nốt). Bắt đầu / kết thúc báo cả server.
  - Trạng thái (`status/0`) phát `{:invasion, status}` trên kênh trùm thế giới (`HacLong.WorldBoss.topic/0`),
    client hiện dải thông báo kèm giờ còn lại.

  `config :hac_long, :invasion, auto: false` (test) thì không tự chạy theo lịch; dùng `start_now/1`.
  """
  use GenServer
  require Logger

  alias HacLong.{Chat, WorldBoss}
  alias HacLong.Game.Data
  alias HacLong.World.MapServer

  @rules Data.rules().invasion
  @boss @rules.boss
  # giờ Việt Nam
  @utc_offset 7 * 3600

  def rules, do: @rules

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Lần bắt đầu tiếp theo (DateTime UTC) sau `now`: mốc tròn `every` giờ theo giờ Việt Nam."
  def next_start(now, every \\ @rules.every_hours) do
    local = DateTime.to_unix(now) + @utc_offset
    step = every * 3600
    next = (div(local, step) + 1) * step
    DateTime.from_unix!(next - @utc_offset)
  end

  @doc "Trạng thái: `%{active, ends_at (unix), maps: %{id => \"run\" | \"boss\" | \"done\"}, next_at}`."
  def status, do: GenServer.call(__MODULE__, :status)

  @doc "Bắt đầu ngay (quản trị / test). `maps`: thay danh sách bản đồ (mặc định `RULES.invasion.maps`)."
  def start_now(maps \\ nil), do: GenServer.call(__MODULE__, {:start, maps})

  @doc "Kết thúc ngay."
  def stop_now, do: GenServer.call(__MODULE__, :stop)

  @doc "MapServer báo: bản đồ `map_id` vừa hết quái vàng (`boss?`: con vừa hạ là trùm vàng)."
  def cleared(map_id, boss?), do: GenServer.cast(__MODULE__, {:cleared, map_id, boss?})

  # ---------- Máy chủ ----------

  @impl true
  def init(:ok) do
    s = %{active: false, ends_at: nil, maps: %{}, next_at: nil, timer: nil}
    {:ok, schedule(s)}
  end

  @impl true
  def handle_call(:status, _from, s), do: {:reply, view(s), s}

  def handle_call({:start, maps}, _from, s) do
    s = if s.active, do: finish(s, "restart"), else: s
    s = begin(s, maps || @rules.maps)
    {:reply, view(s), s}
  end

  def handle_call(:stop, _from, s),
    do: {:reply, :ok, if(s.active, do: finish(s, "stop"), else: s)}

  @impl true
  def handle_cast({:cleared, map_id, boss?}, %{active: true} = s) do
    case s.maps[map_id] do
      "run" when not boss? and @boss ->
        MapServer.invade_boss(map_id)
        Chat.system("👑 Trùm vàng xuất hiện ở #{map_name(map_id)}!")
        {:noreply, publish(put_in(s.maps[map_id], "boss"))}

      st when st in ["run", "boss"] ->
        s = put_in(s.maps[map_id], "done")

        if Enum.all?(s.maps, fn {_, v} -> v == "done" end),
          do: {:noreply, finish(s, "cleared")},
          else: {:noreply, publish(s)}

      _ ->
        {:noreply, s}
    end
  end

  def handle_cast({:cleared, _, _}, s), do: {:noreply, s}

  @impl true
  def handle_info(:tick, s) do
    s = %{s | timer: nil}
    s = if s.active, do: finish(s, "timeout"), else: begin(s, @rules.maps)
    {:noreply, s}
  end

  defp begin(s, maps) do
    counts =
      for {id, n} <- maps, into: %{} do
        id = to_string(id)

        got =
          try do
            MapServer.invade(id, n)
          catch
            :exit, _ -> 0
          end

        {id, if(got > 0, do: "run", else: "done")}
      end

    ends = System.system_time(:second) + @rules.minutes * 60
    s = cancel(s)
    timer = Process.send_after(self(), :tick, @rules.minutes * 60 * 1000)

    Chat.system(
      "✨ Golden Invasion! Quái vàng xuất hiện ở #{Enum.map_join(Map.keys(counts), ", ", &map_name/1)} trong #{@rules.minutes} phút: thưởng ×#{@rules.reward_mult}, dễ rơi ngọc."
    )

    publish(%{s | active: true, ends_at: ends, maps: counts, timer: timer})
  end

  defp finish(s, why) do
    for {id, _} <- s.maps do
      try do
        MapServer.end_invasion(id)
      catch
        :exit, _ -> :ok
      end
    end

    if why != "restart" do
      Chat.system(
        if why == "cleared",
          do: "🏆 Golden Invasion kết thúc: mọi quái vàng và trùm vàng đã bị hạ!",
          else: "Golden Invasion kết thúc."
      )
    end

    s = cancel(s)
    s |> Map.merge(%{active: false, ends_at: nil, maps: %{}}) |> schedule() |> publish()
  end

  # hẹn lần sau theo lịch (tắt khi `auto: false`)
  defp schedule(s) do
    if Application.get_env(:hac_long, :invasion, [])[:auto] == false do
      %{s | next_at: nil}
    else
      next = next_start(DateTime.utc_now())
      ms = max(DateTime.diff(next, DateTime.utc_now(), :millisecond), 1000)
      %{s | next_at: DateTime.to_unix(next), timer: Process.send_after(self(), :tick, ms)}
    end
  end

  defp cancel(%{timer: nil} = s), do: s

  defp cancel(s) do
    Process.cancel_timer(s.timer)
    %{s | timer: nil}
  end

  defp view(s), do: Map.take(s, [:active, :ends_at, :maps, :next_at])

  defp publish(s) do
    Phoenix.PubSub.broadcast(HacLong.PubSub, WorldBoss.topic(), {:invasion, view(s)})
    s
  end

  defp map_name(id), do: (m = HacLong.World.Maps.get(id)) && m.name
end

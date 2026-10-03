defmodule Mu.WorldEvents do
  @moduledoc """
  Lịch event thế giới (P6-M5; `KB_TECH_STACK §4` có `WorldBoss`): **Golden Invasion** (P6-5) và
  **world boss** (P6-6). Một tiến trình kiểm lịch mỗi `events.checkSeconds` (`Mu.Game.EventSchedule`,
  giờ UTC), ra lệnh cho MapServer sinh / thu quái event (`MapServer.spawn_event/5`,
  `despawn_event/2`), báo SYSTEM toàn server và đẩy event `world_event` cho mọi người.

  Không lưu DB: server khởi động lại giữa event thì event đó mất (quái event chỉ sống trong RAM
  của MapServer), lịch chạy tiếp từ lần kế.

  Kết thúc khi hết giờ, khi boss bị hạ, hoặc khi hạ hết quái vàng. Bật / tắt tay:
  `start/1`, `stop/1` (`mix mu.event start golden_invasion --node …`).
  """
  use GenServer
  require Logger

  alias Mu.Chat
  alias Mu.Game.{Config, EventSchedule}
  alias Mu.World.{Maps, MapServer}

  # loại event (tên dùng trong act / lệnh quản trị / nhãn quái) → khóa config
  @kinds %{"golden_invasion" => "goldenInvasion", "world_boss" => "worldBoss"}

  def kinds, do: Map.keys(@kinds)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Bật event `kind` ngay (quản trị / test). Đang chạy → `{:error, :running}`."
  def start(kind), do: GenServer.call(__MODULE__, {:start, kind})

  @doc "Tắt event `kind` ngay (thu quái, báo kết thúc)."
  def stop(kind), do: GenServer.call(__MODULE__, {:stop, kind})

  @doc "Event đang diễn ra: danh sách payload `world_event` (người vào game giữa chừng)."
  def active do
    GenServer.call(__MODULE__, :active)
  catch
    :exit, _ -> []
  end

  @doc "Kiểm lịch ở thời điểm `now` (giây Unix) — test dùng đồng hồ giả."
  def check(now), do: GenServer.call(__MODULE__, {:check, now})

  @doc "MapServer báo một quái event bị hạ (`info`: `map, monster, name, top`)."
  def monster_killed(tag, info), do: GenServer.cast(__MODULE__, {:killed, tag, info})

  @impl true
  def init(opts) do
    auto = Keyword.get(opts, :auto, Application.get_env(:mu, :world_events_auto, true))
    s = %{auto: auto, events: Map.new(kinds(), &{&1, %{running: nil, announced: nil, done: nil}})}
    if auto, do: schedule()
    {:ok, s}
  end

  @impl true
  def handle_call({:start, kind}, _from, s) do
    cond do
      not Map.has_key?(@kinds, kind) -> {:reply, {:error, :unknown}, s}
      s.events[kind].running -> {:reply, {:error, :running}, s}
      true -> {:reply, :ok, begin(s, kind, now() + cfg(kind)["durationMinutes"] * 60, nil)}
    end
  end

  def handle_call({:stop, kind}, _from, s) do
    if Map.has_key?(@kinds, kind) and s.events[kind].running,
      do: {:reply, :ok, finish(s, kind, :stopped)},
      else: {:reply, {:error, :not_running}, s}
  end

  def handle_call(:active, _from, s) do
    {:reply, for({k, %{running: r}} <- s.events, r, do: payload(k, "start", r.ends_at)), s}
  end

  def handle_call({:check, now}, _from, s), do: {:reply, :ok, run_check(s, now)}

  @impl true
  def handle_cast({:killed, kind, info}, s) do
    case s.events[kind] do
      %{running: %{} = r} ->
        left = r.remaining - 1
        s = put_in(s.events[kind].running.remaining, left)

        cond do
          kind == "world_boss" ->
            Chat.system("#{info.top || "Ai đó"} đã hạ #{info.name}!")
            {:noreply, finish(s, kind, :killed)}

          left <= 0 ->
            {:noreply, finish(s, kind, :cleared)}

          true ->
            {:noreply, s}
        end

      _ ->
        {:noreply, s}
    end
  end

  @impl true
  def handle_info(:tick, s) do
    schedule()
    {:noreply, run_check(s, now())}
  end

  def handle_info(_msg, s), do: {:noreply, s}

  # ---------- Lịch ----------

  defp run_check(s, now) do
    Enum.reduce(kinds(), s, fn kind, s ->
      ev = s.events[kind]

      s =
        case EventSchedule.phase(now, cfg(kind)) do
          {:running, start, ends} when ev.running == nil and ev.done != start ->
            begin(s, kind, ends, start)

          {:announce, start} when ev.announced != start ->
            minutes = div(start - now + 59, 60)
            Chat.system("#{cfg(kind)["name"]} sẽ xuất hiện sau #{minutes} phút!")
            broadcast(payload(kind, "soon", start))
            put_in(s.events[kind].announced, start)

          _ ->
            s
        end

      case s.events[kind].running do
        %{ends_at: e} when now >= e -> finish(s, kind, :timeout)
        _ -> s
      end
    end)
  end

  defp begin(s, kind, ends_at, start) do
    c = cfg(kind)

    spawned =
      for sp <- c["spawns"], reduce: 0 do
        n ->
          try do
            {:ok, ids} =
              MapServer.spawn_event(sp["map"], kind, sp["monster"], sp["count"], sp["area"])

            n + length(ids)
          catch
            :exit, reason ->
              Logger.error(
                "Không sinh được quái event #{kind} ở #{sp["map"]}: #{inspect(reason)}"
              )

              n
          end
      end

    maps = c["spawns"] |> Enum.map(&map_name(&1["map"])) |> Enum.uniq() |> Enum.join(", ")
    Chat.system("#{c["name"]} bắt đầu ở #{maps}! (#{c["durationMinutes"]} phút)")
    broadcast(payload(kind, "start", ends_at))

    put_in(s.events[kind], %{
      s.events[kind]
      | running: %{ends_at: ends_at, remaining: spawned},
        done: start || s.events[kind].done
    })
  end

  defp finish(s, kind, reason) do
    c = cfg(kind)

    for map <- c["spawns"] |> Enum.map(& &1["map"]) |> Enum.uniq() do
      try do
        MapServer.despawn_event(map, kind)
      catch
        :exit, _ -> :ok
      end
    end

    text =
      case {kind, reason} do
        {"world_boss", :timeout} -> "#{c["name"]} đã biến mất."
        {"world_boss", :killed} -> "#{c["name"]} đã bị hạ."
        {_, :cleared} -> "#{c["name"]}: đã hạ hết quái."
        _ -> "#{c["name"]} kết thúc."
      end

    Chat.system(text)
    broadcast(payload(kind, "end", now()))
    put_in(s.events[kind].running, nil)
  end

  # ---------- Tiện ích ----------

  defp payload(kind, state, at) do
    c = cfg(kind)

    %{
      kind: kind,
      name: c["name"],
      state: state,
      maps: c["spawns"] |> Enum.map(& &1["map"]) |> Enum.uniq(),
      # "soon": giờ bắt đầu; "start": giờ kết thúc; "end": lúc kết thúc (ms)
      at: at * 1000
    }
  end

  defp broadcast(p) do
    for id <- Maps.ids(),
        do:
          Phoenix.PubSub.broadcast(Mu.PubSub, MapServer.topic(id), {:map_event, "world_event", p})

    :ok
  end

  defp map_name(id), do: (Maps.get(id) || %{name: id}).name
  defp cfg(kind), do: Config.get(["events", Map.fetch!(@kinds, kind)])
  defp now, do: System.os_time(:second)

  defp schedule,
    do: Process.send_after(self(), :tick, Config.get(["events", "checkSeconds"]) * 1000)
end

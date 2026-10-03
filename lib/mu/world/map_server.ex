defmodule Mu.World.MapServer do
  @moduledoc """
  Một tiến trình / map (`KB_TECH_STACK §4`): giữ vị trí người chơi (và từ M3: quái, đồ dưới
  đất), xử lý tuần tự. Khung (Registry, monitor chủ, PubSub theo map) học từ
  `HacLong.World.MapServer`; vòng tick viết mới.

  - Vòng mô phỏng `server.simulationHz` (20 Hz) với bước thời gian cố định
    (`1000 / simulationHz` ms). Lịch tick tính theo đồng hồ monotonic (`next_at += tick_ms`)
    nên không trôi; tụt lại thì chạy bù tối đa `@max_catch_up` tick.
  - Snapshot delta mỗi `simulationHz / snapshotHz` tick: chỉ entity đổi từ lần trước, kèm
    `removed` (`KB_TECHNICAL §5`). Phase 1 broadcast cho cả map (chưa AOI).
  - `spawn` / `despawn` khi entity vào/ra map (payload: OPEN_QUESTIONS P3).
  - Sự kiện gửi qua PubSub topic `topic/1` dạng `{:map_event, event, payload}`.
  - Di chuyển: `move_to` tính A* trên server (client không gửi đường đi), mỗi bước tốn
    `1000 / movement.playerTilesPerSecond` ms, bước chéo ×`movement.diagonalCostFactor` (G3).

  Chế độ tick (`config :mu, :map_tick`): `:auto` (mặc định) hoặc `:manual` (test gọi `tick/2`).
  """
  use GenServer
  require Logger

  alias Mu.Game.Config
  alias Mu.World.{Maps, Pathfinding}

  @max_catch_up 5

  # ---------- API ----------

  def child_spec(map_id) when is_binary(map_id), do: child_spec(map_id: map_id)

  def child_spec(opts) when is_list(opts) do
    %{id: {__MODULE__, opts[:map_id]}, start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Tùy chọn: `map_id`, `name` (mặc định qua Registry), `tick` (`:auto` | `:manual`),
  `topic` (mặc định `topic/1`; test dùng topic riêng).
  """
  def start_link(opts) do
    case Keyword.get(opts, :name, via(opts[:map_id])) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  def via(map_id), do: {:via, Registry, {Mu.World.Registry, map_id}}
  def topic(map_id), do: "map:#{map_id}"
  def entity_id(character_id), do: "p_" <> character_id

  @doc """
  Đưa người chơi vào map (gọi lại khi đã có mặt thì chỉ đổi tiến trình chủ, giữ vị trí).
  `player`: `%{character_id, name, level, hp, hp_max, x, y}`; `owner` (Session) bị monitor,
  chết thì người chơi rời map. Vị trí không đi được → `playerSpawn`.
  Trả `{:ok, %{entity_id, x, y, entities}}` (`entities`: payload `spawn` của mọi thứ trên map).
  """
  def join(server, player, owner), do: GenServer.call(server(server), {:join, player, owner})

  @doc "Rời map: `{:ok, {x, y}}` (vị trí cuối để lưu) hoặc `:error`."
  def leave(server, character_id), do: GenServer.call(server(server), {:leave, character_id})

  @doc "`:ok` hoặc `{:error, \"INVALID_TARGET\"}`."
  def move_to(server, character_id, x, y),
    do: GenServer.call(server(server), {:move_to, character_id, x, y})

  @doc "Vị trí hiện tại `{x, y}` hoặc `nil`."
  def position(server, character_id),
    do: GenServer.call(server(server), {:position, character_id})

  @doc "Chạy `n` tick ngay (chế độ `:manual`, dùng trong test)."
  def tick(server, n \\ 1), do: GenServer.call(server(server), {:tick, n})

  @doc "Thống kê: số tick, độ trễ lớn nhất (ms), số người chơi."
  def stats(server), do: GenServer.call(server(server), :stats)

  defp server(map_id) when is_binary(map_id), do: via(map_id)
  defp server(server), do: server

  # ---------- GenServer ----------

  @impl true
  def init(opts) do
    map = Maps.get(Keyword.fetch!(opts, :map_id)) || raise "không có map #{opts[:map_id]}"
    sim_hz = Config.get(["server", "simulationHz"])
    tick_ms = div(1000, sim_hz)
    mode = Keyword.get(opts, :tick, Application.get_env(:mu, :map_tick, :auto))

    s = %{
      map: map,
      topic: Keyword.get(opts, :topic, topic(map.id)),
      players: %{},
      tick_ms: tick_ms,
      snapshot_every: div(sim_hz, Config.get(["server", "snapshotHz"])),
      step_ms: 1000 / Config.get(["movement", "playerTilesPerSecond"]),
      diagonal: Config.get(["movement", "diagonalCostFactor"]),
      max_path_nodes: Config.get(["movement", "maxPathNodes"]),
      ticks: 0,
      dirty: MapSet.new(),
      removed: [],
      mode: mode,
      next_at: nil,
      max_drift: 0
    }

    s =
      if mode == :auto do
        now = now()
        Process.send_after(self(), :tick, tick_ms)
        %{s | next_at: now + tick_ms}
      else
        s
      end

    {:ok, s}
  end

  @impl true
  def handle_call({:join, p, owner}, _from, s) do
    id = p.character_id

    {s, entity} =
      case s.players do
        %{^id => old} ->
          Process.demonitor(old.ref, [:flush])
          e = %{old | owner: owner, ref: Process.monitor(owner)}
          {put_in(s.players[id], e), e}

        _ ->
          {x, y} =
            if Maps.walkable?(s.map, p.x, p.y), do: {p.x, p.y}, else: s.map.player_spawn

          e = %{
            id: entity_id(id),
            character_id: id,
            name: p.name,
            level: p.level,
            hp: p.hp,
            hp_max: p.hp_max,
            x: x,
            y: y,
            state: "idle",
            path: [],
            progress: 0,
            owner: owner,
            ref: Process.monitor(owner)
          }

          broadcast(s, "spawn", spawn_payload(e))
          {%{put_in(s.players[id], e) | removed: List.delete(s.removed, e.id)}, e}
      end

    reply = %{entity_id: entity.id, x: entity.x, y: entity.y, entities: entities(s)}
    {:reply, {:ok, reply}, s}
  end

  def handle_call({:leave, id}, _from, s) do
    case s.players do
      %{^id => e} ->
        Process.demonitor(e.ref, [:flush])
        {:reply, {:ok, {e.x, e.y}}, remove(s, id)}

      _ ->
        {:reply, :error, s}
    end
  end

  def handle_call({:move_to, id, x, y}, _from, s) do
    with %{} = e <- s.players[id],
         true <- (is_integer(x) and is_integer(y)) || {:malformed, e},
         {:ok, path} <-
           Pathfinding.find(&Maps.walkable?(s.map, &1, &2), {e.x, e.y}, {x, y}, s.max_path_nodes) do
      e = %{e | path: path, progress: 0}
      e = if path == [], do: %{e | state: "idle"}, else: e
      {:reply, :ok, mark(put_in(s.players[id], e), e)}
    else
      nil ->
        {:reply, {:error, "INVALID_TARGET"}, s}

      {:malformed, e} ->
        Logger.warning("move_to sai kiểu từ #{e.id}: #{inspect({x, y})}")
        {:reply, {:error, "INVALID_TARGET"}, s}

      :error ->
        {:reply, {:error, "INVALID_TARGET"}, s}
    end
  end

  def handle_call({:position, id}, _from, s) do
    {:reply, (e = s.players[id]) && {e.x, e.y}, s}
  end

  def handle_call({:tick, n}, _from, s) do
    {:reply, :ok, Enum.reduce(1..n//1, s, fn _, s -> step(s) end)}
  end

  def handle_call(:stats, _from, s) do
    {:reply, %{ticks: s.ticks, max_drift_ms: s.max_drift, players: map_size(s.players)}, s}
  end

  @impl true
  def handle_info(:tick, s) do
    now = now()
    drift = now - s.next_at

    # tụt quá nhiều thì chạy bù có giới hạn rồi đặt lại lịch (không chạy dồn vô hạn)
    behind = min(div(max(drift, 0), s.tick_ms) + 1, @max_catch_up)
    s = Enum.reduce(1..behind, s, fn _, s -> step(s) end)

    next_at =
      if drift > @max_catch_up * s.tick_ms,
        do: now + s.tick_ms,
        else: s.next_at + behind * s.tick_ms

    Process.send_after(self(), :tick, max(next_at - now, 0))
    {:noreply, %{s | next_at: next_at, max_drift: max(s.max_drift, drift)}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, s) do
    case Enum.find(s.players, fn {_, e} -> e.ref == ref end) do
      {id, _} -> {:noreply, remove(s, id)}
      nil -> {:noreply, s}
    end
  end

  def handle_info(_msg, s), do: {:noreply, s}

  # ---------- Mô phỏng ----------

  # Một tick cố định `tick_ms`: di chuyển người chơi theo đường đã tính, rồi snapshot nếu tới lượt.
  defp step(s) do
    s =
      Enum.reduce(s.players, s, fn
        {_, %{path: []}}, s -> s
        {id, e}, s -> advance(s, id, e)
      end)

    s = %{s | ticks: s.ticks + 1}
    if rem(s.ticks, s.snapshot_every) == 0, do: snapshot(s), else: s
  end

  defp advance(s, id, e) do
    moved = walk(%{e | progress: e.progress + s.tick_ms, state: "walk"}, s.step_ms, s.diagonal)
    s = put_in(s.players[id], moved)
    if {moved.x, moved.y, moved.state} != {e.x, e.y, e.state}, do: mark(s, moved), else: s
  end

  # Đi hết số bước mà `progress` cho phép; hết đường thì đứng yên.
  defp walk(%{path: [{nx, ny} = next | rest]} = e, step_ms, diagonal) do
    cost = if Pathfinding.diagonal?({e.x, e.y}, next), do: step_ms * diagonal, else: step_ms

    if e.progress >= cost,
      do: walk(%{e | x: nx, y: ny, path: rest, progress: e.progress - cost}, step_ms, diagonal),
      else: e
  end

  defp walk(%{path: []} = e, _, _), do: %{e | state: "idle", progress: 0}

  defp mark(s, e), do: %{s | dirty: MapSet.put(s.dirty, e.character_id)}

  defp snapshot(s) do
    if MapSet.size(s.dirty) == 0 and s.removed == [], do: s, else: send_snapshot(s)
  end

  defp send_snapshot(s) do
    entities =
      for id <- s.dirty,
          e = s.players[id],
          do: %{id: e.id, x: e.x, y: e.y, hp: e.hp, state: e.state}

    broadcast(s, "snapshot", %{
      t: System.os_time(:millisecond),
      entities: entities,
      removed: s.removed
    })

    %{s | dirty: MapSet.new(), removed: []}
  end

  defp remove(s, id) do
    e = s.players[id]
    broadcast(s, "despawn", %{id: e.id})

    %{
      s
      | players: Map.delete(s.players, id),
        dirty: MapSet.delete(s.dirty, id),
        removed: [e.id | s.removed]
    }
  end

  defp entities(s) do
    npcs =
      for n <- s.map.npcs do
        %{
          id: "npc_" <> n.id,
          kind: "npc",
          x: n.x,
          y: n.y,
          hp: nil,
          maxHp: nil,
          state: "idle",
          name: n.id,
          level: nil,
          templateId: n.id
        }
      end

    npcs ++ Enum.map(Map.values(s.players), &spawn_payload/1)
  end

  defp spawn_payload(e) do
    %{
      id: e.id,
      kind: "player",
      x: e.x,
      y: e.y,
      hp: e.hp,
      maxHp: e.hp_max,
      state: e.state,
      name: e.name,
      level: e.level
    }
  end

  defp broadcast(s, event, payload),
    do: Phoenix.PubSub.broadcast(Mu.PubSub, s.topic, {:map_event, event, payload})

  defp now, do: System.monotonic_time(:millisecond)
end

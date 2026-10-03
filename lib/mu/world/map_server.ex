defmodule Mu.World.MapServer do
  @moduledoc """
  Một tiến trình / map (`KB_TECH_STACK §4`): giữ vị trí + HP/MP người chơi, quái, đồ dưới
  đất; xử lý tuần tự (ai đến trước đánh trước). Khung (Registry, monitor chủ, PubSub theo
  map) học từ `HacLong.World.MapServer`; vòng tick, AI, chiến đấu viết mới.

  - Vòng mô phỏng `server.simulationHz` (20 Hz), bước thời gian cố định `1000 / simulationHz`
    ms. Lịch tick theo đồng hồ monotonic (`next_at += tick_ms`) nên không trôi; tụt lại thì
    chạy bù tối đa `@max_catch_up` tick. Thời gian mô phỏng `now` (ms) = số tick × tick_ms
    (chế độ tự tick cộng thêm phần đã trôi trong tick hiện tại để cooldown chính xác).
  - AI quái `server.monsterAiHz` (10 Hz), chỉ chạy khi map có người (quái "ngủ" khi vắng).
  - Snapshot delta mỗi `simulationHz / snapshotHz` tick: entity đổi + `removed`
    (`KB_TECHNICAL §5`). Broadcast cả map; mỗi kênh lọc theo tầm nhìn (`MuWeb.Aoi`, P3-M1).
  - Sự kiện: `spawn`, `despawn`, `snapshot`, `combat` qua PubSub `topic/1` dạng
    `{:map_event, event, payload}`. Gửi riêng tiến trình chủ (Session):
    `{:map_reward, %{exp, zen, monster}}`, `{:map_died, character_id}`.
  - Tiến độ nhân vật (level, EXP, stat, Zen) do Session giữ; MapServer nhận chỉ số đã tính
    (`stats`, `skills`) qua `join/3` và `update_player/3` (PHASE1_PLAN R5).

  Chế độ tick (`config :mu, :map_tick`): `:auto` (mặc định) hoặc `:manual` (test gọi `tick/2`).
  """
  use GenServer
  require Logger

  alias Mu.Game.{Config, Data, Drops, Engine, Rng}
  alias Mu.Ulid
  alias Mu.World.{Maps, MonsterAi, Pathfinding}

  @max_catch_up 5

  # ---------- API ----------

  def child_spec(map_id) when is_binary(map_id), do: child_spec(map_id: map_id)

  def child_spec(opts) when is_list(opts) do
    %{id: {__MODULE__, opts[:map_id]}, start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Tùy chọn: `map_id`, `name` (mặc định qua Registry; `nil` = không đăng ký), `tick`
  (`:auto` | `:manual`), `topic` (mặc định `topic/1`), `seed` (RNG; mặc định ngẫu nhiên),
  `spawn_monsters` (mặc định `true`).
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
  Đưa người chơi vào map (gọi lại khi đã có mặt thì chỉ đổi tiến trình chủ, giữ trạng thái).
  `player`: `%{character_id, name, class, level, hp, mp, x, y, stats, skills}` (`stats` =
  `Engine.derived/2`); `owner` (Session) bị monitor, chết thì người chơi rời map. Vị trí
  không đi được → `playerSpawn`.
  Trả `{:ok, %{entity_id, x, y, hp, mp, entities}}` (`entities`: payload `spawn` của mọi thứ).
  """
  def join(server, player, owner), do: GenServer.call(server(server), {:join, player, owner})

  @doc "Rời map: `{:ok, %{x, y, hp, mp}}` (để lưu; đang chết thì như đã hồi sinh) hoặc `:error`."
  def leave(server, character_id), do: GenServer.call(server(server), {:leave, character_id})

  @doc "`:ok` hoặc `{:error, code}`."
  def move_to(server, character_id, x, y),
    do: GenServer.call(server(server), {:move_to, character_id, x, y})

  @doc """
  Dùng skill (`basic_attack` = đánh thường) lên `target` (id entity quái) hoặc điểm `{x, y}`.
  `:ok` hoặc `{:error, code}` (`KB_TECHNICAL §5`).
  """
  def use_skill(server, character_id, skill_id, target, rid),
    do: GenServer.call(server(server), {:skill, character_id, skill_id, target, rid})

  @doc """
  Lấy đồ `ground_id` khỏi mặt đất cho người chơi (trước khi Session ghi DB): còn sống, trong
  `interaction.pickupRange` ô, hết loot protect hoặc là chủ (G13).
  `{:ok, %{serial, template_id, ...}}` hoặc `{:error, code}`.
  """
  def take_ground(server, character_id, ground_id),
    do: GenServer.call(server(server), {:take_ground, character_id, ground_id})

  @doc """
  Đặt món người chơi vừa `drop` (đã xóa khỏi DB, `Mu.Game.Items.drop/3`) xuống ô đang đứng
  (P2-9): người vứt giữ quyền nhặt trong `lootProtectSeconds`, biến mất sau `groundItemSeconds`.
  `dropped`: `%{serial, template_id, quantity, attrs}`. Trả `{:ok, ground_id}`.
  """
  def drop_ground(server, character_id, dropped),
    do: GenServer.call(server(server), {:drop_ground, character_id, dropped})

  @doc "Trả đồ về mặt đất (ghi DB thất bại, vd. túi đầy) — giữ nguyên chủ và hạn."
  def return_ground(server, ground), do: GenServer.call(server(server), {:return_ground, ground})

  @doc """
  Dùng potion: còn sống, hết `combat.potionCooldownMs`; hồi `effect` (`%{"hp", "mp"}`), không
  vượt max. `:ok` hoặc `{:error, code}`.
  """
  def use_potion(server, character_id, effect),
    do: GenServer.call(server(server), {:use_potion, character_id, effect})

  @doc "Cập nhật chỉ số sau lên cấp/cộng điểm/trang bị: `%{level?, stats?, skills?, hp?, mp?}`."
  def update_player(server, character_id, changes),
    do: GenServer.call(server(server), {:update_player, character_id, changes})

  @doc "`%{x, y, hp, mp, dead?, combat_remaining_ms}` hoặc `nil`."
  def player_state(server, character_id),
    do: GenServer.call(server(server), {:player_state, character_id})

  @doc "Vị trí hiện tại `{x, y}` hoặc `nil`."
  def position(server, character_id) do
    case player_state(server, character_id) do
      %{x: x, y: y} -> {x, y}
      nil -> nil
    end
  end

  @doc "Chạy `n` tick ngay (chế độ `:manual`, dùng trong test)."
  def tick(server, n \\ 1), do: GenServer.call(server(server), {:tick, n})

  @doc "Thống kê: số tick, độ trễ lớn nhất (ms), số người chơi."
  def stats(server), do: GenServer.call(server(server), :stats)

  @doc "Toàn bộ state (chỉ dùng trong test/debug)."
  def debug_state(server), do: :sys.get_state(server(server))

  @doc "Sửa state trực tiếp (chỉ dùng trong test)."
  def debug_update(server, fun), do: :sys.replace_state(server(server), fun)

  defp server(map_id) when is_binary(map_id), do: via(map_id)
  defp server(server), do: server

  # ---------- GenServer ----------

  @impl true
  def init(opts) do
    map = Maps.get(Keyword.fetch!(opts, :map_id)) || raise "không có map #{opts[:map_id]}"
    server = Config.get(["server"])
    sim_hz = server["simulationHz"]
    tick_ms = div(1000, sim_hz)
    mode = Keyword.get(opts, :tick, Application.get_env(:mu, :map_tick, :auto))

    s = %{
      map: map,
      topic: Keyword.get(opts, :topic, topic(map.id)),
      players: %{},
      monsters: %{},
      ground: %{},
      rng: if(seed = opts[:seed], do: Rng.new(seed), else: Rng.new()),
      tick_ms: tick_ms,
      snapshot_every: div(sim_hz, server["snapshotHz"]),
      ai_every: div(sim_hz, server["monsterAiHz"]),
      regen_every: max(1, div(Config.get(["combat", "mpRegen", "intervalMs"]), tick_ms)),
      step_ms: 1000 / Config.get(["movement", "playerTilesPerSecond"]),
      diagonal: Config.get(["movement", "diagonalCostFactor"]),
      max_path_nodes: Config.get(["movement", "maxPathNodes"]),
      ticks: 0,
      dirty: MapSet.new(),
      removed: [],
      mode: mode,
      next_at: nil,
      last_tick_mono: nil,
      max_drift: 0
    }

    s = if Keyword.get(opts, :spawn_monsters, true), do: spawn_monsters(s), else: s

    s =
      if mode == :auto do
        now = mono()
        Process.send_after(self(), :tick, tick_ms)
        %{s | next_at: now + tick_ms, last_tick_mono: now}
      else
        s
      end

    {:ok, s}
  end

  @impl true
  def handle_call({:join, p, owner}, _from, s) do
    id = p.character_id

    {s, e} =
      case s.players do
        %{^id => old} ->
          Process.demonitor(old.ref, [:flush])
          e = %{old | owner: owner, ref: Process.monitor(owner)}
          {put_in(s.players[id], e), e}

        _ ->
          {x, y} = if Maps.walkable?(s.map, p.x, p.y), do: {p.x, p.y}, else: s.map.player_spawn

          e = %{
            id: entity_id(id),
            kind: :player,
            character_id: id,
            name: p.name,
            class: p.class,
            level: p.level,
            stats: p.stats,
            skills: p.skills,
            hp: min(p.hp, p.stats.hp_max),
            mp: min(p.mp, p.stats.mp_max),
            x: x,
            y: y,
            state: "idle",
            path: [],
            progress: 0,
            cooldowns: %{},
            # P2-M3: buff đang có (`Engine.add_buff/5`), phần lẻ MP hồi tự nhiên
            buffs: %{},
            mp_acc: 0.0,
            dead_at: nil,
            last_combat_at: nil,
            owner: owner,
            ref: Process.monitor(owner)
          }

          broadcast(s, "spawn", spawn_payload(e))
          {%{put_in(s.players[id], e) | removed: List.delete(s.removed, e.id)}, e}
      end

    reply = %{entity_id: e.id, x: e.x, y: e.y, hp: e.hp, mp: e.mp, entities: entities(s)}
    {:reply, {:ok, reply}, s}
  end

  def handle_call({:leave, id}, _from, s) do
    case s.players do
      %{^id => e} ->
        Process.demonitor(e.ref, [:flush])
        e = if e.state == "dead", do: revive(s, e), else: e
        {:reply, {:ok, Map.take(e, [:x, :y, :hp, :mp])}, remove_player(s, id)}

      _ ->
        {:reply, :error, s}
    end
  end

  def handle_call({:move_to, id, x, y}, _from, s) do
    with %{} = e <- s.players[id] || {:error, "INVALID_TARGET"},
         :ok <- if(e.state == "dead", do: {:error, "FORBIDDEN"}, else: :ok),
         :ok <- valid_coords(e, x, y),
         {:ok, path} <-
           Pathfinding.find(&Maps.walkable?(s.map, &1, &2), {e.x, e.y}, {x, y}, s.max_path_nodes) do
      e = %{e | path: path, progress: 0}
      e = if path == [], do: %{e | state: "idle"}, else: e
      {:reply, :ok, mark(put_in(s.players[id], e), e)}
    else
      {:error, code} -> {:reply, {:error, code}, s}
      :error -> {:reply, {:error, "INVALID_TARGET"}, s}
    end
  end

  def handle_call({:skill, id, skill_id, target, rid}, _from, s) do
    case do_skill(s, id, skill_id, target, rid) do
      {:ok, s} -> {:reply, :ok, s}
      {:error, code} -> {:reply, {:error, code}, s}
    end
  end

  def handle_call({:take_ground, id, gid}, _from, s) do
    with %{} = e <- s.players[id] || {:error, "INVALID_TARGET"},
         :ok <- if(e.state == "dead", do: {:error, "FORBIDDEN"}, else: :ok),
         %{} = g <- s.ground[gid] || {:error, "INVALID_TARGET"},
         :ok <- pickup_range(e, g),
         :ok <- loot_owner(s, g, id) do
      broadcast(s, "despawn", %{id: gid})
      {:reply, {:ok, g}, %{s | ground: Map.delete(s.ground, gid), removed: [gid | s.removed]}}
    else
      {:error, code} -> {:reply, {:error, code}, s}
    end
  end

  def handle_call({:drop_ground, id, dropped}, _from, s) do
    e = s.players[id]
    s = drop_item(s, dropped, {e.x, e.y}, id, now(s))
    {:reply, {:ok, "g_" <> dropped.serial}, s}
  end

  def handle_call({:return_ground, g}, _from, s) do
    broadcast(s, "spawn", ground_payload(g))

    {:reply, :ok,
     %{s | ground: Map.put(s.ground, g.id, g), removed: List.delete(s.removed, g.id)}}
  end

  def handle_call({:use_potion, id, effect}, _from, s) do
    t = now(s)

    with %{} = e <- s.players[id] || {:error, "INVALID_TARGET"},
         :ok <- if(e.state == "dead", do: {:error, "FORBIDDEN"}, else: :ok),
         :ok <- if(t >= Map.get(e.cooldowns, "potion", 0), do: :ok, else: {:error, "COOLDOWN"}) do
      e = %{
        e
        | hp: min(e.stats.hp_max, e.hp + (effect["hp"] || 0)),
          mp: min(e.stats.mp_max, e.mp + (effect["mp"] || 0)),
          cooldowns:
            Map.put(e.cooldowns, "potion", t + Config.get(["combat", "potionCooldownMs"]))
      }

      {:reply, :ok, put_entity(s, id, e)}
    else
      {:error, code} -> {:reply, {:error, code}, s}
    end
  end

  def handle_call({:update_player, id, changes}, _from, s) do
    case s.players[id] do
      nil ->
        {:reply, :error, s}

      e ->
        e = Map.merge(e, Map.take(changes, [:level, :stats, :skills, :hp, :mp, :name]))
        e = %{e | hp: min(e.hp, e.stats.hp_max), mp: min(e.mp, e.stats.mp_max)}
        {:reply, :ok, mark(put_in(s.players[id], e), e)}
    end
  end

  def handle_call({:player_state, id}, _from, s) do
    reply =
      case s.players[id] do
        nil ->
          nil

        e ->
          %{
            x: e.x,
            y: e.y,
            hp: e.hp,
            mp: e.mp,
            dead?: e.state == "dead",
            combat_remaining_ms: combat_remaining(s, e)
          }
      end

    {:reply, reply, s}
  end

  def handle_call({:tick, n}, _from, s) do
    {:reply, :ok, Enum.reduce(1..n//1, s, fn _, s -> step(s) end)}
  end

  def handle_call(:stats, _from, s) do
    {:reply, %{ticks: s.ticks, max_drift_ms: s.max_drift, players: map_size(s.players)}, s}
  end

  @impl true
  def handle_info(:tick, s) do
    now = mono()
    drift = now - s.next_at

    # tụt quá nhiều thì chạy bù có giới hạn rồi đặt lại lịch (không chạy dồn vô hạn)
    behind = min(div(max(drift, 0), s.tick_ms) + 1, @max_catch_up)
    s = Enum.reduce(1..behind, s, fn _, s -> step(s) end)

    next_at =
      if drift > @max_catch_up * s.tick_ms,
        do: now + s.tick_ms,
        else: s.next_at + behind * s.tick_ms

    Process.send_after(self(), :tick, max(next_at - now, 0))

    {:noreply, %{s | next_at: next_at, last_tick_mono: now, max_drift: max(s.max_drift, drift)}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, s) do
    case Enum.find(s.players, fn {_, e} -> e.ref == ref end) do
      {id, _} -> {:noreply, remove_player(s, id)}
      nil -> {:noreply, s}
    end
  end

  def handle_info(_msg, s), do: {:noreply, s}

  # ---------- Thời gian ----------

  # Thời gian mô phỏng (ms). Tự tick: cộng phần đã trôi trong tick hiện tại (≤ 1 tick).
  defp now(%{mode: :auto, last_tick_mono: t} = s) when is_integer(t),
    do: s.ticks * s.tick_ms + min(mono() - t, s.tick_ms)

  defp now(s), do: s.ticks * s.tick_ms

  defp mono, do: System.monotonic_time(:millisecond)

  # ---------- Mô phỏng ----------

  # Một tick cố định: di chuyển, AI (10 Hz, khi có người), hồi sinh, hết hạn đồ, snapshot.
  defp step(s) do
    s = %{s | ticks: s.ticks + 1}

    s =
      Enum.reduce(s.players, s, fn
        {_, %{path: []}}, s ->
          s

        {id, e}, s ->
          s |> put_entity(id, advance(e, s.tick_ms, s.step_ms, s.diagonal)) |> portal(id, e)
      end)

    s =
      Enum.reduce(s.monsters, s, fn
        {_, %{path: []}}, s -> s
        {_, %{state: "dead"}}, s -> s
        {id, m}, s -> put_entity(s, id, advance(m, s.tick_ms, m.step_ms, s.diagonal))
      end)

    s = if rem(s.ticks, s.ai_every) == 0, do: s |> ai() |> expire_buffs(), else: s
    s = if rem(s.ticks, s.regen_every) == 0, do: regen_mp(s), else: s
    s = s |> respawn_players() |> expire_ground()
    if rem(s.ticks, s.snapshot_every) == 0, do: snapshot(s), else: s
  end

  # đi hết số bước mà tiến độ cho phép; hết đường thì đứng yên
  defp advance(e, dt, step_ms, diagonal) do
    walking = if e.state in ["idle", "walk"], do: "walk", else: e.state
    walk(%{e | progress: e.progress + dt, state: walking}, step_ms, diagonal)
  end

  defp walk(%{path: [{nx, ny} = next | rest]} = e, step_ms, diagonal) do
    cost = if Pathfinding.diagonal?({e.x, e.y}, next), do: step_ms * diagonal, else: step_ms

    if e.progress >= cost,
      do: walk(%{e | x: nx, y: ny, path: rest, progress: e.progress - cost}, step_ms, diagonal),
      else: e
  end

  defp walk(%{path: []} = e, _, _) do
    state = if e.state == "walk", do: "idle", else: e.state
    %{e | state: state, progress: 0}
  end

  # ghi entity (người hoặc quái) và đánh dấu nếu vị trí/HP/trạng thái đổi
  defp put_entity(s, id, %{kind: :player} = e) do
    old = s.players[id]
    s = put_in(s.players[id], e)
    if changed?(old, e), do: mark(s, e), else: s
  end

  defp put_entity(s, id, %{kind: :monster} = m) do
    old = s.monsters[id]
    s = put_in(s.monsters[id], m)
    if changed?(old, m), do: mark(s, m), else: s
  end

  # người chơi: MP cũng vào snapshot (P2-M3)
  defp changed?(%{kind: :player} = a, b),
    do: {a.x, a.y, a.hp, a.mp, a.state} != {b.x, b.y, b.hp, b.mp, b.state}

  defp changed?(a, b), do: {a.x, a.y, a.hp, a.state} != {b.x, b.y, b.hp, b.state}

  defp mark(s, e), do: %{s | dirty: MapSet.put(s.dirty, e.id)}

  # ---------- Quái ----------

  defp spawn_monsters(s) do
    s.map.spawns
    |> Enum.flat_map(fn sp -> List.duplicate(sp, sp.count) end)
    |> Enum.with_index(1)
    |> Enum.reduce(s, fn {sp, i}, s ->
      tpl = Data.monster(sp.monster) || raise "không có quái #{sp.monster}"
      {{x, y}, rng} = random_cell(s, sp.area, s.rng)
      id = "m_#{i}"

      m = %{
        id: id,
        kind: :monster,
        template_id: sp.monster,
        tpl: tpl,
        area: sp.area,
        home: {x, y},
        x: x,
        y: y,
        hp: tpl["hp"],
        hp_max: tpl["hp"],
        state: "idle",
        target: nil,
        path: [],
        progress: 0,
        step_ms: 1000 / tpl["moveSpeed"],
        next_attack_at: 0,
        respawn_at: nil,
        damage_by: %{}
      }

      %{s | rng: rng, monsters: Map.put(s.monsters, id, m)}
    end)
  end

  # ô ngẫu nhiên đi được, ngoài safe zone, trong vùng sinh
  defp random_cell(s, area, rng) do
    {x, rng} = Rng.int(rng, area.x, area.x + area.w - 1)
    {y, rng} = Rng.int(rng, area.y, area.y + area.h - 1)
    if monster_walkable?(s, x, y), do: {{x, y}, rng}, else: random_cell(s, area, rng)
  end

  defp monster_walkable?(s, x, y), do: Maps.walkable?(s.map, x, y) and not Maps.safe?(s.map, x, y)

  defp ai(s) do
    s = respawn_monsters(s)

    if map_size(s.players) == 0 do
      # không có ai trên map: quái ngủ (KB_GAME_DESIGN §9)
      s
    else
      ctx = %{
        now: now(s),
        players:
          Map.new(s.players, fn {id, e} ->
            {id, %{x: e.x, y: e.y, alive?: e.state != "dead", safe?: Maps.safe?(s.map, e.x, e.y)}}
          end),
        walkable?: &monster_walkable?(s, &1, &2),
        cooldown_ms: Config.get(["combat", "baseCooldownMs"])
      }

      Enum.reduce(Map.keys(s.monsters), s, fn id, s ->
        {m, actions} = MonsterAi.think(s.monsters[id], ctx)
        s = put_entity(s, id, m)
        Enum.reduce(actions, s, fn {:attack, cid}, s -> monster_attack(s, id, cid) end)
      end)
    end
  end

  defp respawn_monsters(s) do
    t = now(s)

    Enum.reduce(s.monsters, s, fn
      {id, %{state: "dead", respawn_at: at} = m}, s when at <= t ->
        {{x, y}, rng} = random_cell(s, m.area, s.rng)

        m = %{
          m
          | x: x,
            y: y,
            home: {x, y},
            hp: m.hp_max,
            state: "idle",
            target: nil,
            path: [],
            progress: 0,
            damage_by: %{},
            respawn_at: nil
        }

        # despawn + spawn cùng id: client không trượt xác từ chỗ cũ sang chỗ mới
        broadcast(s, "despawn", %{id: id})
        broadcast(s, "spawn", spawn_payload(m))
        %{s | rng: rng, monsters: Map.put(s.monsters, id, m)}

      _, s ->
        s
    end)
  end

  # mục tiêu có thể vừa chết vì quái khác trong cùng nhịp AI
  defp monster_attack(s, mid, cid) do
    case s.players[cid] do
      %{state: state} = e when state != "dead" -> do_monster_attack(s, s.monsters[mid], e)
      _ -> s
    end
  end

  defp do_monster_attack(s, m, e) do
    {mid, cid} = {m.id, e.character_id}
    buffed = Engine.with_buffs(e.stats, e.buffs)
    stats = %{defense: buffed.defense, defense_rate: e.stats.defense_rate}
    {res, rng} = Engine.roll_attack(s.rng, Engine.monster_stats(m.tpl), stats)
    hp = max(e.hp - res.dmg, 0)
    e = %{e | hp: hp, last_combat_at: now(s)}
    s = %{s | rng: rng}

    broadcast(s, "combat", %{
      rid: nil,
      attacker: mid,
      target: e.id,
      dmg: res.dmg,
      crit: res.crit,
      hp: hp
    })

    if hp == 0 do
      # chết: mất mọi buff (P2-M3)
      had_buffs? = map_size(e.buffs) > 0
      e = %{e | state: "dead", path: [], progress: 0, dead_at: now(s), buffs: %{}}
      send(e.owner, {:map_died, cid})
      if had_buffs?, do: notify_buffs(s, e)
      put_entity(s, cid, e)
    else
      put_entity(s, cid, e)
    end
  end

  # ---------- Người chơi đánh ----------

  defp do_skill(s, id, skill_id, target, rid) do
    with %{} = e <- s.players[id] || {:error, "INVALID_TARGET"},
         :ok <- if(e.state == "dead", do: {:error, "FORBIDDEN"}, else: :ok),
         %{} = skill <- Data.skill(skill_id) || {:error, "INVALID_TARGET"},
         :ok <- if(skill_id in e.skills, do: :ok, else: {:error, "REQUIREMENT_NOT_MET"}),
         {:ok, aim} <- aim(s, skill, target, e),
         :ok <- safe_zone_ok(s, e, skill),
         :ok <- in_range(e, aim, skill),
         :ok <- off_cooldown(s, e, skill_id),
         :ok <- if(e.mp >= skill["manaCost"], do: :ok, else: {:error, "NO_MANA"}) do
      t = now(s)

      e = %{
        e
        | mp: e.mp - skill["manaCost"],
          cooldowns: Map.put(e.cooldowns, skill_id, t + Engine.skill_cooldown_ms(skill, e.stats)),
          # đánh tại chỗ: dừng đi
          path: [],
          progress: 0,
          state: "idle"
      }

      # chỉ skill đánh quái mới tính là đang combat (G21)
      e = if harmful?(skill), do: %{e | last_combat_at: t}, else: e
      s = put_entity(s, id, e)
      {:ok, apply_skill(s, e, aim, skill, rid)}
    end
  end

  defp harmful?(skill), do: skill["targetType"] in ~w(SINGLE AOE)

  # Đánh quái bị cấm trong safe zone; heal/buff/teleport thì được (P2-M3)
  defp safe_zone_ok(s, e, skill) do
    if harmful?(skill) and Maps.safe?(s.map, e.x, e.y), do: {:error, "FORBIDDEN"}, else: :ok
  end

  # Mục tiêu theo `targetType` (P2-M3):
  # SINGLE / AOE quanh mục tiêu: một quái còn sống; AOE quanh mình / tại ô: quái hoặc ô;
  # ALLY: người chơi còn sống (`p_<id>`; bỏ trống = bản thân); POINT: ô đi được.
  defp aim(s, %{"targetType" => "ALLY"}, target, e) do
    cid =
      case target do
        nil -> e.character_id
        "p_" <> cid -> cid
        _ -> nil
      end

    case cid && s.players[cid] do
      %{state: state} = p when state != "dead" -> {:ok, {:player, cid, {p.x, p.y}}}
      _ -> {:error, "INVALID_TARGET"}
    end
  end

  defp aim(s, %{"targetType" => "POINT"}, {x, y}, _e) when is_integer(x) and is_integer(y) do
    if Maps.walkable?(s.map, x, y), do: {:ok, {:point, {x, y}}}, else: {:error, "INVALID_TARGET"}
  end

  defp aim(_s, %{"targetType" => "POINT"}, _, _e), do: {:error, "INVALID_TARGET"}

  defp aim(s, %{"targetType" => "SINGLE"}, target, _e) when is_binary(target), do: aim(s, target)
  defp aim(_s, %{"targetType" => "SINGLE"}, _target, _e), do: {:error, "INVALID_TARGET"}

  defp aim(s, %{"targetType" => "AOE", "center" => "target"}, target, _e) when is_binary(target),
    do: aim(s, target)

  defp aim(_s, %{"targetType" => "AOE", "center" => "target"}, _target, _e),
    do: {:error, "INVALID_TARGET"}

  defp aim(s, _skill, target, _e), do: aim(s, target)

  defp aim(s, target) when is_binary(target) do
    case s.monsters[target] do
      %{state: state} = m when state != "dead" -> {:ok, {:monster, m.id, {m.x, m.y}}}
      _ -> {:error, "INVALID_TARGET"}
    end
  end

  defp aim(s, {x, y}) when is_integer(x) and is_integer(y) do
    if x in 0..(s.map.width - 1) and y in 0..(s.map.height - 1),
      do: {:ok, {:point, {x, y}}},
      else: {:error, "INVALID_TARGET"}
  end

  defp aim(_s, _), do: {:error, "INVALID_TARGET"}

  defp apply_skill(s, e, aim, %{"targetType" => t} = skill, rid) when t in ~w(SINGLE AOE),
    do: Enum.reduce(victims(s, e, aim, skill), s, &strike(&2, e.character_id, &1, skill, rid))

  # Teleport: tới ô đã kiểm (walkable) ngay; client thấy nhảy qua snapshot (Interp reset)
  defp apply_skill(s, e, {:point, {x, y}}, %{"targetType" => "POINT"}, _rid) do
    e = %{e | x: x, y: y}
    put_entity(s, e.character_id, e)
  end

  defp apply_skill(s, e, {:player, cid, _}, %{"effect" => %{"kind" => "heal"} = eff} = skill, rid) do
    p = s.players[cid]
    hp = min(p.hp + Engine.effect_value(eff, e.stats.energy), p.stats.hp_max)

    broadcast(s, "combat", %{
      rid: rid,
      attacker: e.id,
      target: p.id,
      skill: skill["id"],
      dmg: 0,
      crit: false,
      hp: hp,
      heal: hp - p.hp
    })

    put_entity(s, cid, %{p | hp: hp})
  end

  defp apply_skill(s, e, {:player, cid, _}, %{"effect" => %{"kind" => "buff"} = eff} = skill, rid) do
    p = s.players[cid]
    value = Engine.effect_value(eff, e.stats.energy)
    until = now(s) + eff["durationMs"]
    p = %{p | buffs: Engine.add_buff(p.buffs, skill["id"], eff["stat"], value, until)}

    broadcast(s, "combat", %{
      rid: rid,
      attacker: e.id,
      target: p.id,
      skill: skill["id"],
      dmg: 0,
      crit: false,
      hp: p.hp,
      buff: value
    })

    notify_buffs(s, p)
    put_entity(s, cid, p)
  end

  # Buff hiện có gửi Session chủ (để đưa vào `player.view.buffs`): `expiresAt` = giờ server
  # (ms epoch) để client đếm ngược bằng ServerClock
  defp notify_buffs(s, e) do
    t = now(s)
    wall = System.os_time(:millisecond)

    list =
      for {id, b} <- Enum.sort(e.buffs),
          do: %{id: id, stat: b.stat, value: b.value, expiresAt: wall + b.until - t}

    send(e.owner, {:map_buffs, e.character_id, list})
  end

  defp aim_pos({:monster, _, pos}), do: pos
  defp aim_pos({:player, _, pos}), do: pos
  defp aim_pos({:point, pos}), do: pos

  # đánh thường: tầm theo vũ khí đang cầm (`stats.attack_range`, P2-5)
  defp in_range(e, aim, skill) do
    range =
      if skill["id"] == "basic_attack",
        do: e.stats[:attack_range] || skill["range"],
        else: skill["range"]

    if Pathfinding.chebyshev({e.x, e.y}, aim_pos(aim)) <= range,
      do: :ok,
      else: {:error, "OUT_OF_RANGE"}
  end

  defp off_cooldown(s, e, skill_id) do
    if now(s) >= Map.get(e.cooldowns, skill_id, 0), do: :ok, else: {:error, "COOLDOWN"}
  end

  # SINGLE: chỉ mục tiêu. AOE quanh mục tiêu (`center` target): mục tiêu + quái gần nhất trong
  # `radius` quanh nó, tối đa `maxTargets`. AOE tại ô (`center` point): mọi quái trong `radius`
  # quanh ô/quái đã chọn. AOE quanh mình (`center` self, mặc định): G7.
  defp victims(
         s,
         _e,
         {:monster, mid, {x, y}},
         %{"targetType" => "AOE", "center" => "target"} = skill
       ) do
    near =
      for {id, m} <- s.monsters,
          id != mid,
          m.state != "dead",
          d = Pathfinding.chebyshev({x, y}, {m.x, m.y}),
          d <= skill["radius"],
          do: {d, id}

    [mid | near |> Enum.sort() |> Enum.map(&elem(&1, 1))]
    |> Enum.take(skill["maxTargets"] || length(near) + 1)
  end

  defp victims(s, _e, aim, %{"targetType" => "AOE", "center" => "point"} = skill) do
    {x, y} = aim_pos(aim)

    for {mid, m} <- s.monsters,
        m.state != "dead",
        Pathfinding.chebyshev({x, y}, {m.x, m.y}) <= skill["radius"],
        do: mid
  end

  defp victims(s, e, aim, %{"targetType" => "AOE"} = skill) do
    around =
      for {mid, m} <- s.monsters,
          m.state != "dead",
          Pathfinding.chebyshev({e.x, e.y}, {m.x, m.y}) <= skill["radius"],
          do: mid

    case aim do
      {:monster, mid, _} -> Enum.uniq([mid | Enum.sort(around)])
      _ -> Enum.sort(around)
    end
  end

  defp victims(_s, _e, {:monster, mid, _}, _skill), do: [mid]
  defp victims(_s, _e, _aim, _skill), do: []

  defp strike(s, cid, mid, skill, rid) do
    e = s.players[cid]
    m = s.monsters[mid]

    {res, rng} =
      Engine.roll_attack(
        s.rng,
        Engine.with_buffs(e.stats, e.buffs),
        Engine.monster_stats(m.tpl),
        skill["damageMultiplier"]
      )

    hp = max(m.hp - res.dmg, 0)
    m = MonsterAi.hit(%{m | hp: hp}, cid, res.dmg)
    s = %{s | rng: rng}

    broadcast(s, "combat", %{
      rid: rid,
      attacker: e.id,
      target: mid,
      dmg: res.dmg,
      crit: res.crit,
      hp: hp
    })

    s = put_entity(s, mid, m)
    if hp == 0, do: kill(s, mid, cid), else: s
  end

  # Quái chết: EXP + Zen cho người ra đòn cuối (G12), đồ rơi dưới đất thuộc người gây nhiều
  # sát thương nhất trong `lootProtectSeconds` (G13).
  defp kill(s, mid, killer_id) do
    m = s.monsters[mid]
    killer = s.players[killer_id]
    t = now(s)
    owner = MonsterAi.top_damager(m) || killer_id
    {drop, rng} = Drops.roll(s.rng, m.template_id)
    exp = Engine.exp_gain(m.tpl["experience"], killer.level, m.tpl["level"])
    send(killer.owner, {:map_reward, %{exp: exp, zen: drop.zen, monster: mid}})

    m = %{
      m
      | state: "dead",
        hp: 0,
        target: nil,
        path: [],
        progress: 0,
        damage_by: %{},
        respawn_at: t + m.tpl["respawnSeconds"] * 1000
    }

    s = put_entity(%{s | rng: rng}, mid, m)
    Enum.reduce(drop.items, s, &drop_item(&2, %{template_id: &1}, {m.x, m.y}, owner, t))
  end

  # ---------- Đồ dưới đất (chỉ trong RAM: KB_TECHNICAL §9) ----------

  # `item`: `%{template_id}` (quái rơi, serial mới) hoặc món người chơi vứt (giữ serial,
  # `quantity`, `attrs` để người nhặt nhận lại y nguyên)
  defp drop_item(s, item, {x, y}, owner, t) do
    drop = Config.get(["drop"])
    serial = Map.get_lazy(item, :serial, &Ulid.generate/0)

    g = %{
      id: "g_" <> serial,
      serial: serial,
      template_id: item.template_id,
      quantity: Map.get(item, :quantity, 1),
      attrs: Map.get(item, :attrs),
      x: x,
      y: y,
      owner: owner,
      protect_until: t + drop["lootProtectSeconds"] * 1000,
      expire_at: t + drop["groundItemSeconds"] * 1000
    }

    broadcast(s, "spawn", ground_payload(g))
    %{s | ground: Map.put(s.ground, g.id, g)}
  end

  defp expire_ground(s) do
    t = now(s)

    Enum.reduce(s.ground, s, fn
      {gid, %{expire_at: at}}, s when at <= t ->
        broadcast(s, "despawn", %{id: gid})
        %{s | ground: Map.delete(s.ground, gid), removed: [gid | s.removed]}

      _, s ->
        s
    end)
  end

  # ---------- Cổng (P2-M4) ----------

  # Vừa bước vào ô cổng (trước đó không đứng trên cổng): dừng lại, báo Session chủ chuyển map
  defp portal(s, id, before) do
    e = s.players[id]
    p = Maps.portal_at(s.map, e.x, e.y)

    if p && {e.x, e.y} != {before.x, before.y} && Maps.portal_at(s.map, before.x, before.y) != p do
      send(e.owner, {:map_portal, id, p})
      %{s | players: Map.put(s.players, id, %{e | path: [], progress: 0, state: "idle"})}
    else
      s
    end
  end

  # ---------- Buff hết hạn, hồi MP (P2-M3) ----------

  defp expire_buffs(s) do
    t = now(s)

    Enum.reduce(s.players, s, fn
      {id, %{buffs: buffs} = e}, s when map_size(buffs) > 0 ->
        case Engine.expire_buffs(buffs, t) do
          {_, false} ->
            s

          {kept, true} ->
            e = %{e | buffs: kept}
            notify_buffs(s, e)
            %{s | players: Map.put(s.players, id, e)}
        end

      _, s ->
        s
    end)
  end

  # `energy / energyDiv` MP mỗi giây, cộng dồn phần lẻ; đã chết hoặc đầy thì thôi
  defp regen_mp(s) do
    ms = s.regen_every * s.tick_ms

    Enum.reduce(s.players, s, fn
      {id, %{state: state, mp: mp, stats: %{mp_max: max}} = e}, s
      when state != "dead" and mp < max ->
        acc = e.mp_acc + Engine.mp_regen(e.stats.energy, ms)
        add = trunc(acc)
        e = %{e | mp: min(mp + add, max), mp_acc: acc - add}
        if add > 0, do: put_entity(s, id, e), else: %{s | players: Map.put(s.players, id, e)}

      _, s ->
        s
    end)
  end

  # ---------- Chết & hồi sinh người chơi (G11) ----------

  defp respawn_players(s) do
    delay = Config.get(["combat", "playerRespawnSeconds"]) * 1000
    t = now(s)

    Enum.reduce(s.players, s, fn
      {id, %{state: "dead", dead_at: at} = e}, s when at + delay <= t ->
        e = revive(s, e)
        broadcast(s, "despawn", %{id: e.id})
        broadcast(s, "spawn", spawn_payload(e))
        %{s | players: Map.put(s.players, id, e)}

      _, s ->
        s
    end)
  end

  defp revive(s, e) do
    {x, y} = s.map.player_spawn

    %{
      e
      | x: x,
        y: y,
        hp: e.stats.hp_max,
        mp: e.stats.mp_max,
        state: "idle",
        path: [],
        progress: 0,
        dead_at: nil,
        last_combat_at: nil
    }
  end

  defp pickup_range(e, g) do
    if Pathfinding.chebyshev({e.x, e.y}, {g.x, g.y}) <=
         Config.get(["interaction", "pickupRange"]),
       do: :ok,
       else: {:error, "OUT_OF_RANGE"}
  end

  # trong lootProtectSeconds chỉ chủ (người gây nhiều sát thương nhất) được nhặt (G13)
  defp loot_owner(s, g, id) do
    if g.owner == id or now(s) >= g.protect_until, do: :ok, else: {:error, "NOT_OWNER"}
  end

  defp combat_remaining(s, %{last_combat_at: nil}) when is_map(s), do: 0

  defp combat_remaining(s, e) do
    window = Config.get(["session", "logoutInCombatSeconds"]) * 1000
    max(e.last_combat_at + window - now(s), 0)
  end

  # ---------- Snapshot & sự kiện ----------

  defp snapshot(s) do
    if MapSet.size(s.dirty) == 0 and s.removed == [], do: s, else: send_snapshot(s)
  end

  defp send_snapshot(s) do
    entities =
      for id <- s.dirty, e = entity(s, id) do
        base = %{id: e.id, x: e.x, y: e.y, hp: e.hp, state: e.state}

        # người chơi: kèm MP (thanh MP của chính mình đổi khi dùng skill / hồi, P2-M3)
        if e.kind == :player, do: Map.put(base, :mp, e.mp), else: base
      end

    broadcast(s, "snapshot", %{
      t: System.os_time(:millisecond),
      entities: entities,
      removed: s.removed
    })

    %{s | dirty: MapSet.new(), removed: []}
  end

  defp entity(s, "p_" <> cid), do: s.players[cid]
  defp entity(s, id), do: s.monsters[id]

  defp remove_player(s, id) do
    e = s.players[id]
    broadcast(s, "despawn", %{id: e.id})

    %{
      s
      | players: Map.delete(s.players, id),
        dirty: MapSet.delete(s.dirty, e.id),
        removed: [e.id | s.removed]
    }
  end

  defp valid_coords(e, x, y) do
    if is_integer(x) and is_integer(y) do
      :ok
    else
      Logger.warning("move_to sai kiểu từ #{e.id}: #{inspect({x, y})}")
      {:error, "INVALID_TARGET"}
    end
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
          # tên hiển thị = tên cửa hàng (shop.json), P2-M4
          name: (Data.shop(n.id) || %{})["name"] || n.id,
          level: nil,
          templateId: n.id
        }
      end

    npcs ++
      Enum.map(Map.values(s.players), &spawn_payload/1) ++
      Enum.map(Map.values(s.monsters), &spawn_payload/1) ++
      Enum.map(Map.values(s.ground), &ground_payload/1)
  end

  defp spawn_payload(%{kind: :player} = e) do
    %{
      id: e.id,
      kind: "player",
      x: e.x,
      y: e.y,
      hp: e.hp,
      maxHp: e.stats.hp_max,
      state: e.state,
      name: e.name,
      level: e.level,
      # sprite theo class (Phase 2)
      class: e.class
    }
  end

  defp spawn_payload(%{kind: :monster} = m) do
    %{
      id: m.id,
      kind: "monster",
      x: m.x,
      y: m.y,
      hp: m.hp,
      maxHp: m.hp_max,
      state: m.state,
      name: m.tpl["name"],
      level: m.tpl["level"],
      templateId: m.template_id
    }
  end

  defp ground_payload(g) do
    %{
      id: g.id,
      kind: "item",
      x: g.x,
      y: g.y,
      hp: nil,
      maxHp: nil,
      state: "idle",
      name: g.template_id,
      level: nil,
      templateId: g.template_id
    }
  end

  defp broadcast(s, event, payload),
    do: Phoenix.PubSub.broadcast(Mu.PubSub, s.topic, {:map_event, event, payload})
end

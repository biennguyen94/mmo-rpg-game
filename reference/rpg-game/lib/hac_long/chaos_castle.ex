defmodule HacLong.ChaosCastle do
  @moduledoc """
  Hỗn Chiến Thành (kiểu MU Chaos Castle, DECISIONS B-19; số ở `RULES.chaos_castle`).

  - **Lịch** (giờ Việt Nam, hàm thuần `phase_at/1`): mỗi `every_hours` giờ, lệch `offset_minutes` phút (1h30, 3h30 …):
    `entry_minutes` phút cho vào (`:entry`), rồi `run_minutes` phút hỗn chiến (`:fight`).
  - **Phòng** (DECISIONS "Sự kiện đánh chung theo phòng", `HacLong.Game.EventRooms`): người vào theo số lần chuyển sinh
    vào phòng của mình, mỗi phòng một bản đồ (`map_id/1`: phòng 0 là `map`, phòng b là `map_b`, sinh bằng
    `scripts/gen_cc_rooms.py`). Các phòng chạy cùng lịch nhưng thắng thua, quái, thưởng tính riêng từng phòng; quái của
    phòng mạnh theo mốc chuyển sinh của phòng (`room_k/1`, `Engine.scale_event/2`).
  - **Vào** (`enter/2`, gọi từ Session khi đứng cạnh Người Gác Tháp): từ `min_level`, tốn 1 vé `ticket`; đứng vào một ô
    trống của bản đồ phòng mình (bản đồ chung, `event: "chaos_castle"`).
  - **Bắt đầu hỗn chiến:** mỗi phòng có người thả `max(min_monsters, total − số người phòng đó)` quái cấp quanh cấp
    trung bình người trong phòng; được đồ sát nhau (`HacLong.Slay`, không mất vàng / tên đỏ trong thành).
  - **Bị loại:** gục (quái hoặc người), đổi bản đồ, thoát game (`HacLong.World.leave/2` gọi `out/1`). Gục thì về Làng,
    không mất vàng.
  - **Kết thúc (từng phòng):** còn đúng 1 người và hết quái → người đó thắng (`reward.winner`); hết giờ → người còn trụ nhận
    `reward.survivor`; mỗi người hạ được thêm `reward.per_player_kill` vàng mỗi người. Thưởng gửi **qua thư**. Người còn
    trong thành được đưa về Làng, quái còn lại biến mất.

  Trạng thái công khai giữ ở ETS (`status/0`, đọc không cần gọi tiến trình) để Session / `Engine.view` đọc được mà không
  khóa chéo; tiến trình này không bao giờ gọi đồng bộ vào Session (đưa người về Làng, gửi thư chạy trong Task).
  `config :hac_long, :chaos_castle, auto: false` (test) thì không tự chạy theo lịch; dùng `open_now/0`, `start_fight/0`.
  """
  use GenServer
  require Logger

  alias HacLong.{Chat, Mailbox, World}
  alias HacLong.Game.{Data, Engine, EventRooms, Session}
  alias HacLong.World.{MapServer, Maps}

  @r Data.rules().chaos_castle
  @utc_offset 7 * 3600
  @table :chaos_castle

  def rules, do: @r
  def ticket, do: @r.ticket

  @doc "Bản đồ của phòng `b` (phòng 0 là bản đồ gốc `RULES.chaos_castle.map`)."
  def map_id(b \\ 0), do: if(b == 0, do: @r.map, else: "#{@r.map}_#{b}")

  @doc "Mọi bản đồ phòng."
  def map_ids, do: for(b <- 0..(EventRooms.count() - 1), do: map_id(b))

  @doc "Bản đồ `id` là một phòng Hỗn Chiến Thành."
  def map?(id), do: id in map_ids()

  @doc "Phòng của bản đồ `id` (nil nếu không phải phòng Hỗn Chiến Thành)."
  def room_of(id), do: Enum.find_index(map_ids(), &(&1 == id))

  @doc "Mốc chuyển sinh quái phòng của bản đồ `id` mạnh theo."
  def room_k(id), do: EventRooms.k(room_of(id) || 0)

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  # ---------- Lịch (hàm thuần) ----------

  @doc """
  Pha theo lịch ở thời điểm `now`: `{:entry, opens_at, starts_at, ends_at}`, `{:fight, opens_at, starts_at, ends_at}`
  hoặc `{:idle, next_opens_at}` (unix).
  """
  def phase_at(now \\ DateTime.utc_now()) do
    local = DateTime.to_unix(now) + @utc_offset - @r.offset_minutes * 60
    step = @r.every_hours * 3600
    start = div(local, step) * step
    opens = start - @utc_offset + @r.offset_minutes * 60
    starts = opens + @r.entry_minutes * 60
    ends = starts + @r.run_minutes * 60
    t = DateTime.to_unix(now)

    cond do
      t < starts -> {:entry, opens, starts, ends}
      t < ends -> {:fight, opens, starts, ends}
      true -> {:idle, opens + step}
    end
  end

  # ---------- Đọc trạng thái (không gọi tiến trình) ----------

  @doc "Trạng thái công khai: `%{phase, starts_at, ends_at, next_at, players, alive, monsters}`."
  def status do
    case :ets.whereis(@table) do
      :undefined -> idle_status()
      _ -> with [{:status, s}] <- :ets.lookup(@table, :status), do: s, else: (_ -> idle_status())
    end
  end

  def fighting?, do: status().phase == "fight"

  @doc "Người `uid` còn trụ trong lượt đang chạy."
  def alive?(uid) do
    case :ets.whereis(@table) do
      :undefined ->
        false

      _ ->
        case :ets.lookup(@table, :alive) do
          [{:alive, a}] -> MapSet.member?(a, uid)
          _ -> false
        end
    end
  end

  @doc "Thông tin cho giao diện (thẻ Người Gác Tháp, dải trên bản đồ)."
  def view(p) do
    Map.merge(status(), %{
      price: @r.ticket_price,
      min_level: @r.min_level,
      entry_minutes: @r.entry_minutes,
      run_minutes: @r.run_minutes,
      tickets: Map.get(p.inv, @r.ticket, 0),
      inside: p[:pos] != nil and map?(p.pos.map),
      # phòng của người này (theo số lần chuyển sinh)
      room: EventRooms.label(EventRooms.band(Map.get(p, :rebirths)))
    })
  end

  defp idle_status do
    {_, next} =
      case phase_at() do
        {:idle, n} -> {:idle, n}
        {_, opens, _, _} -> {:idle, opens + @r.every_hours * 3600}
      end

    %{
      phase: "idle",
      starts_at: nil,
      ends_at: nil,
      next_at: next,
      players: 0,
      alive: 0,
      monsters: 0
    }
  end

  # ---------- Vé ----------

  @doc "Mua 1 vé bằng vàng."
  def buy_ticket(p) do
    price = @r.ticket_price

    if p.gold < price,
      do: {%{ok: false, msg: "Cần #{price} vàng để mua vé."}, p},
      else:
        {%{ok: true, msg: "Đã mua #{Data.item(@r.ticket).name} (−#{price} vàng)."},
         %{p | gold: p.gold - price} |> Engine.add_item(@r.ticket)}
  end

  @doc "Tỉ lệ quái `m` rơi vé (quái thường cấp ≥ `ticket_drop.min_level`)."
  def ticket_chance(m) do
    d = @r.ticket_drop
    if m[:world] || m[:pvp] || m[:tower] || m.level < d.min_level, do: 0, else: d.chance
  end

  # ---------- Vào ----------

  @doc "Vào thành (Session gọi, `uid` là người chơi). Trả `{kết_quả, nhân_vật}`."
  def enter(p, uid) do
    cond do
      World.near_npc(p, ["tower"]) == nil ->
        {%{ok: false, msg: "Hãy đến gặp Người Gác Tháp ở Làng."}, p}

      p.battle ->
        {%{ok: false, msg: "Đang trong trận đấu."}, p}

      p.level < @r.min_level ->
        {%{ok: false, msg: "Cần đạt cấp #{@r.min_level} mới vào được Hỗn Chiến Thành."}, p}

      Map.get(p.inv, @r.ticket, 0) < 1 ->
        {%{ok: false, msg: "Cần 1 #{Data.item(@r.ticket).name}."}, p}

      true ->
        room = EventRooms.band(Map.get(p, :rebirths))

        case GenServer.call(__MODULE__, {:join, uid, p.name, p.level, room}) do
          {:ok, pos} ->
            p = p |> Engine.take_item(@r.ticket) |> then(&World.warp(&1, uid, pos))

            {%{
               ok: true,
               msg:
                 "⚔ Vào Hỗn Chiến Thành (phòng #{EventRooms.label(room)})! Chờ hết giờ vào rồi hỗn chiến: trụ lại cuối cùng để thắng."
             }, p}

          {:error, msg} ->
            {%{ok: false, msg: msg}, p}
        end
    end
  end

  # ---------- Sự kiện từ trò chơi (cast, không khóa) ----------

  @doc "Người `uid` bị loại (gục, đổi bản đồ, thoát game)."
  def out(uid), do: if(Process.whereis(__MODULE__), do: GenServer.cast(__MODULE__, {:out, uid}))

  @doc "Người `uid` vừa hạ một quái (`:monster`) hoặc một người (`:player`) trong thành."
  def kill(uid, what),
    do: if(Process.whereis(__MODULE__), do: GenServer.cast(__MODULE__, {:kill, uid, what}))

  @doc "Quản trị viên mở ngay một lượt (cho vào `entry_minutes` phút rồi hỗn chiến)."
  def open_now, do: GenServer.call(__MODULE__, :open_now)

  @doc "Bắt đầu hỗn chiến ngay (test)."
  def start_fight, do: GenServer.call(__MODULE__, :start_fight)

  @doc "Kết thúc ngay (test)."
  def finish_now, do: GenServer.call(__MODULE__, :finish_now)

  # ---------- Máy chủ ----------

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])

    s = %{
      phase: :idle,
      starts_at: nil,
      ends_at: nil,
      players: %{},
      alive: MapSet.new(),
      # phòng → %{monsters: số quái còn lại, open: còn đang hỗn chiến}
      rooms: %{},
      timer: nil
    }

    {:ok, s |> publish() |> schedule()}
  end

  @impl true
  def handle_call({:join, uid, name, level, room}, _from, s) do
    cond do
      s.phase != :entry ->
        {:reply, {:error, "Hỗn Chiến Thành chưa mở cửa (hoặc đã hết giờ vào)."}, s}

      Map.has_key?(s.players, uid) ->
        {:reply, {:error, "Bạn đã vào lượt này rồi."}, s}

      true ->
        pos = free_tile(room)

        s = %{
          s
          | players:
              Map.put(s.players, uid, %{name: name, level: level, room: room, kills: 0, pkills: 0})
        }

        s = %{s | alive: MapSet.put(s.alive, uid)}
        {:reply, {:ok, pos}, publish(s)}
    end
  end

  def handle_call(:open_now, _from, s) do
    t = System.os_time(:second)
    s = cancel(s)

    s = %{
      s
      | phase: :entry,
        starts_at: t + @r.entry_minutes * 60,
        ends_at: t + (@r.entry_minutes + @r.run_minutes) * 60
    }

    s = %{s | players: %{}, alive: MapSet.new(), rooms: %{}}
    announce_open(s)

    {:reply, {:ok, %{starts_at: s.starts_at, ends_at: s.ends_at}},
     s |> publish() |> arm(s.starts_at, :fight)}
  end

  def handle_call(:start_fight, _from, s), do: {:reply, :ok, begin_fight(cancel(s))}
  def handle_call(:finish_now, _from, s), do: {:reply, :ok, finish(cancel(s), :time)}

  @impl true
  def handle_cast({:out, uid}, s) do
    if MapSet.member?(s.alive, uid),
      do:
        {:noreply,
         %{s | alive: MapSet.delete(s.alive, uid)} |> publish() |> check_end(s.players[uid].room)},
      else: {:noreply, s}
  end

  def handle_cast({:kill, uid, what}, s) do
    s =
      case s.players[uid] do
        nil ->
          s

        pl ->
          pl =
            if what == :player,
              do: %{pl | pkills: pl.pkills + 1},
              else: %{pl | kills: pl.kills + 1}

          s = put_in(s.players[uid], pl)

          if what == :monster and s.rooms[pl.room],
            do: update_in(s.rooms[pl.room].monsters, &max(0, &1 - 1)),
            else: s
      end

    room = s.players[uid] && s.players[uid].room
    {:noreply, s |> publish() |> check_end(room)}
  end

  @impl true
  def handle_info(:tick, s) do
    s = %{s | timer: nil}

    case phase_at() do
      {:entry, _o, starts, ends} when s.phase == :idle ->
        s = %{
          s
          | phase: :entry,
            starts_at: starts,
            ends_at: ends,
            players: %{},
            alive: MapSet.new(),
            rooms: %{}
        }

        announce_open(s)
        {:noreply, s |> publish() |> arm(starts, :fight)}

      _ ->
        {:noreply, schedule(s)}
    end
  end

  def handle_info(:fight, s), do: {:noreply, begin_fight(%{s | timer: nil})}
  def handle_info(:finish, s), do: {:noreply, finish(%{s | timer: nil}, :time)}

  # ---------- Diễn biến ----------

  defp begin_fight(%{phase: :entry} = s) do
    if MapSet.size(s.alive) == 0 do
      Chat.system("⚔ Hỗn Chiến Thành không có ai vào, lượt này hủy.")
      s |> reset() |> publish() |> schedule()
    else
      # mỗi phòng có người: quái theo số người và cấp trung bình của phòng đó
      rooms =
        for room <- s.alive |> Enum.map(&s.players[&1].room) |> Enum.uniq(), into: %{} do
          n = max(@r.min_monsters, @r.total - length(alive_in(s, room)))
          {room, %{monsters: spawn_monsters(n, avg_level(s, room), room), open: true}}
        end

      spawned = rooms |> Map.values() |> Enum.map(& &1.monsters) |> Enum.sum()

      Chat.system(
        "⚔ Hỗn Chiến Thành bắt đầu: #{MapSet.size(s.alive)} người ở #{map_size(rooms)} phòng, #{spawned} quái. Trụ lại cuối cùng để thắng!"
      )

      s = %{s | phase: :fight, rooms: rooms}
      s |> publish() |> arm(s.ends_at, :finish)
    end
  end

  defp begin_fight(s), do: s

  defp alive_in(s, room), do: Enum.filter(s.alive, &(s.players[&1].room == room))

  # một phòng xong (hết người hoặc còn 1 người và hết quái); mọi phòng xong thì cả lượt kết thúc
  defp check_end(%{phase: :fight} = s, room) do
    r = s.rooms[room]
    alive = if r && r.open, do: alive_in(s, room), else: nil

    s =
      cond do
        alive == nil -> s
        alive == [] -> finish_room(s, room, :empty)
        length(alive) == 1 and r.monsters == 0 -> finish_room(s, room, :winner)
        true -> s
      end

    if Enum.any?(s.rooms, fn {_, r} -> r.open end),
      do: s,
      else: s |> cancel() |> reset() |> publish() |> schedule()
  end

  defp check_end(s, _room), do: s

  defp finish(%{phase: :idle} = s, _why), do: s

  # hết giờ / không ai vào: kết thúc mọi phòng còn mở
  defp finish(s, why) do
    s =
      s.rooms
      |> Enum.filter(fn {_, r} -> r.open end)
      |> Enum.reduce(s, fn {room, _}, s -> finish_room(s, room, why) end)

    if s.phase == :fight and s.rooms == %{} and why == :time,
      do: Chat.system("⚔ Hỗn Chiến Thành hết giờ.")

    s |> reset() |> publish() |> schedule()
  end

  defp finish_room(s, room, why) do
    alive = alive_in(s, room)
    winner = if why == :winner, do: List.first(alive)
    survivors = if why == :time, do: alive, else: []
    players = Map.filter(s.players, fn {_, pl} -> pl.room == room end)
    label = EventRooms.label(room)

    text =
      case why do
        :winner -> "🏆 #{players[winner].name} thắng Hỗn Chiến Thành (#{label})!"
        :time -> "⚔ Hỗn Chiến Thành (#{label}) hết giờ: #{length(survivors)} người trụ lại."
        :empty -> "⚔ Hỗn Chiến Thành (#{label}) kết thúc: không còn ai trụ lại."
      end

    if s.phase == :fight or why != :empty, do: Chat.system(text)

    Task.start(fn ->
      safe(fn -> MapServer.clear_monsters(map_id(room)) end)
      Enum.each(alive, &send_home/1)
      Enum.each(players, fn {uid, pl} -> reward(uid, pl, uid == winner, uid in survivors) end)
    end)

    %{s | alive: MapSet.difference(s.alive, MapSet.new(alive))}
    |> put_in([:rooms, room], %{monsters: 0, open: false})
  end

  defp reset(s),
    do: %{
      s
      | phase: :idle,
        starts_at: nil,
        ends_at: nil,
        players: %{},
        alive: MapSet.new(),
        rooms: %{}
    }

  # thưởng gửi qua thư: thắng / trụ đến hết giờ + vàng theo số người hạ được
  defp reward(uid, pl, winner?, survivor?) do
    base =
      cond do
        winner? -> @r.reward.winner
        survivor? -> @r.reward.survivor
        true -> %{gold: 0, items: %{}}
      end

    gold = base.gold + pl.pkills * @r.reward.per_player_kill
    items = Map.new(base.items, fn {k, v} -> {to_string(k), v} end)

    if gold > 0 or items != %{} do
      body =
        cond do
          winner? -> "Bạn là người trụ lại cuối cùng của Hỗn Chiến Thành!"
          survivor? -> "Bạn trụ được đến hết giờ ở Hỗn Chiến Thành."
          true -> "Thưởng hạ người trong Hỗn Chiến Thành."
        end

      safe(fn ->
        Mailbox.send(uid, %{
          subject: "⚔ Thưởng Hỗn Chiến Thành",
          body: "#{body} Hạ #{pl.pkills} người, #{pl.kills} quái.",
          gold: gold,
          items: items
        })
      end)
    end
  end

  # đưa người còn trong thành về Làng (chạy trong Session của họ)
  defp send_home(uid) do
    safe(fn ->
      if Session.online?(uid) do
        Session.admin(uid, fn p ->
          if map?(p.pos.map) and p.battle == nil,
            do:
              {:ok, World.warp(p, uid, World.village_spawn()),
               "Hỗn Chiến Thành kết thúc, bạn được đưa về Làng."},
            else: {:error, "không ở trong thành"}
        end)
      end
    end)
  end

  defp avg_level(s, room) do
    lv = for {_, p} <- s.players, p.room == room, do: p.level
    if lv == [], do: @r.min_level, else: round(Enum.sum(lv) / length(lv))
  end

  # quái cấp trong khoảng cấp trung bình ± level_spread (quái vùng và bản đồ phụ, không lấy trùm)
  defp spawn_monsters(n, level, room) do
    pool =
      (Enum.flat_map(Data.zones(), & &1.monsters) ++ Data.side_monsters())
      |> Enum.filter(&(abs(&1.level - level) <= @r.level_spread))
      |> Enum.map(& &1.id)

    pool =
      if pool == [],
        do: [Data.side_monsters() |> Enum.min_by(&abs(&1.level - level)) |> Map.get(:id)],
        else: pool

    taken = MapSet.new()

    {count, _} =
      Enum.reduce(1..n, {0, taken}, fn _, {c, taken} ->
        case free_tile_except(room, taken) do
          nil ->
            {c, taken}

          {x, y} = pos ->
            kind = Enum.random(pool)

            case safe(fn -> MapServer.put_monster(map_id(room), kind, pos) end) do
              %{} -> {c + 1, MapSet.put(taken, {x, y})}
              _ -> {c, MapSet.put(taken, {x, y})}
            end
        end
      end)

    count
  end

  defp tiles(room) do
    m = Maps.get(map_id(room))
    for y <- 0..(m.height - 1), x <- 0..(m.width - 1), Maps.walkable?(m, x, y), do: {x, y}
  end

  defp free_tile(room) do
    {x, y} = Enum.random(tiles(room))
    %{map: map_id(room), x: x, y: y}
  end

  defp free_tile_except(room, taken) do
    case Enum.reject(tiles(room), &MapSet.member?(taken, &1)) do
      [] -> nil
      l -> Enum.random(l)
    end
  end

  defp announce_open(s) do
    mins = div(s.starts_at - System.os_time(:second) + 59, 60)

    Chat.system(
      "⚔ Hỗn Chiến Thành mở cửa: gặp Người Gác Tháp ở Làng trong #{mins} phút (cấp #{@r.min_level}+, cần #{Data.item(@r.ticket).name})."
    )
  end

  defp publish(s) do
    next =
      case phase_at() do
        {:idle, n} -> n
        {_, opens, _, _} -> opens + @r.every_hours * 3600
      end

    # người còn trụ (`alive?/1`; trước đây không ghi nên luôn coi là đã bị loại)
    :ets.insert(@table, {:alive, s.alive})

    :ets.insert(
      @table,
      {:status,
       %{
         phase: to_string(s.phase),
         starts_at: s.starts_at,
         ends_at: s.ends_at,
         next_at: next,
         players: map_size(s.players),
         alive: MapSet.size(s.alive),
         monsters: s.rooms |> Map.values() |> Enum.map(& &1.monsters) |> Enum.sum()
       }}
    )

    s
  end

  # hẹn lần kiểm tra lịch tiếp theo (tắt khi `auto: false`)
  defp schedule(s) do
    if Application.get_env(:hac_long, :chaos_castle, [])[:auto] == false do
      s
    else
      at =
        case phase_at() do
          {:idle, n} -> n
          {:entry, _, _, _} -> System.os_time(:second)
          {:fight, _o, _st, ends} -> ends
        end

      arm(cancel(s), at, :tick)
    end
  end

  defp arm(s, at, msg) do
    s = cancel(s)
    ms = max(0, at - System.os_time(:second)) * 1000
    %{s | timer: Process.send_after(self(), msg, ms)}
  end

  defp cancel(%{timer: nil} = s), do: s

  defp cancel(%{timer: t} = s) do
    Process.cancel_timer(t)
    %{s | timer: nil}
  end

  defp safe(f) do
    f.()
  rescue
    e ->
      Logger.error("Hỗn Chiến Thành: " <> Exception.message(e))
      nil
  catch
    :exit, _ -> nil
  end
end

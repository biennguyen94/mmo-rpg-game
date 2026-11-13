defmodule HacLong.BloodMoon do
  @moduledoc """
  Huyết Nguyệt ở Pháp Trường (DECISIONS "Pháp Trường Huyết Nguyệt", Phase 8). Số ở `RULES.blood_moon`.

  - Bản đồ `map` không có quái; ngày thường là vùng an toàn (`HacLong.Slay.check/2`).
  - Quản trị mở ngay (`open_now/1`, 1..`minutes_max` phút) hoặc lịch hằng ngày `daily_at` ("HH:MM", giờ Việt Nam; quản
    trị đổi bằng `set_daily/1`, lưu ở dòng `admin_log` op `blood_moon_daily` mới nhất): báo trước `warn_min` phút rồi mở
    `minutes` phút. Lúc mở: đồ sát tự do trên bản đồ, gục không mất vàng / không tên đỏ, về Làng, `relock_s` giây sau
    mới vào lại (`locked_s/1`).
  - Hạ người (`kill/4`, gọi trong lúc chốt trận đồ sát): +1 điểm; cơ hội rơi một viên ngọc (hàm thuần `drop_chance/4`).
    Bot không rơi / không làm rơi ngọc, chỉ tính điểm.
  - Hết giờ (`close_now/0` hoặc hẹn giờ): bảng xếp hạng; `top_rewards` gửi thư cho người thật đứng đầu (bot không nhận).
  - Quản trị gọi mọi bot vào (`summon_bots/0`): bot đi tìm người gần nhất để đồ sát (`HacLong.Bots.Bot`); `recall_bots/0`
    hoặc hết giờ thì bot về Làng.

  Trạng thái chỉ trong bộ nhớ (cờ mở ở `:persistent_term` cho `open?/0` gọi từ Session / Slay). Client nhận
  `{:blood_moon, public}` qua `topic/0` (kênh đẩy `blood_moon`). `config :hac_long, :blood_moon, auto: false` (test): không
  tự hẹn lịch hằng ngày.
  """
  use GenServer
  require Logger

  alias HacLong.{Bots, Chat, Mailbox}
  alias HacLong.Game.{Data, Session}
  alias HacLong.World.Maps

  @topic "blood_moon"
  @open_key {__MODULE__, :open}
  @tz_offset_s 7 * 3600

  def topic, do: @topic
  def rules, do: Data.rules().blood_moon
  def map_id, do: rules().map

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Huyết Nguyệt đang mở (đồ sát tự do trên Pháp Trường)."
  def open?, do: :persistent_term.get(@open_key, false)

  @doc "Đang ở Pháp Trường lúc Huyết Nguyệt mở (gục không mất vàng, không tên đỏ)."
  def active_at?(map), do: map == map_id() and open?()

  @doc "Số giây còn phải chờ mới vào lại được Pháp Trường (vừa gục trong sự kiện)."
  def locked_s(uid), do: call({:locked_s, uid}, 0)

  @doc "Trạng thái cho client (xem `public/1`)."
  def public, do: call(:public, public(initial()))

  @doc "Mở ngay `minutes` phút (mặc định `RULES.blood_moon.minutes`). Đang mở thì báo lỗi."
  def open_now(minutes \\ nil), do: GenServer.call(__MODULE__, {:open, minutes})

  @doc "Đóng sớm: chốt bảng xếp hạng, gửi quà."
  def close_now, do: GenServer.call(__MODULE__, :close)

  @doc "Đặt lịch hằng ngày \"HH:MM\" hoặc nil (tắt). Người gọi đã ghi `admin_log`."
  def set_daily(at), do: GenServer.call(__MODULE__, {:daily, at})

  @doc """
  Đặt quà top (quản trị): danh sách đúng `length(RULES.blood_moon.top_rewards)` phần tử, mỗi phần tử
  `%{mã ngọc => số}` (ngọc trong `jewels`, 0..`reward_max`), hoặc nil để về mặc định của RULES. Người gọi đã ghi
  `admin_log` (op `blood_moon_rewards`, `params.rewards`); dòng mới nhất là mức đang dùng.
  """
  def set_rewards(rewards), do: GenServer.call(__MODULE__, {:rewards, rewards})

  @doc "Quà top mặc định (RULES), khóa chuỗi."
  def default_rewards,
    do: Enum.map(rules().top_rewards, &Map.new(&1, fn {k, v} -> {to_string(k), v} end))

  @doc """
  Chuẩn hóa / kiểm quà top (hàm thuần): `{:ok, [%{mã => số}]}` (đủ mọi ngọc, thiếu là 0) hoặc `{:error, lý do}`.
  """
  def check_rewards(list, r \\ rules()) do
    max = r.reward_max
    jewels = Enum.map(r.jewels, &to_string/1)

    ok? = fn m ->
      is_map(m) and
        Enum.all?(m, fn {k, v} -> to_string(k) in jewels and is_integer(v) and v in 0..max end)
    end

    if is_list(list) and length(list) == length(r.top_rewards) and Enum.all?(list, ok?),
      do:
        {:ok,
         Enum.map(list, fn m ->
           Map.new(jewels, &{&1, Map.get(m, &1) || Map.get(m, String.to_atom(&1)) || 0})
         end)},
      else: {:error, "Quà mỗi hạng: số nguyên 0..#{max} cho từng loại ngọc."}
  end

  @doc "Gọi mọi bot đang chạy vào Pháp Trường (chỉ lúc đang mở). Trả số bot."
  def summon_bots, do: GenServer.call(__MODULE__, :summon_bots)

  @doc "Cho bot đã gọi về Làng. Trả số bot."
  def recall_bots, do: GenServer.call(__MODULE__, :recall_bots)

  @doc "Bot `uid` đang được gọi đồ sát ở Pháp Trường (Huyết Nguyệt đang mở)."
  def bot_on?(uid), do: open?() and call({:bot_on, uid}, false)

  @doc """
  Chốt một mạng trong sự kiện (Slay gọi khi `winner` hạ `loser`, cả hai đang ở Pháp Trường lúc mở): +1 điểm cho
  `winner`, khóa `loser` vào lại `relock_s` giây, tung cơ hội rơi ngọc. `rw` / `rl`: số lần chuyển sinh. Trả mã ngọc
  rơi được hoặc nil.
  """
  def kill(winner, loser, %{name: wn, rebirths: rw}, %{name: ln, rebirths: rl}) do
    GenServer.call(__MODULE__, {:kill, winner, loser, wn, ln, rw || 0, rl || 0})
  catch
    # sự kiện lỗi / không chạy: trận vẫn chốt như thường, chỉ không tính mạng
    :exit, _ -> nil
  end

  @doc """
  Cơ hội rơi ngọc khi hạ một người (hàm thuần): `drop_pct` × hệ số chuyển sinh (người gục nhiều hơn thì cao hơn, chặn
  [0, rebirth_max]) × `repeat_decay`^(số lần đã hạ người này trước đó). `rk` / `rv`: chuyển sinh người hạ / người gục.
  """
  def drop_chance(rk, rv, before, r \\ rules()) do
    reb = (1 + r.rebirth_step * (rv - rk)) |> max(0.0) |> min(r.rebirth_max * 1.0)
    r.drop_pct * reb * :math.pow(r.repeat_decay, before)
  end

  @doc """
  Bảng xếp hạng (hàm thuần): `[%{uid, name, kills, bot}]` theo số mạng giảm dần, bằng nhau thì ai đạt trước đứng trên
  (`at`: thứ tự đạt số mạng đó).
  """
  def ranking(score) do
    score
    |> Enum.map(fn {uid, e} -> Map.put(e, :uid, uid) end)
    |> Enum.sort_by(&{-&1.kills, &1.at})
  end

  @doc "Người nhận quà (hàm thuần): người thật có ≥ `min_kills` mạng, theo thứ tự xếp hạng, ghép với `top_rewards`."
  def winners(rank, r \\ rules()) do
    rewards = r[:rewards] || r.top_rewards

    rank
    |> Enum.reject(&(&1.bot or &1.kills < r.min_kills))
    |> Enum.zip(rewards)
  end

  @doc false
  # test: về trạng thái ban đầu (đóng, không gửi quà); `drop`: ép tỉ lệ rơi ngọc (nil: theo RULES)
  def reset(drop \\ nil), do: GenServer.call(__MODULE__, {:reset, drop})

  defp call(msg, default) do
    case GenServer.whereis(__MODULE__) do
      nil -> default
      pid -> GenServer.call(pid, msg)
    end
  catch
    :exit, _ -> default
  end

  # ---------- GenServer ----------

  defp initial,
    do: %{
      open: false,
      until: nil,
      ends: nil,
      warn: nil,
      score: %{},
      seq: 0,
      pairs: %{},
      drops: 0,
      locked: %{},
      bots: MapSet.new(),
      daily: nil,
      daily_ref: nil,
      last: [],
      drop: nil,
      rewards: nil
    }

  @impl true
  def init(:ok) do
    :persistent_term.put(@open_key, false)
    s = %{initial() | daily: load_daily(), rewards: load_rewards()}
    s = if auto?(), do: schedule_daily(s), else: s
    {:ok, s}
  end

  defp auto?, do: Application.get_env(:hac_long, :blood_moon, [])[:auto] != false

  @impl true
  def handle_call(:public, _from, s), do: {:reply, public(s), s}

  def handle_call({:reset, drop}, _from, s) do
    :persistent_term.put(@open_key, false)

    {:reply, :ok,
     %{initial() | daily: s.daily, daily_ref: s.daily_ref, drop: drop, rewards: default_rewards()}}
  end

  def handle_call({:locked_s, uid}, _from, s),
    do: {:reply, max(0, ceil(((s.locked[uid] || 0) - now()) / 1000)), s}

  def handle_call({:bot_on, uid}, _from, s), do: {:reply, MapSet.member?(s.bots, uid), s}

  def handle_call({:open, _}, _from, %{open: true} = s),
    do: {:reply, {:error, "Huyết Nguyệt đang mở rồi."}, s}

  def handle_call({:open, minutes}, _from, s) do
    mins = minutes || rules().minutes

    if is_integer(mins) and mins >= 1 and mins <= rules().minutes_max do
      s = open(s, mins)
      {:reply, {:ok, public(s)}, s}
    else
      {:reply, {:error, "Số phút phải từ 1 tới #{rules().minutes_max}."}, s}
    end
  end

  def handle_call(:close, _from, %{open: false} = s),
    do: {:reply, {:error, "Huyết Nguyệt chưa mở."}, s}

  def handle_call(:close, _from, s) do
    s = close(s)
    {:reply, {:ok, public(s)}, s}
  end

  def handle_call({:daily, at}, _from, s) do
    if at == nil or valid_hm?(at) do
      if s.daily_ref, do: Process.cancel_timer(s.daily_ref)
      s = %{s | daily: at, daily_ref: nil}
      s = if auto?(), do: schedule_daily(s), else: s
      broadcast(s)
      {:reply, {:ok, public(s)}, s}
    else
      {:reply, {:error, "Giờ phải dạng HH:MM (vd 20:00)."}, s}
    end
  end

  def handle_call({:rewards, nil}, _from, s) do
    s = %{s | rewards: default_rewards()}
    broadcast(s)
    {:reply, {:ok, public(s)}, s}
  end

  def handle_call({:rewards, list}, _from, s) do
    case check_rewards(list) do
      {:ok, rw} ->
        s = %{s | rewards: rw}
        broadcast(s)
        {:reply, {:ok, public(s)}, s}

      err ->
        {:reply, err, s}
    end
  end

  def handle_call(:summon_bots, _from, %{open: false} = s),
    do: {:reply, {:error, "Mở Huyết Nguyệt trước rồi mới gọi bot."}, s}

  def handle_call(:summon_bots, _from, s) do
    ids = Bots.user_ids() |> Enum.filter(&Session.online?/1)
    s = %{s | bots: MapSet.union(s.bots, MapSet.new(ids))}
    broadcast(s)
    {:reply, {:ok, length(ids)}, s}
  end

  def handle_call(:recall_bots, _from, s) do
    n = send_bots_home(s.bots)
    s = %{s | bots: MapSet.new()}
    broadcast(s)
    {:reply, {:ok, n}, s}
  end

  def handle_call({:kill, winner, loser, wn, ln, rw, rl}, _from, %{open: true} = s) do
    bot? = Bots.bot?(winner) or Bots.bot?(loser)
    before = Map.get(s.pairs, {winner, loser}, 0)

    jewel =
      if not bot? and :rand.uniform() < drop_chance(rw, rl, before, drop_rules(s)),
        do: Enum.random(rules().jewels)

    seq = s.seq + 1
    e = Map.get(s.score, winner, %{name: wn, kills: 0, bot: Bots.bot?(winner), at: 0})

    s = %{
      s
      | seq: seq,
        score: Map.put(s.score, winner, %{e | name: wn, kills: e.kills + 1, at: seq}),
        pairs: Map.put(s.pairs, {winner, loser}, before + 1),
        locked: Map.put(s.locked, loser, now() + rules().relock_s * 1000),
        drops: s.drops + if(jewel, do: 1, else: 0)
    }

    if jewel,
      do:
        Chat.system(
          "🩸 #{wn} hạ #{ln} ở Pháp Trường, nhặt được #{Data.item(jewel)[:name] || jewel}!"
        )

    broadcast(s)
    {:reply, jewel, s}
  end

  def handle_call({:kill, _w, _l, _wn, _ln, _rw, _rl}, _from, s), do: {:reply, nil, s}

  @impl true
  def handle_info({:end, ref}, %{ends: ref} = s), do: {:noreply, close(s)}
  def handle_info({:end, _}, s), do: {:noreply, s}

  def handle_info(:daily_warn, s) do
    Chat.system(
      "🩸 #{rules().warn_min} phút nữa Huyết Nguyệt mọc ở Pháp Trường (cổng phía nam Làng): #{rules().minutes} phút đồ sát tự do, hạ người có cơ hội rơi ngọc quý!"
    )

    s = %{s | warn: now() + rules().warn_min * 60_000}
    broadcast(s)
    {:noreply, s}
  end

  def handle_info(:daily_open, s) do
    s = if s.open, do: s, else: open(%{s | warn: nil}, rules().minutes)
    {:noreply, schedule_daily(%{s | daily_ref: nil})}
  end

  defp drop_rules(%{drop: nil}), do: rules()
  defp drop_rules(%{drop: d}), do: %{rules() | drop_pct: d}

  # ---------- mở / đóng ----------

  defp open(s, mins) do
    ref = make_ref()
    Process.send_after(self(), {:end, ref}, mins * 60_000)
    :persistent_term.put(@open_key, true)

    s = %{
      s
      | open: true,
        until: now() + mins * 60_000,
        ends: ref,
        warn: nil,
        score: %{},
        seq: 0,
        pairs: %{},
        drops: 0,
        locked: %{}
    }

    Chat.system(
      "🩸 Huyết Nguyệt đã mọc! Pháp Trường (cổng phía nam Làng) đồ sát tự do trong #{mins} phút. Gục không mất vàng, hạ người có cơ hội rơi ngọc quý; top 3 được ban ngọc."
    )

    broadcast(s)
    s
  end

  defp close(s) do
    :persistent_term.put(@open_key, false)
    rank = ranking(s.score)
    # hạng để toàn 0 ngọc: không có quà (không gửi thư, không xướng tên)
    gifts =
      rank
      |> winners(Map.put(rules(), :rewards, s.rewards))
      |> Enum.with_index(1)
      |> Enum.reject(fn {{_e, items}, _i} -> Enum.all?(items, fn {_, n} -> n == 0 end) end)

    for {{e, items}, i} <- gifts do
      Mailbox.send(e.uid, %{
        subject: "🩸 Huyết Nguyệt: hạng #{i}",
        body:
          "Bạn đứng hạng #{i} đêm Huyết Nguyệt ở Pháp Trường với #{e.kills} mạng. Quan Giám Trảm ban thưởng ngọc quý.",
        items: for({id, n} <- items, n > 0, into: %{}, do: {to_string(id), n})
      })
    end

    top =
      gifts
      |> Enum.map_join(", ", fn {{e, _}, i} -> "#{i}. #{e.name} (#{e.kills} mạng)" end)

    Chat.system(
      "🌕 Huyết Nguyệt đã lặn, Pháp Trường yên bình trở lại. " <>
        if(top == "",
          do: "Không ai đủ mạng để nhận thưởng.",
          else: "Được ban ngọc: #{top}. Quà đã gửi vào hộp thư."
        )
    )

    send_bots_home(s.bots)

    last = rank |> Enum.take(rules().top_n) |> Enum.map(&Map.take(&1, [:name, :kills, :bot]))
    s = %{s | open: false, until: nil, ends: nil, bots: MapSet.new(), last: last}
    broadcast(s)
    s
  rescue
    e ->
      Logger.error("Huyết Nguyệt đóng lỗi: " <> Exception.message(e))
      :persistent_term.put(@open_key, false)
      %{s | open: false, until: nil, ends: nil, bots: MapSet.new()}
  end

  # bot đang đồ sát dở thì để đánh xong (bot tự về Làng sau đó, `HacLong.Bots.Bot`)
  defp send_bots_home(bots) do
    bots
    |> Enum.filter(fn uid ->
      p = Session.get(uid)
      p != nil and p.pos.map == map_id() and not HacLong.Slay.slaying?(p)
    end)
    |> Enum.count(&match?({:ok, _}, Session.to_village(&1, "BLOOD_MOON")))
  end

  # ---------- lịch hằng ngày ----------

  defp schedule_daily(%{daily: nil} = s), do: s

  defp schedule_daily(%{daily: at} = s) do
    [h, m] = at |> String.split(":") |> Enum.map(&String.to_integer/1)
    day = 86_400_000
    local = rem(now() + @tz_offset_s * 1000, day)
    target = (h * 3600 + m * 60) * 1000
    delay = rem(target - local + day, day)
    delay = if delay < 1000, do: delay + day, else: delay
    warn = rules().warn_min * 60_000
    if delay > warn, do: Process.send_after(self(), :daily_warn, delay - warn)
    %{s | daily_ref: Process.send_after(self(), :daily_open, delay)}
  end

  defp valid_hm?(at) when is_binary(at) do
    case Regex.run(~r/^(\d{1,2}):(\d{2})$/, at) do
      [_, h, m] -> String.to_integer(h) < 24 and String.to_integer(m) < 60
      _ -> false
    end
  end

  defp valid_hm?(_), do: false

  defp load_daily do
    case HacLong.Admin.recent_op("blood_moon_daily", 1) do
      [%{params: %{"at" => at}}] -> if valid_hm?(at), do: at
      _ -> rules().daily_at
    end
  rescue
    _ -> rules().daily_at
  end

  # dòng admin_log hợp lệ mới nhất (lần lưu sai bị từ chối cũng ghi log nên bỏ qua): `reset` → mặc định
  defp load_rewards do
    "blood_moon_rewards"
    |> HacLong.Admin.recent_op(50)
    |> Enum.find_value(default_rewards(), fn
      %{params: %{"reset" => r}} when r not in [nil, false] ->
        default_rewards()

      %{params: %{"rewards" => list}} ->
        case check_rewards(list) do
          {:ok, rw} -> rw
          _ -> nil
        end

      _ ->
        nil
    end)
  rescue
    _ -> default_rewards()
  end

  # ---------- cho client ----------

  defp public(s) do
    rank = ranking(s.score)
    on_map = players_on_map()

    %{
      open: s.open,
      left: if(s.until, do: max(0, s.until - now()), else: 0),
      warn: if(s.warn, do: max(0, s.warn - now()), else: 0),
      daily: s.daily,
      rewards: s.rewards,
      drops: s.drops,
      bots: MapSet.size(s.bots),
      players: on_map,
      top:
        rank
        |> Enum.take(rules().top_n)
        |> Enum.map(&%{uid: &1.uid, name: &1.name, kills: &1.kills, bot: &1.bot}),
      last: s.last
    }
  end

  # số người đang đứng ở Pháp Trường (bản đồ chưa chạy: 0)
  defp players_on_map do
    case Registry.lookup(HacLong.World.Registry, map_id()) do
      [{_pid, _}] -> length(HacLong.World.MapServer.snapshot(map_id()).players)
      _ -> 0
    end
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  defp broadcast(s),
    do: Phoenix.PubSub.broadcast(HacLong.PubSub, @topic, {:blood_moon, public(s)})

  defp now, do: System.system_time(:millisecond)

  @doc false
  def map_spawns do
    m = Maps.get(map_id())

    for y <- 0..(m.height - 1),
        x <- 0..(m.width - 1),
        Maps.walkable?(m, x, y),
        Maps.tile(m, x, y) == ":",
        do: {x, y}
  end
end

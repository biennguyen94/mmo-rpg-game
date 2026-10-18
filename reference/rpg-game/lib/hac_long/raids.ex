defmodule HacLong.Raids do
  @moduledoc """
  Xâm lăng kiểu MU: Rồng Đỏ, Phù Thủy Trắng (DECISIONS B-20; số ở `RULES.raids`).

  - **Lịch** (giờ Việt Nam, hàm thuần `next_start/2`): mỗi loại bắt đầu ở mốc `every_hours` giờ lệch `offset_minutes`
    phút, kéo dài `minutes` phút.
  - **Bắt đầu:** chọn ngẫu nhiên `pick` bản đồ trong `maps`; mỗi bản đồ nhận `leader.count` con đầu đàn (đứng yên, tính
    như trùm) và `minion.count` con lính (`HacLong.World.MapServer.raid/3`), không hồi sinh. Cấp theo vùng của bản đồ:
    đầu đàn = cấp trùm vùng + `level_bonus`, lính = cấp quái mạnh nhất vùng + `level_bonus` (`spec/3`).
  - **Thưởng** (`HacLong.World` / `Engine`): kinh nghiệm, vàng × `reward_mult`; đầu đàn chắc chắn rơi ngọc
    (`jewel_chance`) và có thể rơi thêm `drops`; lính rơi ngọc `minion_jewel_chance`.
  - **Kết thúc:** hạ hết mọi con ở mọi bản đồ (kết thúc sớm) hoặc hết giờ (con chưa ai đánh biến mất). Báo cả server.

  `config :hac_long, :raids, auto: false` (test) thì không tự chạy theo lịch; dùng `start_now/2`.
  """
  use GenServer
  require Logger

  alias HacLong.Chat
  alias HacLong.Game.Data
  alias HacLong.World.{MapServer, Maps}

  @rules Data.rules().raids |> Map.delete(:_doc)
  @utc_offset 7 * 3600

  def rules, do: @rules
  def keys, do: @rules |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()

  @doc "Luật của loại `key` (chuỗi), nil nếu không có."
  def rule(key) when is_binary(key),
    do: Enum.find_value(@rules, fn {k, r} -> to_string(k) == key && r end)

  def rule(_), do: nil

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Lần bắt đầu tiếp theo của loại `key` (DateTime UTC) sau `now`."
  def next_start(key, now) do
    r = rule(key)
    local = DateTime.to_unix(now) + @utc_offset - r.offset_minutes * 60
    step = r.every_hours * 3600
    DateTime.from_unix!((div(local, step) + 1) * step - @utc_offset + r.offset_minutes * 60)
  end

  @doc """
  Chỉ số quái xâm lăng `kind` của loại `key` trên vùng `zone` (chỉ số vùng): `%{id, name, level, mult, reward_mult,
  jewel_chance, raid}`. Con đầu đàn tính như trùm (`boss: true` ở MapServer).
  """
  def spec(key, kind, zone) do
    r = rule(key)
    z = Data.zone(zone) || hd(Data.zones())

    {u, level, jewel} =
      if kind == r.leader.kind,
        do: {r.leader, z.boss.level, r.jewel_chance},
        else: {r.minion, z.monsters |> Enum.map(& &1.level) |> Enum.max(), r.minion_jewel_chance}

    %{
      id: kind,
      name: u.name,
      level: level + u.level_bonus,
      mult: u.mult,
      reward_mult: r.reward_mult,
      jewel_chance: jewel,
      raid: key
    }
  end

  @doc "Đồ thêm khi hạ con đầu đàn của loại `key`: `[{item_id, tỉ_lệ}]`."
  def drops(key),
    do: rule(key).drops |> Enum.map(fn {id, c} -> {to_string(id), c} end) |> Enum.sort()

  @doc "Trạng thái: `%{key => %{active, ends_at, maps: %{id => số_con_còn}, next_at}}`."
  def status, do: GenServer.call(__MODULE__, :status)

  @doc "Bắt đầu ngay loại `key` (quản trị / test). `maps`: thay danh sách bản đồ."
  def start_now(key, maps \\ nil), do: GenServer.call(__MODULE__, {:start, key, maps})

  @doc "Kết thúc ngay (mọi loại nếu `key` nil)."
  def stop_now(key \\ nil), do: GenServer.call(__MODULE__, {:stop, key})

  @doc "MapServer báo: một con của `key` ở `map_id` vừa bị hạ, còn `left` con ở bản đồ đó (`leader?`: con đầu đàn)."
  def killed(key, map_id, leader?, left),
    do:
      if(Process.whereis(__MODULE__),
        do: GenServer.cast(__MODULE__, {:killed, key, map_id, leader?, left})
      )

  # ---------- Máy chủ ----------

  @impl true
  def init(:ok) do
    s =
      Map.new(keys(), &{&1, %{active: false, ends_at: nil, maps: %{}, next_at: nil, timer: nil}})

    {:ok, Enum.reduce(keys(), s, &schedule(&2, &1))}
  end

  @impl true
  def handle_call(:status, _from, s), do: {:reply, view(s), s}

  def handle_call({:start, key, maps}, _from, s) do
    case rule(key) do
      nil ->
        {:reply, {:error, "Không có sự kiện #{key}."}, s}

      r ->
        s = if s[key].active, do: finish(s, key, :restart), else: s
        s = begin(s, key, maps || Enum.take_random(r.maps, r.pick))
        {:reply, {:ok, view(s)[key]}, s}
    end
  end

  def handle_call({:stop, nil}, _from, s),
    do:
      {:reply, :ok,
       Enum.reduce(keys(), s, fn k, s -> if s[k].active, do: finish(s, k, :stop), else: s end)}

  def handle_call({:stop, key}, _from, s),
    do: {:reply, :ok, if(s[key] && s[key].active, do: finish(s, key, :stop), else: s)}

  @impl true
  def handle_cast({:killed, key, map_id, leader?, left}, s) do
    case s[key] do
      %{active: true, maps: %{^map_id => _}} ->
        r = rule(key)
        if leader?, do: Chat.system("#{r.icon} #{r.leader.name} ở #{map_name(map_id)} đã bị hạ!")
        s = put_in(s[key].maps[map_id], left)

        if Enum.all?(s[key].maps, fn {_, n} -> n == 0 end),
          do: {:noreply, finish(s, key, :cleared)},
          else: {:noreply, s}

      _ ->
        {:noreply, s}
    end
  end

  @impl true
  def handle_info({:tick, key}, s) do
    s = put_in(s[key].timer, nil)
    r = rule(key)

    if s[key].active,
      do: {:noreply, finish(s, key, :timeout)},
      else: {:noreply, begin(s, key, Enum.take_random(r.maps, r.pick))}
  end

  defp begin(s, key, maps) do
    r = rule(key)

    units =
      [{r.leader.kind, r.leader.count, true}] ++
        if(r.minion, do: [{r.minion.kind, r.minion.count, false}], else: [])

    counts =
      for id <- maps, into: %{} do
        id = to_string(id)

        got =
          try do
            MapServer.raid(id, key, units)
          catch
            :exit, _ -> 0
          end

        {id, got}
      end

    counts = Map.reject(counts, fn {_, n} -> n == 0 end)
    ends = System.system_time(:second) + r.minutes * 60
    s = cancel(s, key)
    timer = Process.send_after(self(), {:tick, key}, r.minutes * 60 * 1000)

    where = Enum.map_join(Map.keys(counts), ", ", &map_name/1)

    Chat.system(
      "#{r.icon} #{r.name}! #{r.leader.name} xuất hiện ở #{where} trong #{r.minutes} phút: thưởng ×#{r.reward_mult}, chắc chắn rơi ngọc."
    )

    put_in(s[key], %{s[key] | active: true, ends_at: ends, maps: counts, timer: timer})
  end

  defp finish(s, key, why) do
    r = rule(key)

    for {id, _} <- s[key].maps do
      try do
        MapServer.end_raid(id, key)
      catch
        :exit, _ -> :ok
      end
    end

    case why do
      :cleared -> Chat.system("🏆 #{r.name} kết thúc: mọi #{r.leader.name} đã bị hạ!")
      :timeout -> Chat.system("#{r.icon} #{r.name} kết thúc.")
      _ -> :ok
    end

    s = cancel(s, key)
    s = put_in(s[key], %{s[key] | active: false, ends_at: nil, maps: %{}})
    schedule(s, key)
  end

  defp schedule(s, key) do
    if Application.get_env(:hac_long, :raids, [])[:auto] == false do
      put_in(s[key].next_at, nil)
    else
      next = next_start(key, DateTime.utc_now())
      ms = max(DateTime.diff(next, DateTime.utc_now(), :millisecond), 1000)

      put_in(s[key], %{
        s[key]
        | next_at: DateTime.to_unix(next),
          timer: Process.send_after(self(), {:tick, key}, ms)
      })
    end
  end

  defp cancel(s, key) do
    if t = s[key].timer, do: Process.cancel_timer(t)
    put_in(s[key].timer, nil)
  end

  defp view(s),
    do: Map.new(s, fn {k, v} -> {k, Map.take(v, [:active, :ends_at, :maps, :next_at])} end)

  defp map_name(id), do: (m = Maps.get(id)) && m.name
end

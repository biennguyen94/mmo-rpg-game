defmodule HacLong.CastleSiege do
  @moduledoc """
  Công Thành Chiến (kiểu MU Castle Siege, DECISIONS B-22; số ở `RULES.castle_siege`).

  - **Lịch** (giờ Việt Nam, hàm thuần `next_start/1`): mỗi tuần vào thứ `weekday` lúc `hour:minute`, đánh `run_minutes`
    phút trên bản đồ chung `map` (`event: "castle_siege"`).
  - **Đăng ký** (`register/2`, ở Người Gác Tháp, trước giờ đánh): bang chủ / phó bang, tốn `register_gold` vàng của người
    đăng ký. Bang đang giữ thành không cần đăng ký.
  - **Vào** (`enter/2`, từ Session): trong lúc đánh, thành viên từ `min_level` của bang đã đăng ký hoặc bang giữ thành
    (quản trị mở ngay thì mọi bang); đứng ở sân phía nam. Gục thì về Làng (không mất vàng), vào lại được.
  - **Vương Miện** (`crown`) ở giữa thành: bang hạ được thì **giữ Vương Miện** (`defeated/3`); Vương Miện hiện lại sau
    `crown.respawn_s` giây; bang đang giữ không đánh được nó (`crown_blocked/2`). Người các bang khác nhau đồ sát nhau
    (`HacLong.Slay`) không mất vàng, không tên đỏ; cùng bang không đánh nhau.
  - **Kết thúc:** bang đang giữ Vương Miện là **Chủ Thành** tới trận sau (giữ trong bảng `castle_siege`); mọi thành viên
    nhận `reward` qua thư. Không bang nào giữ thì Chủ Thành cũ giữ nguyên. Người còn trong thành về Làng.

  Trạng thái công khai ở ETS (`status/0`) để Session / `Engine.view` đọc không cần gọi tiến trình. Tiến trình không gọi
  đồng bộ vào Session (đưa người về Làng, gửi thư chạy trong Task). `config :hac_long, :castle_siege, auto: false`
  (test): không tự chạy theo lịch, không tự nạp từ database (`reload/0`).
  """
  use GenServer
  require Logger

  import Ecto.Query

  alias HacLong.{Chat, Guilds, Mailbox, Repo, World}
  alias HacLong.Game.{Data, Session}
  alias HacLong.World.{MapServer, Maps}

  @r Data.rules().castle_siege
  @utc_offset 7 * 3600
  @table :castle_siege

  def rules, do: @r
  def map_id, do: @r.map
  def crown_kind, do: @r.crown.kind

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  # ---------- Lịch (hàm thuần) ----------

  @doc "Lần đánh tiếp theo (unix) sau `now`: thứ `weekday` lúc `hour:minute` giờ Việt Nam."
  def next_start(now \\ DateTime.utc_now()) do
    t = DateTime.to_unix(now)
    local = DateTime.from_unix!(t + @utc_offset)
    days = rem(@r.weekday - Date.day_of_week(local) + 7, 7)

    at =
      DateTime.new!(Date.add(DateTime.to_date(local), days), Time.new!(@r.hour, @r.minute, 0))
      |> DateTime.to_unix()
      |> Kernel.-(@utc_offset)

    if at > t, do: at, else: at + 7 * 86_400
  end

  # ---------- Đọc trạng thái (không gọi tiến trình) ----------

  @doc "`%{phase: \"idle\" | \"fight\", ends_at, next_at, owner, holder, registered, open_all, crown}`."
  def status do
    with ref when ref != :undefined <- :ets.whereis(@table),
         [{:status, s}] <- :ets.lookup(@table, :status) do
      s
    else
      _ ->
        %{
          phase: "idle",
          ends_at: nil,
          next_at: next_start(),
          owner: nil,
          holder: nil,
          registered: [],
          open_all: false,
          crown: false
        }
    end
  end

  def fighting?, do: status().phase == "fight"

  @doc "Thông tin cho giao diện."
  def view(p) do
    s = status()
    g = p[:guild]

    Map.merge(Map.drop(s, [:registered]), %{
      min_level: @r.min_level,
      run_minutes: @r.run_minutes,
      register_gold: @r.register_gold,
      registered_count: length(s.registered),
      mine_registered: g != nil and g.id in s.registered,
      can_enter: g != nil and allowed?(s, g.id),
      staff: g != nil and g.role in ~w(leader officer),
      inside: p[:pos] != nil and p.pos.map == @r.map
    })
  end

  defp allowed?(s, gid),
    do: s.open_all or gid in s.registered or (s.owner != nil and s.owner.id == gid)

  @doc "Lý do người `p` không được đánh Vương Miện (bang đang giữ), nil nếu được."
  def crown_blocked(p, m) do
    s = status()

    cond do
      m.kind != @r.crown.kind -> nil
      s.phase != "fight" -> "Công Thành Chiến chưa bắt đầu."
      p[:guild] == nil -> "Cần ở trong một bang."
      s.holder && s.holder.id == p.guild.id -> "Bang bạn đang giữ Vương Miện, hãy bảo vệ nó!"
      true -> nil
    end
  end

  @doc "Chỉ số Vương Miện (quái bản đồ sự kiện)."
  def crown_spec do
    c = @r.crown
    %{id: c.kind, name: c.name, level: c.level, mult: c.mult}
  end

  # ---------- Đăng ký, vào ----------

  @doc "Bang chủ / phó bang đăng ký bang mình cho trận tới (tốn `register_gold`). Trả `{kết_quả, nhân_vật}`."
  def register(p, _uid) do
    g = p[:guild]
    s = status()

    cond do
      g == nil ->
        {%{ok: false, msg: "Cần ở trong một bang."}, p}

      g.role not in ~w(leader officer) ->
        {%{ok: false, msg: "Chỉ bang chủ / phó bang được đăng ký."}, p}

      s.phase == "fight" ->
        {%{ok: false, msg: "Công Thành Chiến đang diễn ra, đăng ký trận sau."}, p}

      s.owner && s.owner.id == g.id ->
        {%{ok: false, msg: "Bang bạn đang giữ thành, không cần đăng ký."}, p}

      g.id in s.registered ->
        {%{ok: false, msg: "Bang bạn đã đăng ký rồi."}, p}

      p.gold < @r.register_gold ->
        {%{ok: false, msg: "Cần #{@r.register_gold} vàng để đăng ký."}, p}

      true ->
        case GenServer.call(__MODULE__, {:register, g.id}) do
          :ok ->
            {%{
               ok: true,
               msg:
                 "🏰 Đã đăng ký bang [#{g.tag}] cho Công Thành Chiến (−#{@r.register_gold} vàng)."
             }, %{p | gold: p.gold - @r.register_gold}}

          {:error, msg} ->
            {%{ok: false, msg: msg}, p}
        end
    end
  end

  @doc "Vào thành (Session gọi). Trả `{kết_quả, nhân_vật}`."
  def enter(p, uid) do
    s = status()
    g = p[:guild]

    cond do
      World.near_npc(p, ["tower"]) == nil ->
        {%{ok: false, msg: "Hãy đến gặp Người Gác Tháp ở Làng."}, p}

      p.battle ->
        {%{ok: false, msg: "Đang trong trận đấu."}, p}

      s.phase != "fight" ->
        {%{ok: false, msg: "Công Thành Chiến chưa bắt đầu."}, p}

      g == nil ->
        {%{ok: false, msg: "Cần ở trong một bang."}, p}

      not allowed?(s, g.id) ->
        {%{ok: false, msg: "Bang bạn chưa đăng ký Công Thành Chiến."}, p}

      p.level < @r.min_level ->
        {%{ok: false, msg: "Cần cấp #{@r.min_level}."}, p}

      p.hp <= 0 ->
        {%{ok: false, msg: "Bạn cần hồi máu trước."}, p}

      true ->
        GenServer.cast(__MODULE__, {:entered, uid})

        {%{
           ok: true,
           msg: "🏰 Vào Thành Hắc Long! Hạ Vương Miện ở giữa thành và giữ nó tới hết giờ."
         }, World.warp(p, uid, spawn_pos())}
    end
  end

  defp spawn_pos do
    m = Maps.get(@r.map)
    [y0, y1] = @r.spawn_rows

    {x, y} =
      Enum.random(for y <- y0..y1, x <- 0..(m.width - 1), Maps.walkable?(m, x, y), do: {x, y})

    %{map: @r.map, x: x, y: y}
  end

  # ---------- Từ trò chơi / quản trị ----------

  @doc "Người `uid` (bang `guild`) vừa hạ quái `mid` trên bản đồ thành."
  def defeated(uid, mid, guild),
    do:
      if(Process.whereis(__MODULE__),
        do: GenServer.cast(__MODULE__, {:defeated, uid, mid, guild})
      )

  @doc "Bắt đầu ngay (quản trị / test). `open_all`: mọi bang vào được."
  def start_now(open_all \\ true), do: GenServer.call(__MODULE__, {:start, open_all})

  @doc "Kết thúc ngay (test)."
  def finish_now, do: GenServer.call(__MODULE__, :finish)

  @doc "Nạp lại Chủ Thành / đăng ký từ database."
  def reload, do: GenServer.call(__MODULE__, :reload)

  # ---------- Máy chủ ----------

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])

    s = %{
      phase: :idle,
      ends_at: nil,
      owner: nil,
      registered: [],
      holder: nil,
      open_all: false,
      crown: nil,
      inside: MapSet.new(),
      timer: nil
    }

    if auto?(), do: send(self(), :load)
    {:ok, publish(s)}
  end

  defp auto?, do: Application.get_env(:hac_long, :castle_siege, [])[:auto] != false

  @impl true
  def handle_call({:register, gid}, _from, s) do
    if s.phase == :fight or gid in s.registered do
      {:reply, {:error, "Không đăng ký được lúc này."}, s}
    else
      s = %{s | registered: s.registered ++ [gid]}
      save(s)
      {:reply, :ok, publish(s)}
    end
  end

  def handle_call({:start, open_all}, _from, s) do
    s = if s.phase == :fight, do: finish(cancel(s)), else: s
    {:reply, :ok, begin(cancel(s), open_all)}
  end

  def handle_call(:finish, _from, s),
    do: {:reply, :ok, if(s.phase == :fight, do: finish(cancel(s)), else: s)}

  def handle_call(:reload, _from, s), do: {:reply, :ok, s |> load() |> publish()}

  @impl true
  def handle_cast({:entered, uid}, s), do: {:noreply, %{s | inside: MapSet.put(s.inside, uid)}}

  def handle_cast({:defeated, uid, mid, guild}, %{phase: :fight, crown: mid} = s)
      when guild != nil do
    g = %{id: guild.id, name: guild.name, tag: guild.tag}

    Chat.system(
      "👑 [#{g.tag}] #{g.name} chiếm Vương Miện! Vương Miện hiện lại sau #{@r.crown.respawn_s} giây."
    )

    Process.send_after(self(), :crown, @r.crown.respawn_s * 1000)
    _ = uid
    {:noreply, publish(%{s | holder: g, crown: nil})}
  end

  def handle_cast({:defeated, _, _, _}, s), do: {:noreply, s}

  @impl true
  def handle_info(:load, s), do: {:noreply, s |> load() |> publish() |> schedule()}
  def handle_info(:start, s), do: {:noreply, begin(%{s | timer: nil}, false)}
  def handle_info(:finish, s), do: {:noreply, finish(%{s | timer: nil})}

  def handle_info(:crown, %{phase: :fight} = s), do: {:noreply, publish(spawn_crown(s))}
  def handle_info(:crown, s), do: {:noreply, s}

  # ---------- Diễn biến ----------

  defp begin(s, open_all) do
    if not open_all and s.registered == [] and s.owner == nil do
      Chat.system("🏰 Công Thành Chiến tuần này không có bang nào đăng ký.")
      s |> publish() |> schedule()
    else
      safe(fn -> MapServer.clear_monsters(@r.map) end)
      ends = System.os_time(:second) + @r.run_minutes * 60

      s = %{
        s
        | phase: :fight,
          ends_at: ends,
          holder: s.owner,
          open_all: open_all,
          inside: MapSet.new()
      }

      s = spawn_crown(s)

      Chat.system(
        "🏰 Công Thành Chiến bắt đầu (#{@r.run_minutes} phút)! Thành viên các bang đã đăng ký gặp Người Gác Tháp ở Làng để vào thành, hạ Vương Miện và giữ nó tới hết giờ."
      )

      s |> publish() |> arm(ends, :finish)
    end
  end

  defp spawn_crown(s) do
    {x, y} = List.to_tuple(@r.crown.at)

    case safe(fn ->
           MapServer.put_monster(
             @r.map,
             @r.crown.kind,
             {x, y},
             true,
             false,
             Map.take(crown_spec(), [:name, :level])
           )
         end) do
      %{id: id} -> %{s | crown: id}
      _ -> s
    end
  end

  defp finish(s) do
    owner = s.holder || s.owner

    text =
      if owner,
        do: "🏆 Công Thành Chiến kết thúc: [#{owner.tag}] #{owner.name} là Chủ Thành Hắc Long!",
        else: "🏰 Công Thành Chiến kết thúc: chưa bang nào giữ được thành."

    Chat.system(text)
    inside = MapSet.to_list(s.inside)
    winner = s.holder

    Task.start(fn ->
      safe(fn -> MapServer.clear_monsters(@r.map) end)
      Enum.each(inside, &send_home/1)
      if winner, do: reward(winner)
    end)

    s = %{
      s
      | phase: :idle,
        ends_at: nil,
        owner: owner,
        registered: [],
        holder: nil,
        open_all: false,
        crown: nil,
        inside: MapSet.new()
    }

    save(s)
    s |> publish() |> schedule()
  end

  defp reward(g) do
    items = Map.new(@r.reward.items, fn {k, v} -> {to_string(k), v} end)

    for uid <- safe(fn -> Guilds.member_ids(g.id) end) || [] do
      safe(fn ->
        Mailbox.send(uid, %{
          subject: "🏰 Chủ Thành Hắc Long",
          body:
            "Bang [#{g.tag}] #{g.name} giữ được thành trong Công Thành Chiến. Phần thưởng cho mọi thành viên.",
          gold: @r.reward.gold,
          items: items
        })
      end)
    end
  end

  defp send_home(uid) do
    safe(fn ->
      if Session.online?(uid) do
        Session.admin(uid, fn p ->
          if p.pos.map == @r.map and p.battle == nil,
            do:
              {:ok, World.warp(p, uid, World.village_spawn()),
               "Công Thành Chiến kết thúc, bạn được đưa về Làng."},
            else: {:error, "không ở trong thành"}
        end)
      end
    end)
  end

  # ---------- Lưu ----------

  defp load(s) do
    case safe(fn ->
           Repo.one(
             from c in "castle_siege",
               where: c.id == 1,
               select: %{owner: c.owner_guild_id, registered: c.registered}
           )
         end) do
      %{owner: gid, registered: reg} ->
        %{s | owner: gid && safe(fn -> Guilds.info_brief(gid) end), registered: reg || []}

      # chưa có dòng nào: chưa ai giữ thành, chưa ai đăng ký
      nil ->
        %{s | owner: nil, registered: []}

      _ ->
        s
    end
  end

  defp save(s) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    row = %{
      id: 1,
      owner_guild_id: s.owner && s.owner.id,
      owner_since: s.owner && now,
      registered: s.registered,
      inserted_at: now,
      updated_at: now
    }

    safe(fn ->
      Repo.insert_all("castle_siege", [row],
        on_conflict: {:replace, [:owner_guild_id, :registered, :updated_at]},
        conflict_target: :id
      )
    end)
  end

  defp publish(s) do
    :ets.insert(
      @table,
      {:status,
       %{
         phase: to_string(s.phase),
         ends_at: s.ends_at,
         next_at: next_start(),
         owner: s.owner,
         holder: s.holder,
         registered: s.registered,
         open_all: s.open_all,
         crown: s.crown != nil
       }}
    )

    s
  end

  defp schedule(s) do
    if auto?(), do: arm(cancel(s), next_start(), :start), else: s
  end

  defp arm(s, at, msg) do
    s = cancel(s)
    %{s | timer: Process.send_after(self(), msg, max(0, at - System.os_time(:second)) * 1000)}
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
      Logger.error("Công Thành Chiến: " <> Exception.message(e))
      nil
  catch
    :exit, _ -> nil
  end
end

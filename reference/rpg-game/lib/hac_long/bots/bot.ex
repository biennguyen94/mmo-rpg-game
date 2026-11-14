defmodule HacLong.Bots.Bot do
  @moduledoc """
  Một người chơi AI (Phase 16). Gắn vào `Session` của tài khoản bot như một tab đang mở (nên có mặt trên
  bản đồ, ai cũng thấy trong danh sách Quanh đây, xem được hồ sơ, thách đấu được), rồi cứ mỗi nhịp hỏi
  `HacLong.Bots.Brain` lệnh tiếp theo và gửi qua `Session.command/2` như client.

  Thỉnh thoảng nói một câu trong kênh thế giới; lời mời cược đấu thì từ chối sau vài giây. Vừa gục (bị đồ sát,
  thua quái…) thì đứng nghỉ ở Làng `RULES.bots.rest_after_death_s` giây rồi mới đi luyện tiếp (`Brain.rest_until/5`).

  Lịch chơi như người (DECISIONS "Bot chơi theo phiên"): mỗi phiên online `RULES.bots.schedule.online_h` giờ rồi thoát hẳn
  `offline_h` giờ (biến khỏi bản đồ, danh sách online), thoát khi đang rảnh (không trận, không ở tháp / phòng sự kiện, không
  đồ sát); lúc khởi động một phần bot đang offline (`start_offline`). Trong phiên thỉnh thoảng đứng treo `afk_min` phút
  (mỗi `afk_every_min` phút) ở chỗ không có trận. Quản trị gọi bot vào Huyết Nguyệt thì bot offline cũng vào lại.
  Bot gắn vào Session qua một tiến trình "tab" riêng (`tab`): thoát là tắt tab đó, như người đóng trình duyệt.

  Câu cá (DECISIONS "Bot câu cá, bot try hard"): hẹn lượt ra Biển Long Vương (`RULES.bots.fish`), báo Brain ô Long Vương /
  Đàn Cá Vàng đang có; thả câu xong thì giật cần sau khi cá cắn `react_ms` mili giây. Bot try hard (`RULES.bots.tryhard`)
  nghỉ ít hơn, leo Tháp và ra hồ thường hơn, giật cần nhanh hơn.
  """
  use GenServer, restart: :transient
  require Logger

  alias HacLong.Chat
  alias HacLong.Bots.Brain
  alias HacLong.Game.Session
  alias HacLong.World.{Maps, MapServer}

  @lines [
    "Có ai đi tổ đội không?",
    "Quái ở đây rơi đồ ổn đấy.",
    "Sắp lên cấp rồi!",
    "Bình máu giờ đắt quá…",
    "Ai biết chỗ luyện cấp nhanh không?",
    "Hôm nay may mắn ghê.",
    "Đợi quái vàng xâm lăng thôi.",
    "Chào mọi người!",
    "Vừa hạ được một con khó nhằn.",
    "Bản đồ phụ vui phết."
  ]
  # trung bình khoảng 4 phút một câu (mỗi nhịp ~0,6 giây)
  @chat_chance 1 / 400
  @tower_every HacLong.Game.Data.rules().bots.play.tower_every_min
  # câu cá, bot try hard (DECISIONS "Bot câu cá, bot try hard")
  @fish HacLong.Game.Data.rules().bots.fish
  @tryhard HacLong.Game.Data.rules().bots.tryhard
  @feed_every HacLong.Game.Data.rules().bots.play.feed_every_min
  @tower_max HacLong.Game.Data.rules().bots.play.tower_max_min * 60_000
  # tự gỡ kẹt (DECISIONS "Đưa về Làng"): đứng yên quá chừng này thì về Làng
  @stuck_ms HacLong.Game.Data.rules().bots.play.stuck_min * 60_000
  # lịch chơi theo phiên (DECISIONS "Bot chơi theo phiên")
  @sched HacLong.Game.Data.rules().bots.schedule

  def start_link({uid, _name, _cls} = arg),
    do:
      GenServer.start_link(__MODULE__, arg, name: {:via, Registry, {HacLong.Bots.Registry, uid}})

  @impl true
  def init({uid, name, cls}) do
    Process.send_after(self(), :start, 1000 + :rand.uniform(4000))

    # `rest_until` theo đồng hồ đơn điệu (có thể là số âm trên máy ảo): mốc "chưa nghỉ" là lúc khởi động, không phải 0
    {:ok,
     %{
       uid: uid,
       name: name,
       cls: cls,
       tries: 0,
       deaths: nil,
       rest_until: System.monotonic_time(:millisecond),
       # lần leo Tháp Vô Tận tiếp theo (`RULES.bots.play.tower_every_min`)
       next_tower: next_in(System.monotonic_time(:millisecond), tower_every(uid)),
       # lượt ra Biển Long Vương câu cá tiếp theo, và lúc lượt đang câu kết thúc
       next_fish: next_in(System.monotonic_time(:millisecond), fish_every(uid)),
       fish_until: System.monotonic_time(:millisecond),
       # đã thả câu, đang chờ giật cần (`:reel`)
       reeling: false,
       # lần cho thú ăn tiếp theo (`play.feed_every_min`): ngay từ đầu được cho ăn
       next_feed: System.monotonic_time(:millisecond),
       # bản đồ đang đứng ở nhịp trước (gục thì biết gục ở đâu) và các chỗ đang tránh (`Brain.note_death/3`)
       last_map: nil,
       # lúc vào bản đồ tháp (Tháp Vô Tận / Quảng Trường / Lâu Đài / Kalima): ở quá `play.tower_max_min` phút thì ra cổng
       tower_since: nil,
       # tầng lúc vào Tháp Vô Tận lượt này (Brain ra cổng khi vừa lên qua hết một chặng 10 tầng, không ra ngay tầng vào)
       tower_from: nil,
       # dấu vết tiến triển ở nhịp trước và lúc nó bắt đầu không đổi (`unstick/4`)
       sig: nil,
       still_since: nil,
       deaths_at: %{fails: %{}, avoid: %{}},
       # phiên chơi: online / offline tới `next_switch`; tab: tiến trình gắn vào Session lúc online; treo máy tới `afk_until`
       online: :rand.uniform() >= @sched.start_offline,
       tab: nil,
       next_switch: nil,
       afk_until: System.monotonic_time(:millisecond),
       next_afk: next_in(System.monotonic_time(:millisecond), @sched.afk_every_min)
     }}
  end

  @impl true
  def handle_info(:start, s) do
    now = System.monotonic_time(:millisecond)

    if s.online do
      s = go_online(s, now)
      Phoenix.PubSub.subscribe(HacLong.PubSub, Session.topic(s.uid))
      send(self(), :tick)
      {:noreply, s}
    else
      # vừa khởi động mà đang "offline": vào lại sau một quãng ngẫu nhiên trong phiên offline
      Phoenix.PubSub.subscribe(HacLong.PubSub, Session.topic(s.uid))
      s = %{s | next_switch: now + round(:rand.uniform() * hours(@sched.offline_h))}
      send(self(), :wake)
      {:noreply, s}
    end
  catch
    # Session chưa mở được (vd. nạp nhân vật lỗi): thử lại sau, không làm sập cả nhóm bot
    kind, reason ->
      Logger.warning("bot #{s.uid} chưa vào được: #{inspect(kind)} #{inspect(reason)}")
      Process.send_after(self(), :start, 30_000)
      {:noreply, s}
  end

  # thả diều (DECISIONS "Đồi Sáo Diều…"): gió giật thì giữ dây
  def handle_info(:hold, s) do
    Session.command(s.uid, %{"act" => "kite_hold"})
    {:noreply, %{s | reeling: false}}
  catch
    _, _ -> {:noreply, %{s | reeling: false}}
  end

  def handle_info(:reel, s) do
    Session.command(s.uid, %{"act" => "fish_reel"})
    {:noreply, %{s | reeling: false}}
  catch
    _, _ -> {:noreply, %{s | reeling: false}}
  end

  # đang offline: tới giờ (hoặc quản trị gọi vào Huyết Nguyệt) thì vào lại, không thì hỏi lại sau một phút
  def handle_info(:wake, %{online: false} = s) do
    now = System.monotonic_time(:millisecond)

    if now >= s.next_switch or HacLong.BloodMoon.bot_on?(s.uid) do
      send(self(), :tick)
      {:noreply, go_online(s, now)}
    else
      Process.send_after(self(), :wake, 60_000)
      {:noreply, s}
    end
  catch
    kind, reason ->
      Logger.warning("bot #{s.uid} chưa vào lại được: #{inspect(kind)} #{inspect(reason)}")
      Process.send_after(self(), :wake, 60_000)
      {:noreply, s}
  end

  def handle_info(:wake, s), do: {:noreply, s}

  # nhịp cũ còn trong hộp thư lúc vừa thoát: bỏ
  def handle_info(:tick, %{online: false} = s), do: {:noreply, s}

  def handle_info(:tick, s) do
    s = tick(s)
    {:noreply, s}
  catch
    kind, reason ->
      Logger.warning("bot #{s.uid}: #{inspect(kind)} #{inspect(reason)}")
      Process.send_after(self(), :tick, 3000)
      {:noreply, s}
  end

  # các tin khác phát cho người chơi (thông báo, cập nhật nhân vật…): bỏ qua
  def handle_info(_msg, s), do: {:noreply, s}

  defp tick(s) do
    p = Session.get(s.uid)
    now = System.monotonic_time(:millisecond)

    if now >= s.next_switch and leave_ok?(p, s.uid),
      do: go_offline(s, now),
      else: play(s, p, now)
  end

  defp play(s, p, now) do
    s = afk_turn(s, p, now)

    # vừa gục (về Làng): nghỉ một lúc rồi mới đi luyện tiếp; gục nhiều ở một chỗ thì tạm tránh chỗ đó
    s = note_death(s, p, now)

    s = %{
      s
      | rest_until: Brain.rest_until(s.rest_until, s.deaths, p, now, rest_mult(s.uid)),
        deaths: p && p.deaths
    }

    s = fish_turn(s, now)
    {dragon, school} = lake_tiles(p)
    {bird, flock} = HacLong.SkyEvent.tiles()
    snap = p && snapshot(p)

    # sự kiện (DECISIONS "Bot đi sự kiện"): Cổ Long, Mảnh Sao (chỉ hỏi khi đang ở đồi), Golden Invasion
    hill? = p != nil and p.pos.map == HacLong.Game.Kite.map_id()
    inv = HacLong.Invasion.status()
    name = if s.tries > 0, do: "#{s.name} #{s.tries}", else: s.name

    # Huyết Nguyệt (DECISIONS "Pháp Trường Huyết Nguyệt"): bot được quản trị gọi thì bỏ nghỉ / việc khác, vào Pháp Trường
    # tìm người gần nhất đồ sát (trong trận vẫn đánh như thường qua `Brain.decide/3`)
    # (đang đánh quái / leo Tháp thì bỏ ngang, đi luôn; trận đồ sát thì đánh cho xong)
    blood = p != nil and not HacLong.Slay.slaying?(p) and HacLong.BloodMoon.bot_on?(s.uid)

    # trăng đã lặn mà bot còn đứng ở Pháp Trường (đánh xong trận dở): về Làng, không đứng chơ vơ ở bản đồ không quái
    if p != nil and p.pos.map == HacLong.BloodMoon.map_id() and not HacLong.BloodMoon.open?() and
         not HacLong.Slay.slaying?(p) and (p.battle == nil or p.battle.over),
       do: Session.to_village(s.uid, "BLOOD_MOON")

    cmd =
      cond do
        blood ->
          blood_step(
            s.uid,
            Brain.blood_job(
              p,
              snap,
              s.uid,
              HacLong.BloodMoon.locked_s(s.uid),
              HacLong.BloodMoon.altar_lit()
            )
          )

        Brain.resting?(p, s.rest_until, now) ->
          nil

        # đang treo máy (đứng yên, không trận)
        now < s.afk_until ->
          nil

        true ->
          Brain.decide(p, snap, %{
            name: name,
            cls: s.cls,
            seed: s.uid,
            tower_due: now >= s.next_tower,
            feed_due: now >= s.next_feed,
            tower_stuck: s.tower_since != nil and now - s.tower_since > @tower_max,
            tower_from: s.tower_from,
            fishing: now < s.fish_until,
            dragon: dragon,
            school: school,
            bird: bird,
            flock: flock,
            world_boss: HacLong.WorldBoss.hp() != nil,
            stars: if(hill?, do: HacLong.SkyEvent.public().stars, else: []),
            invasion: if(inv.active, do: inv.maps, else: %{}),
            reeling: s.reeling,
            avoid: Brain.avoiding(s.deaths_at, now)
          })
      end

    s =
      case cmd && Session.command(s.uid, cmd) do
        # thả câu: giật cần sau khi cá cắn một lúc (phản xạ như người, chậm quá thì trượt)
        {%{ok: false}, nil} ->
          %{s | tries: s.tries + 1}

        # vừa vào tháp / cho thú ăn: hẹn lần sau
        {%{ok: true} = r, _} ->
          case cmd["act"] do
            "fish_cast" ->
              Process.send_after(self(), :reel, r.wait + react(s.uid))
              %{s | reeling: true}

            "kite_fly" ->
              Process.send_after(self(), :hold, r.wait + react(s.uid))
              %{s | reeling: true}

            "tower_enter" ->
              %{s | next_tower: next_in(now, tower_every(s.uid))}

            "pet_feed" ->
              %{s | next_feed: next_in(now, @feed_every)}

            _ ->
              s
          end

        _ ->
          s
      end

    if p && !p.battle && :rand.uniform() < @chat_chance, do: say(s, p)
    Process.send_after(self(), :tick, delay(p, cmd))
    in_tower = p != nil and p.pos.map == "tower"
    floor = in_tower && is_map(p[:tower]) && p.tower[:floor]

    s = %{
      s
      | last_map: p && p.pos.map,
        tower_since: if(in_tower, do: s.tower_since || now),
        tower_from: if(in_tower, do: s.tower_from || floor)
    }

    unstick(s, p, Brain.resting?(p, s.rest_until, now) or now < s.afk_until, now)
  end

  # ---------- Phiên chơi (DECISIONS "Bot chơi theo phiên") ----------

  defp hours([lo, hi]), do: round((lo + :rand.uniform() * (hi - lo)) * 3_600_000)

  # tab: tiến trình đứng thay trình duyệt (Session theo dõi nó; tắt nó là thoát game)
  defp go_online(s, now) do
    tab = spawn(fn -> tab_loop() end)
    Session.attach(s.uid, tab)

    %{
      s
      | online: true,
        tab: tab,
        next_switch: now + hours(@sched.online_h),
        sig: nil,
        still_since: nil
    }
  end

  defp go_offline(s, now) do
    if s.tab, do: Process.exit(s.tab, :kill)
    Process.send_after(self(), :wake, 60_000)
    %{s | online: false, tab: nil, next_switch: now + hours(@sched.offline_h), reeling: false}
  end

  defp tab_loop do
    receive do
      _ -> tab_loop()
    end
  end

  @doc false
  # thoát được lúc này: đang rảnh (không trận / trận đã xong, không ở tháp / phòng sự kiện, không đồ sát, không bị gọi vào
  # Huyết Nguyệt)
  def leave_ok?(nil, _uid), do: true

  def leave_ok?(p, uid) do
    (p.battle == nil or p.battle.over) and p.pos.map != "tower" and
      p.pos.map != HacLong.BloodMoon.map_id() and not HacLong.Slay.slaying?(p) and
      not HacLong.BloodMoon.bot_on?(uid)
  end

  # treo máy: tới lượt mà đang rảnh ở bản đồ thường thì đứng `afk_min` phút
  defp afk_turn(s, p, now) do
    cond do
      now < s.afk_until or now < s.next_afk ->
        s

      p != nil and p.battle == nil and p.pos.map != "tower" ->
        until = now + round(min_between(@sched.afk_min) * 60_000)
        %{s | afk_until: until, next_afk: next_in(until, @sched.afk_every_min)}

      true ->
        s
    end
  end

  defp min_between([lo, hi]), do: lo + :rand.uniform() * (hi - lo)

  # Tự gỡ kẹt: không nghỉ mà vị trí, máu, kinh nghiệm, vàng, lượt trận không đổi quá `play.stuck_min` phút thì về
  # Làng (Session.to_village: kết thúc trận như bỏ chạy, rời tháp / phòng sự kiện), bắt đầu đo lại.
  defp unstick(s, nil, _resting, _now), do: %{s | sig: nil, still_since: nil}
  defp unstick(s, _p, true, _now), do: %{s | sig: nil, still_since: nil}

  defp unstick(s, p, false, now) do
    # câu cá lâu một chỗ không phải kẹt: số cá câu được, Long Khí cũng là tiến triển
    sig =
      {p.pos, p.hp, p.xp, p.gold, p.level, p.battle && p.battle[:turn], p[:fish_caught],
       p[:long_khi]}

    cond do
      sig != s.sig ->
        %{s | sig: sig, still_since: now}

      now - s.still_since > @stuck_ms ->
        Logger.info("bot #{s.uid} kẹt ở #{p.pos.map} (#{p.pos.x}, #{p.pos.y}) quá lâu: về Làng")
        Session.to_village(s.uid, "BOT_STUCK")
        %{s | sig: nil, still_since: nil}

      true ->
        s
    end
  end

  # số lần gục tăng so với nhịp trước: gục ở bản đồ nhịp trước đứng
  defp note_death(%{deaths: d, last_map: m} = s, %{deaths: now_d}, now)
       when is_integer(d) and is_binary(m) and now_d > d,
       do: %{s | deaths_at: Brain.note_death(s.deaths_at, m, now)}

  defp note_death(s, _p, _now), do: s

  defp tryhard?(uid), do: Brain.tryhard?(uid)
  defp tower_every(uid), do: if(tryhard?(uid), do: @tryhard.tower_every_min, else: @tower_every)
  defp fish_every(uid), do: if(tryhard?(uid), do: @tryhard.fish_every_min, else: @fish.every_min)
  defp fish_stay(uid), do: if(tryhard?(uid), do: @tryhard.fish_stay_min, else: @fish.stay_min)
  defp rest_mult(uid), do: if(tryhard?(uid), do: @tryhard.rest_mult, else: 1)

  defp react(uid) do
    [lo, hi] = if tryhard?(uid), do: @tryhard.react_ms, else: @fish.react_ms
    lo + :rand.uniform(hi - lo + 1) - 1
  end

  # tới lượt ra hồ: câu trong `fish_stay` phút, hẹn lượt sau
  defp fish_turn(s, now) do
    if now >= s.next_fish,
      do: %{
        s
        | fish_until: next_in(now, fish_stay(s.uid)),
          next_fish: next_in(now, fish_every(s.uid))
      },
      else: s
  end

  # ô Long Vương / Đàn Cá Vàng đang có; chưa đủ cấp vào hồ thì khỏi hỏi
  defp lake_tiles(%{level: lv}) do
    lake = Maps.get(HacLong.LakeEvent.map_id())
    if lake && lv >= (lake[:min_level] || 1), do: HacLong.LakeEvent.tiles(), else: {nil, nil}
  end

  defp lake_tiles(_), do: {nil, nil}

  # Huyết Nguyệt: dịch chuyển vào Pháp Trường / đồ sát người trong tầm làm ngay (không phải lệnh Session); còn lại
  # (đi tới, uống bình) trả lệnh cho Session như thường
  defp blood_step(uid, {:teleport, {x, y}}) do
    Session.teleport(uid, %{map: HacLong.BloodMoon.map_id(), x: x, y: y})
    nil
  end

  defp blood_step(uid, {:slay, target}) do
    HacLong.Slay.attack(uid, target)
    nil
  end

  defp blood_step(_uid, cmd), do: cmd

  # mốc ngẫu nhiên trong khoảng [lo, hi] phút kể từ `now`
  defp next_in(now, [lo, hi]), do: now + round((lo + :rand.uniform() * (hi - lo)) * 60_000)

  defp snapshot(%{pos: %{map: id}}) do
    m = Maps.get(id)
    if m && not m.private and id != "tower", do: MapServer.snapshot(id)
  end

  defp snapshot(_), do: nil

  # trong trận (kể cả đang chờ lượt đồ sát) thì hỏi lại nhanh
  defp delay(%{battle: %{}}, _), do: 700 + :rand.uniform(700)
  defp delay(_p, nil), do: 2000 + :rand.uniform(2000)
  # đi qua lại chờ (hết quái, chờ trùm / hết giờ): hỏi lại chậm
  defp delay(_p, %{"act" => "move", "wait" => true}), do: 3000 + :rand.uniform(2000)
  defp delay(_p, %{"act" => "move"}), do: 280 + :rand.uniform(220)
  defp delay(_p, _), do: 600 + :rand.uniform(600)

  defp say(s, p) do
    Chat.post(%{uid: s.uid, name: p.name, map: p.pos.map}, Enum.random(@lines))
  end
end

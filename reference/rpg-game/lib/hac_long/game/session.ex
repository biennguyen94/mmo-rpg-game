defmodule HacLong.Game.Session do
  @moduledoc """
  Tiến trình giữ nhân vật của một tài khoản khi người chơi đang online.

  Mọi lệnh của cùng một tài khoản đi qua đúng một tiến trình này nên được xử lý
  lần lượt, kể cả khi mở nhiều tab: không có chuyện hai thao tác cùng đọc một
  trạng thái cũ rồi ghi đè nhau. Sau mỗi thay đổi, trạng thái được ghi vào
  PostgreSQL và phát cho các tab khác qua PubSub.

  - Các tab đang mở (`GameChannel`) gắn vào Session bằng `attach/2`. Còn ít nhất một tab thì
    nhân vật có mặt trên bản đồ; tab cuối đóng thì rời bản đồ. Không còn tab nào và
    không ai dùng trong `@idle_timeout` thì tiến trình tự tắt.
  - Bước đi (`"move"`) rất nhiều nên không ghi database mỗi bước: vị trí được ghi dồn sau
    `@flush_ms`, khi đổi bản đồ, khi vào trận, khi đóng game và khi tiến trình tắt.
  - Bước đi bị giới hạn tốc độ (`@step_ms`) để không chạy nhanh bằng script; các lệnh khác
    (đánh, mua bán...) cũng vậy (`@act_ms`), nhanh hơn tay người bấm nhiều.
  """
  use GenServer, restart: :transient
  require Logger

  alias HacLong.Game.{
    Achievements,
    Characters,
    Commands,
    Daily,
    Engine,
    Names,
    Quests,
    Tower,
    Tutorial
  }

  alias HacLong.{Arena, GuildQuests, Guilds, Mailbox, Market, Party, World, WorldBoss}
  alias HacLong.World.{MapServer, Maps}
  alias HacLong.Slay

  @idle_timeout :timer.minutes(10)
  @flush_ms 5_000
  @rid_memory 64
  # giao dịch giữ Session tối đa chừng này (rồi tự nhả, coi như giao dịch không thành)
  @hold_ms 3_000
  # khoảng cách tối thiểu giữa hai bước, cho phép dồn vài bước khi mạng giật
  @step_ms 90
  @step_burst 4
  @act_ms 80
  @act_burst 10
  @share_bonus HacLong.Game.Data.rules().party.share_bonus

  def topic(user_id), do: "player:#{user_id}"

  @doc "Trạng thái hiện tại (nil nếu chưa tạo nhân vật)."
  def get(user_id), do: call(user_id, :get)

  @doc "Tab `pid` mở game: nhân vật có mặt trên bản đồ. Trả về trạng thái hiện tại."
  def attach(user_id, pid), do: call(user_id, {:attach, pid})

  @doc "Chạy một lệnh từ client. Trả về `{kết_quả, nhân_vật}`."
  def command(user_id, cmd) when is_map(cmd), do: call(user_id, {:command, cmd, self()})

  @doc """
  Trùm thế giới đã gục hoặc bay đi (gọi từ `HacLong.WorldBoss`). `info`:
  `%{result: "win" | "fled", reward: nil | %{gold, xp, items, share}}`. Kết thúc trận đang
  đánh trùm (nếu có) và trao thưởng; người chơi không online thì vẫn nhận (lưu database).
  """
  def world_boss_end(user_id, info), do: call(user_id, {:world_boss_end, info})

  @doc """
  Đồng đội vừa hạ con quái đang đánh chung (gọi từ `HacLong.Party`). `info`:
  `%{key, n, xp, gold, killer}`. Trận của người này (nếu còn đánh) kết thúc bằng chiến thắng.
  """
  def shared_end(user_id, info), do: call(user_id, {:shared_end, info})

  @doc "Đang mở game (Session chạy và có tab). Không khởi động Session."
  def online?(user_id) do
    case Registry.lookup(HacLong.Game.Registry, user_id) do
      [{pid, _}] ->
        try do
          GenServer.call(pid, :online_info, 1000) != nil
        catch
          :exit, _ -> false
        end

      [] ->
        false
    end
  end

  @doc """
  Đồ sát (`HacLong.Slay`): vào trận với bản sao `foe` của đối thủ. `info`: `%{fight, foe}`.
  Trả `:ok` hoặc `{:error, lý_do}` (đang đánh, đã gục, rời bản đồ...).
  """
  def slay_begin(user_id, info), do: call(user_id, {:slay_begin, info})

  @doc "Trận đồ sát `id` không mở được ở bên kia: bỏ trận vừa vào (không ai mất gì)."
  def slay_cancel(user_id, id), do: call(user_id, {:slay_cancel, id})

  @doc "Hết giờ lượt đồ sát: đánh thường thay người chơi."
  def slay_auto(user_id), do: call(user_id, :slay_auto)

  @doc "Đối thủ đồ sát vừa ra đòn: `%{id, hp, foe_hp, until, text}`. Không khởi động Session."
  def slay_sync(user_id, info) do
    case Registry.lookup(HacLong.Game.Registry, user_id) do
      [{pid, _}] -> GenServer.cast(pid, {:slay_sync, info})
      [] -> :ok
    end
  end

  @doc """
  Giữ Session (cho giao dịch trực tiếp ghi cả hai nhân vật trong một transaction): trả về
  `{:ok, ref, nhân_vật}`; từ lúc đó tới `release/3` (hoặc sau `@hold_ms`) mọi lệnh khác của
  người này phải xếp hàng đợi, nên nhân vật không đổi dưới tay người giữ.
  """
  def hold(user_id) do
    ref = make_ref()

    case call(user_id, {:hold, ref}) do
      {:ok, p} -> {:ok, ref, p}
      err -> err
    end
  end

  @doc """
  Nhả Session đã `hold/1`. `player`: nhân vật mới (người giữ đã lưu database) hoặc `nil` nếu
  không đổi gì.
  """
  def release(user_id, ref, player), do: call(user_id, {:release, ref, player})

  @doc """
  Thao tác quản trị trên nhân vật (`HacLong.Admin`): `fun.(nhân_vật)` trả về
  `{:ok, nhân_vật_mới, thông_báo}` hoặc `{:error, lý_do}`. Chạy trong Session nên không đè
  lên lệnh người chơi đang gửi; lưu với lý do `"ADMIN"`, `ref` là mã dòng `admin_log`.
  """
  def admin(user_id, fun, ref \\ nil) when is_function(fun, 1),
    do: call(user_id, {:admin, fun, ref})

  @doc """
  Người chơi đang mở game (Session có tab): `%{count, players: [%{id, name, level, cls, map}]}`
  (tối đa `limit` người, theo tên). Không khởi động Session nào; Session đang bận quá 1 giây thì bỏ qua.
  """
  def online(limit \\ 200) do
    players =
      HacLong.Game.Registry
      |> Registry.select([{{:_, :"$1", :_}, [], [:"$1"]}])
      |> Enum.map(fn pid ->
        try do
          GenServer.call(pid, :online_info, 1000)
        catch
          :exit, _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    %{count: length(players), players: players |> Enum.sort_by(& &1.name) |> Enum.take(limit)}
  end

  @doc "Bang của người chơi vừa đổi: Session đang chạy thì nạp lại (không chạy thì thôi)."
  def refresh_guild(user_id) do
    case Registry.lookup(HacLong.Game.Registry, user_id) do
      [{pid, _}] -> GenServer.cast(pid, :refresh_guild)
      [] -> :ok
    end
  end

  defp call(user_id, msg, retry \\ true) do
    pid =
      case DynamicSupervisor.start_child(HacLong.Game.SessionSupervisor, {__MODULE__, user_id}) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    GenServer.call(pid, msg)
  catch
    # tiến trình vừa tự tắt vì rảnh đúng lúc gọi: khởi động lại và thử một lần nữa
    :exit, {reason, _} when retry and reason in [:noproc, :normal] -> call(user_id, msg, false)
  end

  def start_link(user_id) do
    GenServer.start_link(__MODULE__, user_id,
      name: {:via, Registry, {HacLong.Game.Registry, user_id}}
    )
  end

  @impl true
  def init(user_id) do
    # để `terminate/2` chạy khi server tắt (deploy) và ghi nốt vị trí chưa lưu
    Process.flag(:trap_exit, true)

    s = %{
      user_id: user_id,
      player: with_guild(Characters.load(user_id), user_id),
      tabs: %{},
      dirty: false,
      flush_timer: nil,
      steps: {@step_burst, now()},
      acts: {@act_burst, now()},
      # lệnh đã chạy theo `rid` (mã yêu cầu của client): gửi lại cùng `rid` thì trả kết quả cũ,
      # không chạy lần hai (bấm đúp, mạng chập chờn gửi lại). Giữ `@rid_memory` mã gần nhất.
      rids: %{},
      rid_order: :queue.new(),
      # `{ref, timer}` khi giao dịch đang giữ Session (`hold/1`); `queue`: lệnh đợi tới lúc nhả
      held: nil,
      queue: []
    }

    {:ok, s, @idle_timeout}
  end

  # Bang hội không lưu trong bảng characters: đọc từ HacLong.Guilds.
  defp with_guild(nil, _uid), do: nil
  defp with_guild(p, uid), do: Map.put(p, :guild, Guilds.brief(uid))

  @impl true
  def handle_call({:release, ref, player}, _from, %{held: {ref, timer}} = s) do
    Process.cancel_timer(timer)
    s = %{s | held: nil}

    s =
      if player do
        Characters.put_reason("TRADE")
        s = cancel_flush(%{s | player: player, dirty: false})
        broadcast(s, player, nil)
        s
      else
        if s.dirty, do: mark_dirty(s), else: s
      end

    s = replay(s)
    reply(:ok, s)
  end

  # nhả muộn (đã tự nhả vì quá giờ) hoặc nhả hai lần: bỏ qua
  def handle_call({:release, _ref, _player}, _from, %{held: nil} = s), do: reply(:ok, s)

  # đang bị giữ: lệnh xếp hàng, trả lời sau khi nhả
  def handle_call(msg, from, %{held: {_, _}} = s),
    do: {:noreply, %{s | queue: [{msg, from} | s.queue]}}

  def handle_call(msg, from, s) do
    {reason, ref} = save_reason(msg)
    Characters.put_reason(reason, ref)
    handle(msg, from, fresh(s))
  end

  # Chạy lại các lệnh đã xếp hàng trong lúc bị giữ, theo đúng thứ tự đến.
  defp replay(%{queue: []} = s), do: s

  defp replay(s) do
    queue = Enum.reverse(s.queue)

    Enum.reduce(queue, %{s | queue: []}, fn {msg, from}, s ->
      case handle_call(msg, from, s) do
        {:reply, value, s, _timeout} ->
          GenServer.reply(from, value)
          s

        # lại bị giữ (lệnh vừa chạy là `hold`): những lệnh sau tiếp tục xếp hàng
        {:noreply, s} ->
          s
      end
    end)
  end

  # Lý do ghi vào nhật ký vàng / đồ hiếm cho lần lưu nhân vật của lệnh này.
  defp save_reason({:command, %{"act" => act} = cmd, _origin}) when is_binary(act) do
    reason = if act =~ ~r/^[a-z_]{1,32}$/, do: String.upcase(act), else: "CMD"
    ref = Enum.find([cmd["listing"], cmd["id"], cmd["uid"]], &(is_binary(&1) or is_integer(&1)))
    {reason, ref}
  end

  defp save_reason({:world_boss_end, _}), do: {"WORLD_BOSS", nil}
  defp save_reason({:shared_end, _}), do: {"PARTY", nil}
  defp save_reason({:slay_begin, _}), do: {"SLAY", nil}
  defp save_reason(:slay_auto), do: {"SLAY", nil}
  defp save_reason({:admin, _fun, ref}), do: {"ADMIN", ref}
  defp save_reason(_), do: {"OTHER", nil}

  @impl true
  def handle_cast(:refresh_guild, %{player: nil} = s), do: {:noreply, s, timeout(s)}

  def handle_cast({:slay_sync, info}, %{player: %{battle: %{over: false} = b} = p} = s) do
    if b[:encounter][:slay] == info.id do
      log = Enum.take(b.log ++ [%{text: info.text, kind: "bad"}], -60)
      enc = %{b.encounter | mine: true, until: info.until}
      b = %{b | log: log, encounter: enc, monster: %{b.monster | hp: info.foe_hp}}
      p = %{p | hp: info.hp, battle: b}
      s = s |> Map.put(:player, p) |> mark_dirty()
      broadcast(s, p, nil)
      {:noreply, s, timeout(s)}
    else
      {:noreply, s, timeout(s)}
    end
  end

  def handle_cast({:slay_sync, _info}, s), do: {:noreply, s, timeout(s)}

  def handle_cast(:refresh_guild, s) do
    p = with_guild(s.player, s.user_id)
    s = %{s | player: p}
    broadcast(s, p, nil)
    if map_size(s.tabs) > 0, do: World.refresh(p, s.user_id)
    Phoenix.PubSub.broadcast(HacLong.PubSub, topic(s.user_id), {:guild, p.guild})
    {:noreply, s, timeout(s)}
  end

  # Sang ngày mới thì đổi việc hằng ngày (lưu cùng lần ghi tiếp theo).
  defp fresh(s), do: %{s | player: Daily.ensure(s.player, Daily.today())}

  defp handle(:get, _from, s), do: reply(s.player, s)

  defp handle(:online_info, _from, %{player: p} = s) when p != nil and map_size(s.tabs) > 0,
    do: reply(%{id: s.user_id, name: p.name, level: p.level, cls: p.cls, map: p.pos.map}, s)

  defp handle(:online_info, _from, s), do: reply(nil, s)

  defp handle({:attach, pid}, _from, s) do
    if map_size(s.tabs) == 0, do: World.enter(s.player, s.user_id)
    HacLong.Party.back(s.user_id)
    s = %{s | tabs: Map.put(s.tabs, Process.monitor(pid), pid)}
    reply(s.player, s)
  end

  defp handle({:command, %{"act" => act} = cmd, origin}, _from, s)
       when act in ["move", "teleport", "travel"] do
    case take(s, :steps, @step_ms, @step_burst) do
      {:ok, s} ->
        {result, player} = run_move(s, cmd)
        # bước ra / lên cầu thang có thể kết thúc lượt Quảng Trường Quỷ
        player = ds_record(player, s)
        {player, notes} = checks(player)
        old = s.player

        s =
          cond do
            player == old ->
              s

            old.pos.map != player.pos.map or player.battle != nil or
              player.waystones != old.waystones or player[:tower] != old[:tower] or
              player[:tutorial] != old[:tutorial] or
                player[:achievements] != old[:achievements] ->
              save(s, player)

            true ->
              s |> Map.put(:player, player) |> mark_dirty()
          end

        if player != old, do: broadcast(s, player, origin)
        left_trade(s.user_id, old, player)
        Enum.each(notes, &notify(s, &1))
        reply({result, player}, s)

      :too_fast ->
        reply({%{ok: false}, s.player}, s)
    end
  end

  defp handle({:command, %{"rid" => rid} = cmd, origin}, from, s)
       when is_binary(rid) and byte_size(rid) in 1..64 do
    case s.rids do
      %{^rid => result} ->
        reply({result, s.player}, s)

      _ ->
        case handle({:command, Map.delete(cmd, "rid"), origin}, from, s) do
          {:reply, {result, _player} = value, s, t} ->
            {:reply, value, remember_rid(s, rid, result), t}

          other ->
            other
        end
    end
  end

  defp handle({:command, cmd, origin}, _from, s) do
    case take(s, :acts, @act_ms, @act_burst) do
      {:ok, s} -> run_command(s, cmd, origin)
      :too_fast -> reply({%{ok: false, msg: "Thao tác quá nhanh."}, s.player}, s)
    end
  end

  defp handle({:shared_end, info}, _from, %{player: %{battle: %{over: false} = b}} = s) do
    if b[:encounter][:shared] == info.key do
      old = s.player
      p = shared_reward(old, info)
      {_, p} = Engine.finish_win(p)
      log = p.battle.log ++ [%{text: "Đồng đội ra đòn kết liễu!", kind: "info"}]
      p = put_in(p.battle.log, Enum.take(log, -60))
      p = battle_over(s, old, p)
      s = save(s, p)
      broadcast(s, p, nil)
      track_guild(old, p, nil)
      reply(:ok, s)
    else
      reply(:ok, s)
    end
  end

  defp handle({:shared_end, _info}, _from, s), do: reply(:ok, s)

  defp handle({:slay_begin, _info}, _from, %{player: nil} = s),
    do: reply({:error, "Chưa có nhân vật."}, s)

  defp handle({:slay_begin, %{fight: f, foe: foe}}, _from, s) do
    p = s.player

    cond do
      p.battle != nil ->
        reply({:error, "#{p.name} đang trong trận đấu."}, s)

      p.hp <= 0 ->
        reply({:error, "#{p.name} đang gục ngã."}, s)

      p.pos.map != f.map ->
        reply({:error, "#{p.name} đã rời bản đồ."}, s)

      true ->
        mp = Maps.get(f.map)
        {_, p2} = Engine.start_with_monster(p, mp.zone || 0, foe)
        enc = %{slay: f.id, foe: f.foe, mine: f.mine, until: f.until}

        b =
          Map.merge(p2.battle, %{
            zone: mp.zone,
            encounter: enc,
            live: true,
            place: mp.name,
            theme: mp[:theme]
          })

        text =
          if f.mine,
            do: "🗡 Bạn đồ sát #{foe.name}! Bạn ra đòn trước.",
            else: "⚠ #{foe.name} đồ sát bạn! Bỏ chạy tính như gục ngã."

        b = %{b | log: [%{text: text, kind: "bad"}]}
        p2 = %{p2 | battle: b}
        left_trade(s.user_id, p, p2)
        s = save(s, p2)
        broadcast(s, p2, nil)
        reply(:ok, s)
    end
  end

  defp handle({:slay_cancel, id}, _from, %{player: %{battle: %{encounter: %{slay: id}}} = p} = s) do
    p = %{p | battle: nil}
    s = save(s, p)
    broadcast(s, p, nil)
    reply(:ok, s)
  end

  defp handle({:slay_cancel, _id}, _from, s), do: reply(:ok, s)

  defp handle(:slay_auto, _from, %{player: %{battle: %{over: false, live: true}}} = s),
    do: run_command_(s, %{"act" => "attack", "auto" => true}, nil)

  defp handle(:slay_auto, _from, s), do: reply(:ok, s)

  defp handle({:hold, _ref}, _from, %{player: nil} = s),
    do: reply({:error, "Chưa có nhân vật."}, s)

  defp handle({:hold, ref}, _from, s) do
    timer = Process.send_after(self(), {:hold_expired, ref}, @hold_ms)
    reply({:ok, s.player}, %{s | held: {ref, timer}})
  end

  defp handle({:admin, _fun, _ref}, _from, %{player: nil} = s),
    do: reply({:error, "Người này chưa có nhân vật."}, s)

  defp handle({:admin, fun, _ref}, _from, s) do
    old = s.player

    case fun.(old) do
      {:ok, p, msg} ->
        s = save(s, p)
        broadcast(s, p, nil)

        if map_size(s.tabs) > 0 && World.info(p) != World.info(old),
          do: World.refresh(p, s.user_id)

        reply({:ok, msg}, s)

      {:error, _} = err ->
        reply(err, s)
    end
  end

  defp handle({:world_boss_end, _info}, _from, %{player: nil} = s), do: reply(:ok, s)

  defp handle({:world_boss_end, info}, _from, s) do
    old = s.player
    p = s.player

    p =
      if World.world_battle?(p),
        do:
          end_world_battle(
            p,
            info.result,
            if(info.result == "win",
              do: "#{WorldBoss.name()} đã gục ngã!",
              else: "#{WorldBoss.name()} đã bay đi."
            )
          ),
        else: p

    # lọt top 3 sát thương (cho thành tựu), kể cả khi không online
    p =
      if info.reward && info.reward[:top],
        do: Map.put(p, :boss_top, (Map.get(p, :boss_top) || 0) + 1),
        else: p

    {p, notice} =
      case info.reward do
        nil ->
          {p, if(info.result == "win", do: nil, else: "#{WorldBoss.name()} đã bay đi.")}

        # không online: gửi thưởng qua hộp thư, lần sau vào game thấy ngay
        r when map_size(s.tabs) == 0 ->
          xp = min(r.xp, 3 * Engine.xp_to_next(p.level))

          Mailbox.send(s.user_id, %{
            subject: "Thưởng trùm thế giới",
            body: "#{WorldBoss.name()} đã gục ngã. Bạn gây #{r.share}% sát thương.",
            gold: r.gold,
            xp: xp,
            items: r.items
          })

          {p, nil}

        r ->
          # không cho người cấp thấp nhảy vọt quá nhiều cấp nhờ một trận
          xp = min(r.xp, 3 * Engine.xp_to_next(p.level))
          p = %{p | gold: p.gold + r.gold}
          p = Enum.reduce(r.items, p, fn {id, n}, p -> Engine.add_item(p, id, n) end)
          {levels, p} = Engine.gain_xp(p, xp)

          text =
            "Thưởng trùm thế giới (#{r.share}% sát thương): +#{r.gold} vàng, +#{xp} kinh nghiệm#{Enum.map_join(r.items, fn {id, _} -> ", " <> HacLong.Game.Data.item(id).name end)}."

          p =
            if World.world_battle?(p) do
              b = p.battle
              reward = %{xp: xp, gold: r.gold, items: Map.keys(r.items), levels: levels}

              %{
                p
                | battle: %{
                    b
                    | reward: reward,
                      log: Enum.take(b.log ++ [%{text: text, kind: "win"}], -60)
                  }
              }
            else
              p
            end

          {p, text}
      end

    s = if p != old, do: save(s, p), else: s
    broadcast(s, p, nil)
    if notice, do: Phoenix.PubSub.broadcast(HacLong.PubSub, topic(s.user_id), {:notice, notice})
    reply(:ok, s)
  end

  # Tạo nhân vật: kiểm tra tên hợp lệ và chưa ai dùng (cần database nên làm ở đây).
  defp run_command(%{player: nil} = s, %{"act" => "create"} = cmd, origin) do
    with {:ok, name} <- Names.validate(cmd["name"]),
         false <- Characters.name_taken?(name) do
      run_command_(s, Map.put(cmd, "name", name), origin)
    else
      {:error, msg} -> reply({%{ok: false, msg: msg}, nil}, s)
      true -> reply({%{ok: false, msg: "Tên này đã có người dùng."}, nil}, s)
    end
  rescue
    # hai người cùng lấy một tên đúng lúc: ràng buộc duy nhất trong database chặn người sau
    Ecto.ConstraintError -> reply({%{ok: false, msg: "Tên này đã có người dùng."}, nil}, s)
  end

  # Mở thư: đánh dấu thư đã nhận và ghi nhân vật trong cùng một transaction.
  defp run_command(%{player: p} = s, %{"act" => act} = cmd, origin)
       when p != nil and act in ["mail_claim", "mail_claim_all"] do
    save = &Characters.save!(s.user_id, &1)

    result =
      if act == "mail_claim",
        do: Mailbox.claim(s.user_id, cmd["id"], p, save),
        else: Mailbox.claim_all(s.user_id, p, save)

    case result do
      {:ok, msg, player} ->
        s = cancel_flush(%{s | player: player, dirty: false})
        broadcast(s, player, origin)
        reply({%{ok: true, msg: msg}, player}, s)

      {:error, msg} ->
        reply({%{ok: false, msg: msg}, p}, s)
    end
  end

  # Lập bang, góp quỹ: trừ vàng và ghi nhân vật trong cùng transaction với bảng bang hội.
  defp run_command(%{player: p} = s, %{"act" => act} = cmd, origin)
       when p != nil and act in ["guild_create", "guild_donate"] do
    save = &Characters.save!(s.user_id, &1)

    result =
      if act == "guild_create",
        do: Guilds.create(s.user_id, cmd["name"], cmd["tag"], p, save),
        else: Guilds.donate(s.user_id, cmd["amount"], p, save)

    case result do
      {:ok, msg, player} ->
        player = with_guild(player, s.user_id)
        s = cancel_flush(%{s | player: player, dirty: false})
        broadcast(s, player, origin)
        reply({%{ok: true, msg: msg}, player}, s)

      {:error, msg} ->
        reply({%{ok: false, msg: msg}, p}, s)
    end
  end

  # Chợ: rao bán, mua, rút về; đồ và vàng đổi trong cùng transaction với bảng chợ.
  defp run_command(%{player: p} = s, %{"act" => act} = cmd, origin)
       when p != nil and act in ["market_sell", "market_buy", "market_cancel"] do
    save = &Characters.save!(s.user_id, &1)

    result =
      cond do
        p.battle ->
          {:error, "Đang trong trận đấu."}

        World.near_npc(p, ["market"]) == nil ->
          {:error, "Hãy đến gặp Chủ Chợ ở Làng."}

        act == "market_sell" ->
          Market.list(s.user_id, p, cmd["id"], cmd["count"] || 1, cmd["price"], save)

        act == "market_buy" ->
          Market.buy(s.user_id, p, cmd["listing"], save)

        true ->
          Market.cancel(s.user_id, p, cmd["listing"], save)
      end

    case result do
      {:ok, msg, player} ->
        s = cancel_flush(%{s | player: player, dirty: false})
        broadcast(s, player, origin)
        reply({%{ok: true, msg: msg}, player}, s)

      {:error, msg} ->
        reply({%{ok: false, msg: msg}, p}, s)
    end
  end

  defp run_command(s, cmd, origin), do: run_command_(s, cmd, origin)

  defp run_command_(s, cmd, origin) do
    old = s.player
    {result, player} = run(s, old, cmd)
    # nhân vật vừa tạo cũng có ngay việc hằng ngày
    player =
      s |> after_command(old, player, cmd) |> ds_record(s) |> Daily.ensure(Daily.today())

    # nhân vật vừa tạo: gắn thông tin bang (chưa có) như lúc nạp từ database
    player = if player && old == nil, do: with_guild(player, s.user_id), else: player
    {player, notes} = checks(player)

    left_trade(s.user_id, old, player)

    s =
      if player != old do
        broadcast(s, player, origin)
        # đổi đồ, lên cấp, dắt thú khác: người cùng bản đồ thấy ngay
        if player && old && map_size(s.tabs) > 0 && World.info(player) != World.info(old),
          do: World.refresh(player, s.user_id)

        if player, do: save(s, player), else: delete(s)
      else
        s
      end

    Enum.each(notes, &notify(s, &1))
    track_guild(old, player, result)

    # ép đồ / ghép cánh thành công: báo cả server (không gửi kèm cho client)
    {announce, result} = if is_map(result), do: Map.pop(result, :announce), else: {nil, result}
    if announce, do: HacLong.Chat.system(announce)

    reply({result, player}, s)
  end

  # Góp tiến độ nhiệm vụ bang (không chờ: ghi database ngoài tiến trình này).
  defp track_guild(old, %{guild: %{id: gid}} = new, result) when old != nil do
    events =
      %{
        "kill" => new.kills - old.kills,
        "fish" => (Map.get(new, :fish_caught) || 0) - (Map.get(old, :fish_caught) || 0),
        "gather" => if(is_map(result) and result[:gather], do: 1, else: 0),
        "boss" => if(zone_boss_win?(old, new), do: 1, else: 0)
      }
      |> Map.filter(fn {_, n} -> n > 0 end)

    if events != %{}, do: Task.start(fn -> GuildQuests.progress(gid, events) end)
    :ok
  end

  defp track_guild(_old, _new, _result), do: :ok

  defp zone_boss_win?(old, new) do
    b = new.battle

    b && b.over && b.result == "win" && b.monster.boss && !b.monster[:world] &&
      !b.monster[:pvp] && !(old.battle && old.battle.over)
  end

  # Hướng dẫn người mới và thành tựu: tính lại sau mỗi thay đổi, trả về các thông báo mới.
  defp checks(player) do
    {player, tut} = Tutorial.check(player)
    {player, ach} = Achievements.check(player)
    {player, Enum.reject([tut, ach], &is_nil/1)}
  end

  # Thông báo riêng cho người chơi này (hiện ở mọi tab đang mở), vd. bước hướng dẫn mới.
  defp notify(_s, nil), do: :ok

  defp notify(s, text),
    do: Phoenix.PubSub.broadcast(HacLong.PubSub, topic(s.user_id), {:notice, text})

  # Đánh trùm thế giới: máu trùm là máu chung ở HacLong.WorldBoss. Trước lượt đánh lấy máu
  # mới nhất, sau lượt đánh báo sát thương vừa gây.
  @strikes ~w(attack skill potion mana flee)

  defp run(s, %{battle: %{over: false} = b} = p, %{"act" => act} = cmd) when act in @strikes do
    cond do
      b[:live] -> slay_strike(s, p, cmd)
      World.world_battle?(p) -> world_strike(s, p, cmd)
      key = b[:encounter][:shared] -> shared_strike(s, p, cmd, key)
      true -> Commands.run(p, cmd)
    end
  end

  # Thách đấu (đấu trường): đối thủ là bản sao chỉ số dựng từ database.
  defp run(s, p, %{"act" => "pvp_challenge"} = cmd) do
    with nil <- p.battle && {:error, "Đang trong trận đấu."},
         true <- p.hp > 0 || {:error, "Bạn cần hồi máu trước."},
         {:ok, m} <- Arena.challenge(s.user_id, cmd["uid"]) do
      {r, p2} = Engine.start_with_monster(p, 1, m)
      enc = %{pvp: m.pvp, hp: p.hp, gold: p.gold, deaths: p.deaths}
      {Map.put(r, :msg, "Thách đấu #{m.name}!"), put_in(p2.battle[:encounter], enc)}
    else
      {:error, msg} -> {%{ok: false, msg: msg}, p}
    end
  end

  defp run(_s, p, cmd), do: Commands.run(p, cmd)

  # Đồ sát: chỉ ra đòn ở lượt của mình; máu hai bên lấy từ HacLong.Slay.
  defp slay_strike(s, p, %{"act" => act} = cmd) do
    uid = s.user_id

    case Slay.peek(uid) do
      nil ->
        b = p.battle
        log = Enum.take(b.log ++ [%{text: "Trận đồ sát đã kết thúc.", kind: "info"}], -60)
        {%{ok: true}, %{p | battle: %{b | over: true, result: "fled", log: log}}}

      %{mine: false} ->
        {%{ok: false, msg: "Chưa tới lượt bạn."}, p}

      _f when act == "flee" ->
        Slay.flee(uid)
        {%{ok: true, msg: "Bạn bỏ chạy: tính như gục ngã."}, p}

      f ->
        p = %{p | hp: f.hp} |> put_in([:battle, :monster, :hp], f.foe_hp)

        case Commands.run(p, Map.delete(cmd, "auto")) do
          {%{ok: false}, _} = r ->
            r

          {r, p2} ->
            case Slay.acted(uid, p2.hp, p2.battle.monster.hp, cmd["auto"] == true) do
              {:ok, v} ->
                enc = %{p2.battle.encounter | mine: v.mine, until: v.until}
                {r, put_in(p2.battle.encounter, enc)}

              {:error, msg} ->
                {%{ok: false, msg: msg}, p}
            end
        end
    end
  end

  defp world_strike(s, p, cmd) do
    case WorldBoss.hp() do
      nil ->
        {%{ok: true}, end_world_battle(p, "fled", "#{WorldBoss.name()} đã rời khỏi Tế Đàn.")}

      hp ->
        p = put_in(p.battle.monster.hp, hp)
        {result, p2} = Commands.run(p, cmd)
        dealt = if p2.battle, do: hp - p2.battle.monster.hp, else: 0

        case dealt > 0 && WorldBoss.hit(s.user_id, p.name, dealt) do
          false ->
            {result, p2}

          {:alive, left} ->
            {result, put_in(p2.battle.monster.hp, left)}

          :killed ->
            p2 = put_in(p2.battle.monster.hp, 0)

            # người khác vừa đánh trước nên máu chung hết sớm hơn máu mình thấy
            if p2.battle.over,
              do: {result, p2},
              else:
                {%{ok: true, result: "win"},
                 end_world_battle(p2, "win", "🏆 #{WorldBoss.name()} gục ngã dưới đòn của bạn!")}

          :gone ->
            {%{ok: true},
             end_world_battle(p2, "win", "#{WorldBoss.name()} đã bị người khác hạ gục.")}
        end
    end
  end

  # Trận đánh chung với tổ đội: máu quái ở HacLong.Party, thưởng chia theo số người.
  defp shared_strike(s, p, cmd, key) do
    case Party.fight(key) do
      # không có tổ đội hoặc mọi người khác đã rời: đánh như thường
      nil ->
        Commands.run(p, cmd)

      f ->
        p = p |> put_in([:battle, :monster, :hp], f.hp) |> shared_reward(f)
        {result, p2} = Commands.run(p, cmd)
        dealt = if p2.battle, do: f.hp - p2.battle.monster.hp, else: 0

        case dealt > 0 && Party.hit(key, s.user_id, dealt) do
          false ->
            {result, p2}

          {:alive, left} ->
            {result, put_in(p2.battle.monster.hp, left)}

          {:killed, _n} ->
            if p2.battle.over, do: {result, p2}, else: shared_win(p2)

          # đồng đội vừa hạ trước
          :gone ->
            shared_win(p2)
        end
    end
  end

  defp shared_win(p) do
    {r, p} = Engine.finish_win(p)
    {Map.put(r, :result, "win"), p}
  end

  # thưởng mỗi người = thưởng gốc × `RULES.party.share_bonus` / số người (một người thì giữ nguyên)
  defp shared_reward(p, %{n: n, xp: xp, gold: gold}) when n > 1 do
    k = @share_bonus / n

    p
    |> put_in([:battle, :monster, :xp], round(xp * k))
    |> put_in([:battle, :monster, :gold], round(gold * k))
  end

  defp shared_reward(p, _), do: p

  defp end_world_battle(%{battle: %{over: false}} = p, result, text) do
    b = p.battle
    b = if result == "win", do: put_in(b.monster.hp, 0), else: b
    entry = %{text: text, kind: if(result == "win", do: "win", else: "info")}
    %{p | battle: %{b | over: true, result: result, log: Enum.take(b.log ++ [entry], -60)}}
  end

  defp end_world_battle(p, _result, _text), do: p

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _}, s) do
    s = %{s | tabs: Map.delete(s.tabs, ref)}

    if map_size(s.tabs) == 0 do
      World.leave(s.player, s.user_id)

      # rớt mạng / đóng hết tab: hẹn rời tổ đội, hủy giao dịch và lời mời cược đang dính
      HacLong.Party.away(s.user_id)
      uid = s.user_id
      Task.start(fn -> HacLong.Trade.cancel(uid) end)
      Task.start(fn -> HacLong.PkBet.disconnect(uid) end)
      Characters.put_reason("MOVE")
      {:noreply, flush(s), @idle_timeout}
    else
      {:noreply, s}
    end
  end

  def handle_info(:flush, s) do
    Characters.put_reason("MOVE")
    {:noreply, flush(%{s | flush_timer: nil}), timeout(s)}
  end

  # giao dịch giữ quá lâu (tiến trình giao dịch chết giữa chừng): tự nhả, không đổi gì
  def handle_info({:hold_expired, ref}, %{held: {ref, _}} = s) do
    Logger.warning("Session #{s.user_id}: giao dịch giữ quá #{@hold_ms} ms, tự nhả")
    s = %{s | held: nil}
    s = if s.dirty, do: mark_dirty(s), else: s
    {:noreply, replay(s), timeout(s)}
  end

  def handle_info({:hold_expired, _ref}, s), do: {:noreply, s, timeout(s)}

  def handle_info(:timeout, %{held: nil} = s) do
    if map_size(s.tabs) == 0, do: {:stop, :normal, flush(s)}, else: {:noreply, s}
  end

  def handle_info(:timeout, s), do: {:noreply, s}

  def handle_info({:EXIT, _pid, _reason}, s), do: {:noreply, s, timeout(s)}

  @impl true
  def terminate(_reason, s) do
    Characters.put_reason("MOVE")
    flush(s)
  end

  # ---------- Nội bộ ----------

  # "Thao tác quá nhanh" không ghi nhớ: gửi lại cùng mã sau đó vẫn chạy được.
  defp remember_rid(s, _rid, %{ok: false, msg: "Thao tác quá nhanh."}), do: s

  defp remember_rid(s, rid, result) do
    order = :queue.in(rid, s.rid_order)

    if :queue.len(order) > @rid_memory do
      {{:value, old}, order} = :queue.out(order)
      %{s | rids: s.rids |> Map.delete(old) |> Map.put(rid, result), rid_order: order}
    else
      %{s | rids: Map.put(s.rids, rid, result), rid_order: order}
    end
  end

  defp reply(value, s), do: {:reply, value, s, timeout(s)}

  # Còn tab đang mở thì không tự tắt (nhân vật vẫn đứng trên bản đồ).
  defp timeout(%{tabs: tabs}) when map_size(tabs) > 0, do: :infinity
  defp timeout(_), do: @idle_timeout

  defp run_move(%{player: nil} = s, _cmd), do: {%{ok: false, msg: "Chưa có nhân vật."}, s.player}

  # Phase 15a: bảng chọn bản đồ (tốn vàng, nhật ký vàng TRAVEL)
  defp run_move(s, %{"act" => "travel"} = cmd) do
    Characters.put_reason("TRAVEL", cmd["to"])
    World.travel(s.player, s.user_id, cmd["to"])
  end

  defp run_move(s, %{"act" => "teleport"} = cmd),
    do: World.teleport(s.player, s.user_id, cmd["to"])

  defp run_move(s, cmd),
    do: World.move(s.player, s.user_id, cmd["dir"], cmd["confirm"] == true)

  # Quảng Trường Quỷ vừa kết thúc (`DevilSquare.finish/3` đặt `ds_result`): ghi bảng xếp hạng ngày
  defp ds_record(%{ds_result: %{score: score}} = player, s) do
    HacLong.DevilSquareBoard.record(Daily.today(), s.user_id, player.name, score)
    Map.delete(player, :ds_result)
  end

  defp ds_record(player, _s), do: player

  defp after_command(s, old, player, cmd) do
    cond do
      # trận vừa kết thúc: cập nhật quái trên bản đồ, gục ngã thì về Nhà
      player && old && old.battle && not old.battle.over && player.battle && player.battle.over ->
        battle_over(s, old, player)

      # Phase 13: máu quái đang đánh trên bản đồ chung, mọi người cùng bản đồ thấy như nhau
      player && player.battle && match?(%{map: _, mid: _}, player.battle[:encounter]) ->
        %{map: map_id, mid: mid} = player.battle.encounter
        m = player.battle.monster
        MapServer.hp(map_id, mid, round(max(m.hp, 0) * 100 / max(m.maxHp, 1)))
        player

      cmd["act"] == "create" and player && old == nil ->
        if map_size(s.tabs) > 0, do: World.enter(player, s.user_id)
        player

      # vừa vào tháp: rời bản đồ Làng (người khác không thấy mình nữa)
      old && player && player.pos.map == Tower.map_id() && old.pos.map != Tower.map_id() ->
        World.leave(old, s.user_id)
        player

      cmd["act"] == "reset" and old && player == nil ->
        World.leave(old, s.user_id)
        player

      true ->
        player
    end
  end

  # Trận đấu trường xong: đổi điểm. Thua (gục ngã) tính như chết thường: mất vàng, về Nhà
  # (Engine đã trừ vàng/máu); bỏ chạy thì máu, vàng như trước trận.
  defp battle_over(s, _old, %{battle: %{encounter: %{pvp: target} = enc} = b} = player) do
    r = Arena.finish(s.user_id, target, b.result)
    # chiến bang: thắng thành viên bang địch thì ghi điểm cho bang
    war = r.won && HacLong.GuildWars.record(s.user_id, target)

    player =
      cond do
        r.won ->
          %{player | gold: player.gold + r.gold}

        b.result == "lose" ->
          World.leave(player, s.user_id)
          %{player | pos: HacLong.World.Maps.home_spawn()}

        true ->
          %{player | hp: max(1, enc.hp), gold: enc.gold, deaths: enc.deaths}
      end

    sign = fn d -> if d >= 0, do: "+#{d}", else: "#{d}" end

    text =
      if r.won,
        do:
          "🏟 Thắng! Điểm đấu trường #{sign.(r.delta)}, thưởng #{r.gold} vàng." <>
            if(war, do: " ⚔ Chiến bang: bang bạn +1 điểm.", else: ""),
        else:
          if(b.result == "lose",
            do: "🏟 Thua trận đấu trường (điểm #{sign.(r.delta)}).",
            else: "🏟 Bỏ chạy khỏi đấu trường (điểm #{sign.(r.delta)}). Không mất vàng."
          )

    reward = %{xp: 0, gold: r.gold, items: [], levels: 0}

    player = %{
      player
      | battle: %{b | reward: reward, log: Enum.take(b.log ++ [%{text: text, kind: "win"}], -60)}
    }

    Phoenix.PubSub.broadcast(
      HacLong.PubSub,
      topic(target),
      {:notice,
       "🏟 #{player.name} thách đấu bạn ở đấu trường và #{if r.won, do: "thắng", else: "thua"} (điểm của bạn #{sign.(r.their_delta)})."}
    )

    player
  end

  # Trận vừa kết thúc: cập nhật quái trên bản đồ, gục ngã thì về Nhà, tính nhiệm vụ...
  defp battle_over(s, old, player) do
    player = player |> Tower.after_battle() |> World.finish_encounter(s.user_id)

    # lần đầu hạ Hắc Long: ghi lại thời điểm cho bảng xếp hạng
    player =
      if player.victory and not old.victory,
        do: Map.put(player, :victory_at, DateTime.truncate(DateTime.utc_now(), :second)),
        else: player

    if player.battle.result == "win" do
      player
      |> guild_xp()
      |> Quests.on_kill(player.battle.monster.id)
      |> Daily.on_kill(player.battle.monster.id, player.battle.zone)
    else
      player
    end
  end

  # Bang từ cấp 2: thêm kinh nghiệm mỗi trận thắng.
  defp guild_xp(%{guild: %{level: lv}} = p) when lv > 1 do
    bonus = round(p.battle.monster.xp * Guilds.xp_bonus(lv))

    if bonus > 0 do
      {_levels, p} = Engine.gain_xp(p, bonus)
      log = p.battle.log ++ [%{text: "Bang hội: +#{bonus} kinh nghiệm.", kind: "good"}]
      put_in(p.battle.log, Enum.take(log, -60))
    else
      p
    end
  end

  defp guild_xp(p), do: p

  # Xô token: mỗi `every_ms` hồi một lượt, tối đa `burst` lượt.
  defp take(s, key, every_ms, burst) do
    {tokens, at} = Map.fetch!(s, key)
    t = now()
    tokens = min(burst, tokens + (t - at) / every_ms)

    if tokens >= 1,
      do: {:ok, Map.put(s, key, {tokens - 1, t})},
      else: :too_fast
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp broadcast(s, player, origin) do
    Phoenix.PubSub.broadcast(HacLong.PubSub, topic(s.user_id), {:player, player, origin})
  end

  # giao dịch trực tiếp tự hủy khi đổi bản đồ hoặc vào trận (Phase 5, E5); chạy riêng vì Trade
  # có thể đang giữ Session này
  defp left_trade(uid, %{pos: %{map: m}} = old, %{pos: %{map: m2}} = new)
       when m != m2 or (old.battle == nil and new.battle != nil) do
    why = if m != m2, do: "đã rời bản đồ", else: "đã vào trận đánh"
    Task.start(fn -> HacLong.Trade.left(uid, why) end)
  end

  defp left_trade(_uid, _old, _new), do: :ok

  defp save(s, player) do
    Characters.save!(s.user_id, player)
    cancel_flush(%{s | player: player, dirty: false})
  end

  defp delete(s) do
    Characters.delete!(s.user_id)
    cancel_flush(%{s | player: nil, dirty: false})
  end

  defp mark_dirty(%{flush_timer: nil} = s),
    do: %{s | dirty: true, flush_timer: Process.send_after(self(), :flush, @flush_ms)}

  defp mark_dirty(s), do: %{s | dirty: true}

  defp cancel_flush(%{flush_timer: nil} = s), do: s

  defp cancel_flush(s) do
    Process.cancel_timer(s.flush_timer)
    %{s | flush_timer: nil}
  end

  # đang bị giao dịch giữ: không ghi (giao dịch sẽ ghi nhân vật mới), để sau khi nhả
  defp flush(%{held: {_, _}} = s), do: s
  defp flush(%{dirty: true, player: p} = s) when p != nil, do: save(s, p)
  defp flush(s), do: s
end

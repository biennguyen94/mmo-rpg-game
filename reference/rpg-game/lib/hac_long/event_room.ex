defmodule HacLong.EventRoom do
  @moduledoc """
  Phòng sự kiện đánh chung kiểu MU (DECISIONS "Sự kiện đánh chung theo phòng"): Quảng Trường Quỷ, Lâu Đài Máu (phòng
  theo đợt mở + mốc chuyển sinh `RULES.event_rooms` + bậc cấp) và Kalima (phòng của một tổ đội). Mỗi phòng một tiến
  trình: chung bản đồ, chung quái, chung máu quái; ai cùng phòng cũng thấy nhau.

  - Bản đồ, quái, bước / đợt và giờ kết thúc là của phòng; Session giữ bản sao ở `p.tower` (cùng dạng lượt riêng, thêm
    `room`, `k`) để đi, chạm quái như cũ. Điểm (`ds.score`) và số quái tự hạ (`bc.mine`, `kal.mine`) là của từng người.
  - Quái mạnh theo mốc `k` của phòng (`Engine.scale_event/2`), không theo người đánh.
  - Đánh: `engage/4` lấy máu chung, `hit/4` trừ máu sau mỗi đòn. Người hạ nhận thưởng trận và điểm; người khác đang đánh
    con đó nhận vàng / kinh nghiệm theo phần sát thương (`{:room_kill, ...}` gửi Session).
  - Kết thúc (hết giờ, qua hết đợt, hạ trùm): gửi `{:room_end, id, info}` cho Session từng người (thưởng ở
    `settle/2`); người không online thì kết thúc ở bước đi sau (phòng không còn: `alive?/1`).

  Session gọi phòng (`GenServer.call`); phòng chỉ `cast` lại Session nên không khóa chéo.
  """
  use GenServer, restart: :temporary

  alias HacLong.Game.{BloodCastle, Data, DevilSquare, EventRooms, Kalima, Tower}

  @flush_ms 100
  @kinds %{"ds" => :ds, "bc" => :bc, "kal" => :kal}
  # điểm / số quái của riêng từng người, không lấy từ phòng khi đồng bộ
  @personal [:score, :mine]

  def topic(id), do: "event_room:#{id}"

  defp via(id), do: {:via, Registry, {__MODULE__.Registry, id}}

  def child_spec(arg),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}, restart: :temporary}

  def start_link({id, spec}), do: GenServer.start_link(__MODULE__, {id, spec}, name: via(id))

  @doc "Phòng `id` còn chạy."
  def alive?(id) when is_binary(id), do: Registry.lookup(__MODULE__.Registry, id) != []
  def alive?(_), do: false

  # ---------- Vào ----------

  @doc """
  Lệnh vào sự kiện ở Người Gác Tháp (`act`: `ds_enter`, `bc_enter`, `kal_enter`) của người chơi `uid`: vào phòng
  chung (Kalima: phòng tổ đội đang mở thì vào không tốn vé). Trả `{kết_quả, nhân_vật}`.
  """
  def enter("ds_enter", p, uid),
    do: DevilSquare.enter(p, DateTime.utc_now(), &join_band(&1, p, uid))

  def enter("bc_enter", p, uid),
    do: BloodCastle.enter(p, DateTime.utc_now(), &join_band(&1, p, uid))

  def enter("kal_enter", p, uid) do
    party = HacLong.Party.of(uid)
    id = if party, do: "kal:p#{party.id}", else: "kal:u#{uid}"

    if party && alive?(id),
      do: Kalima.join(p, fn -> join(id, nil, uid, HacLong.World.info(p)) end),
      else:
        Kalima.enter(p, DateTime.utc_now(), fn spec ->
          # quái Kalima mạnh theo người chuyển sinh nhiều nhất trong tổ đội
          k = min(party_rebirths(party, p), Data.rules().character.max_rebirths)
          spec = Map.merge(spec, %{k: k, label: if(party, do: "Tổ đội", else: "Một mình")})
          join(id, spec, uid, HacLong.World.info(p))
        end)
  end

  # phòng Quảng Trường / Lâu Đài: theo đợt mở, mốc chuyển sinh, bậc cấp
  defp join_band(%{kind: kind, slot: slot, level: level} = spec, p, uid) do
    band = EventRooms.band(Map.get(p, :rebirths))
    id = "#{kind}:#{slot}:#{band}:#{level}"
    join(id, Map.merge(spec, %{k: EventRooms.k(band), band: band}), uid, HacLong.World.info(p))
  end

  defp party_rebirths(nil, p), do: Map.get(p, :rebirths) || 0

  defp party_rebirths(%{members: uids}, p) do
    import Ecto.Query

    db =
      HacLong.Repo.all(
        from c in HacLong.Game.Character, where: c.user_id in ^uids, select: c.rebirths
      )

    Enum.max([Map.get(p, :rebirths) || 0 | Enum.map(db, &(&1 || 0))])
  end

  @doc """
  Vào phòng `id` (chưa có thì mở với `spec` `%{kind, k, level, n?}`; `spec` nil: chỉ vào phòng đang mở). `info`: những
  gì người khác thấy (`World.info/1`). Trả `{:ok, trạng_thái_tháp}` hoặc `{:error, lý_do}`.
  """
  def join(id, spec, uid, info) do
    if spec do
      case DynamicSupervisor.start_child(__MODULE__.Supervisor, {__MODULE__, {id, spec}}) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    call(id, {:join, uid, info}) || {:error, "Phòng đã đóng."}
  end

  # ---------- Trong phòng ----------

  @doc """
  Chạm quái `mid` (máu tối đa `max` theo mốc phòng): `{:ok, máu_hiện_tại, số_người_đang_đánh}` hoặc `{:error, lý_do}`.
  Từ lúc đó tới `disengage/3`, mỗi đòn của bất kỳ ai lên con này đẩy máu mới xuống màn trận (`{:shared_hp, key/2, ...}`,
  như đánh chung tổ đội).
  """
  def engage(id, uid, mid, max),
    do: call(id, {:engage, uid, mid, max}) || {:error, "Sự kiện đã kết thúc."}

  @doc "Trận của `uid` với quái `mid` đã xong (thua, bỏ chạy, thắng): thôi nhận máu, bớt số người đang đánh."
  def disengage(id, uid, mid), do: GenServer.cast(via(id), {:disengage, uid, mid})

  @doc "Khóa trận chung của quái `mid` trong phòng `id` (client so với `encounter.room_key`)."
  def key(id, mid), do: "room:#{id}:#{mid}"

  @doc "Trận chung với quái `mid`: `%{hp, max, mine}` (`mine`: sát thương của `uid`) hoặc nil (quái đã bị hạ)."
  def fight(id, mid, uid), do: call(id, {:fight, mid, uid})

  @doc """
  `uid` gây `dmg` sát thương lên quái `mid`: `{:alive, máu_còn}`, `{:killed, %{pts, role, share, end}}` (người này hạ;
  `end`: phòng kết thúc, thưởng ở `settle/2`) hoặc `:gone` (người khác hạ trước).
  """
  def hit(id, uid, mid, dmg), do: call(id, {:hit, uid, mid, dmg}) || :gone

  @doc "Bước tới ô `(x, y)`."
  def moved(id, uid, x, y), do: GenServer.cast(via(id), {:move, uid, x, y})

  @doc """
  Bước lên cầu thang Quảng Trường: `{:error, lý_do}`, `{:ok, trạng_thái_tháp}` (cả phòng sang đợt sau) hoặc
  `{:cleared, info}` (qua hết đợt: người khác nhận `{:room_end, ...}`, người này tự `settle/2`).
  """
  def climb(id, uid), do: call(id, {:climb, uid}) || {:error, "Sự kiện đã kết thúc."}

  @doc "Rời phòng (tự ra, gục ngã)."
  def leave(id, uid), do: call(id, {:leave, uid})

  @doc "Trạng thái bản đồ cho kênh (`map`, người trong phòng), dạng như `MapServer.snapshot/1`."
  def snapshot(id), do: call(id, :snapshot)

  defp call(id, msg) do
    GenServer.call(via(id), msg)
  catch
    :exit, _ -> nil
  end

  # ---------- Hàm thuần dùng ở Session / World ----------

  @doc "Sự kiện của trạng thái tháp phòng chung: `:ds | :bc | :kal`."
  def kind(%{ds: _}), do: :ds
  def kind(%{bc: _}), do: :bc
  def kind(%{kal: _}), do: :kal

  @doc "Bản sao tháp của người chơi `old` nhận trạng thái mới `shared` của phòng: giữ điểm / số quái của riêng mình."
  def merge(old, shared) do
    k = kind(shared)
    mine = Map.take(Map.get(old, k) || %{}, @personal)
    shared |> Map.put(k, Map.merge(shared[k], mine))
  end

  @doc """
  Phòng kết thúc (`info` từ `{:room_end, ...}` hoặc kết quả `climb/2`, `hit/4`): trả thưởng như lượt riêng. Trả
  `{kết_quả, nhân_vật}`; Quảng Trường, Lâu Đài / Kalima không thắng thì về Làng.
  """
  def settle(%{tower: %{ds: _}} = p, info),
    do: DevilSquare.finish(p, info.why, info[:cleared] == true)

  def settle(%{tower: %{bc: %{done: true}}} = p, _info), do: {%{ok: true, msg: nil}, p}

  def settle(%{tower: %{bc: _}} = p, %{success: true} = info),
    do: BloodCastle.room_finish(p, info.top == true, info.share)

  def settle(%{tower: %{bc: _}} = p, _info), do: BloodCastle.finish(p, false)
  def settle(%{tower: %{kal: %{done: true}}} = p, _info), do: {%{ok: true, msg: nil}, p}
  def settle(%{tower: %{kal: _}} = p, info), do: Kalima.finish(p, info[:success] == true)
  def settle(p, _info), do: {%{ok: true, msg: nil}, p}

  @doc """
  Trận với quái phòng vừa xong (Session, trước `World.finish_encounter/2`): mình hạ thì cộng điểm / số quái, phòng kết
  thúc vì cú hạ đó thì trả thưởng; gục ngã thì rời phòng và kết thúc lượt như lượt riêng.
  """
  def after_battle(
        %{tower: %{room: id}, battle: %{over: true, result: r, encounter: enc}} = p,
        uid
      ) do
    if enc[:tower], do: disengage(id, uid, enc.tower)

    case r do
      "win" ->
        p = if enc[:killed], do: credit(p, enc), else: p

        case enc[:end] do
          nil ->
            p

          info ->
            {res, p} = settle(p, info)
            if res.msg, do: log(p, res.msg), else: p
        end

      "lose" ->
        leave(id, uid)
        Tower.after_battle(p)

      _ ->
        p
    end
  end

  def after_battle(p, _uid), do: p

  defp credit(%{tower: %{ds: ds} = t} = p, enc),
    do: %{p | tower: %{t | ds: %{ds | score: ds.score + (enc[:pts] || 0)}}}

  defp credit(%{tower: t} = p, %{role: "guard"}) do
    k = kind(t)
    %{p | tower: Map.update!(t, k, &Map.update(&1, :mine, 1, fn n -> n + 1 end))}
  end

  defp credit(p, _enc), do: p

  defp log(%{battle: %{log: _}} = p, text),
    do: update_in(p.battle.log, &(&1 ++ [%{kind: "win", text: text}]))

  defp log(p, _text), do: p

  # ---------- Tiến trình ----------

  @impl true
  def init({id, spec}) do
    salt = "#{id}|#{System.unique_integer([:positive])}"
    kind = Map.fetch!(@kinds, spec.kind)

    {t, minutes} =
      case kind do
        :ds -> {DevilSquare.room_new(spec.level, salt), DevilSquare.rules().run_minutes}
        :bc -> {BloodCastle.room_new(spec.level, salt), BloodCastle.rules().run_minutes}
        :kal -> {Kalima.room_new(spec.n, spec.level, salt), Kalima.rules().run_minutes}
      end

    ends_at = System.os_time(:second) + minutes * 60
    t = Map.update!(t, kind, &Map.put(&1, :ends_at, ends_at))
    Process.send_after(self(), :time_up, minutes * 60_000)

    {:ok,
     %{
       id: id,
       kind: kind,
       k: spec.k,
       # nhãn phòng cho giao diện: "CS 2–3" (mốc chuyển sinh), "Tổ đội"
       label: spec[:label] || (spec[:band] && EventRooms.label(spec.band)),
       salt: salt,
       t: t,
       members: %{},
       fights: %{},
       sync: false,
       snap: false,
       flush: false
     }}
  end

  @impl true
  def handle_call({:join, uid, info}, _from, s) do
    [ex, ey] = s.t.exit
    s = put_in(s.members[uid], Map.merge(info, %{x: ex, y: ey - 1}))
    {:reply, {:ok, view(s)}, dirty(s, :sync)}
  end

  def handle_call({:engage, uid, mid, max}, _from, s) do
    cond do
      not Map.has_key?(s.members, uid) ->
        {:reply, {:error, "Bạn không còn ở trong sự kiện."}, s}

      not Enum.any?(s.t.monsters, &(&1.id == mid)) ->
        {:reply, {:error, "Quái đã bị hạ."}, s}

      true ->
        f = s.fights[mid] || %{hp: max, max: max, hitters: %{}, in: MapSet.new()}
        f = %{f | in: MapSet.put(f.in, uid)}
        tell_hp(s, mid, f, uid)
        {:reply, {:ok, f.hp, MapSet.size(f.in)}, put_in(s.fights[mid], f)}
    end
  end

  def handle_call({:fight, mid, uid}, _from, s) do
    reply =
      case s.fights[mid] do
        nil -> nil
        f -> %{hp: f.hp, max: f.max, mine: Map.get(f.hitters, uid, 0)}
      end

    {:reply, reply, s}
  end

  def handle_call({:hit, uid, mid, dmg}, _from, s) do
    case s.fights[mid] do
      nil ->
        {:reply, :gone, s}

      f ->
        dmg = min(max(round(dmg), 0), f.hp)
        f = %{f | hp: f.hp - dmg, hitters: Map.update(f.hitters, uid, dmg, &(&1 + dmg))}

        if f.hp > 0 do
          pct = max(1, round(f.hp * 100 / max(f.max, 1)))

          t = %{
            s.t
            | monsters:
                Enum.map(s.t.monsters, &if(&1.id == mid, do: Map.put(&1, :hp_pct, pct), else: &1))
          }

          tell_hp(s, mid, f, uid)
          {:reply, {:alive, f.hp}, %{s | t: t, fights: Map.put(s.fights, mid, f)} |> dirty(:sync)}
        else
          kill(s, uid, mid, f)
        end
    end
  end

  def handle_call({:climb, uid}, _from, %{kind: :ds} = s) do
    case DevilSquare.room_climb(s.t, s.salt) do
      {:error, msg} ->
        {:reply, {:error, msg}, s}

      :cleared ->
        info = %{why: "qua hết #{s.t.ds.waves} đợt", cleared: true}
        finish(s, info, uid)
        {:stop, :normal, {:cleared, info}, s}

      {:next, t} ->
        [ex, ey] = t.exit
        members = Map.new(s.members, fn {u, m} -> {u, %{m | x: ex, y: ey - 1}} end)
        s = %{s | t: t, fights: %{}, members: members}
        text = "Đợt #{t.floor}/#{t.ds.waves}!"
        for u <- Map.keys(members), u != uid, do: notice(u, text)
        {:reply, {:ok, view(s)}, s |> dirty(:sync) |> dirty(:snap)}
    end
  end

  def handle_call({:climb, _uid}, _from, s), do: {:reply, {:error, "Không có đợt sau."}, s}

  def handle_call({:leave, uid}, _from, s) do
    s = Enum.reduce(Map.keys(s.fights), s, &drop_fighter(&2, uid, &1))
    s = %{s | members: Map.delete(s.members, uid)}

    if s.members == %{},
      do: {:stop, :normal, :ok, s},
      else: {:reply, :ok, dirty(s, :sync)}
  end

  def handle_call(:snapshot, _from, s), do: {:reply, snapshot_of(s), s}

  @impl true
  def handle_cast({:disengage, uid, mid}, s), do: {:noreply, drop_fighter(s, uid, mid)}

  def handle_cast({:move, uid, x, y}, s) do
    case s.members[uid] do
      nil -> {:noreply, s}
      m -> {:noreply, s |> put_in([:members, uid], %{m | x: x, y: y}) |> dirty(:snap)}
    end
  end

  @impl true
  def handle_info(:flush, s), do: {:noreply, flush(%{s | flush: false})}

  def handle_info(:time_up, s) do
    info =
      if s.kind == :ds,
        do: %{why: "hết giờ", cleared: false},
        else: %{success: false}

    finish(s, info, nil)
    {:stop, :normal, s}
  end

  defp drop_fighter(s, uid, mid) do
    case s.fights[mid] do
      %{in: fighters} = f ->
        if MapSet.member?(fighters, uid) do
          f = %{f | in: MapSet.delete(fighters, uid)}
          tell_hp(s, mid, f, uid)
          put_in(s.fights[mid], f)
        else
          s
        end

      _ ->
        s
    end
  end

  # máu mới / số người đang đánh quái `mid` gửi màn trận của những người khác đang đánh nó (người vừa đánh đã có trong
  # kết quả lệnh của mình)
  defp tell_hp(s, mid, f, except) do
    msg = {:shared_hp, key(s.id, mid), f.hp, MapSet.size(f.in)}

    for u <- f.in, u != except do
      # Session giữ máu mới trong trận (lần đẩy nhân vật sau không trả máu cũ), kênh vẽ ngay
      cast(u, {:room_hp, s.id, mid, f.hp, MapSet.size(f.in)})
      Phoenix.PubSub.broadcast(HacLong.PubSub, HacLong.Game.Session.topic(u), msg)
    end
  end

  # quái `mid` gục dưới đòn của `uid`: qua bước / đợt; người khác đang đánh con đó thắng theo phần sát thương
  defp kill(s, uid, mid, f) do
    m = Enum.find(s.t.monsters, &(&1.id == mid))
    pos = s.members[uid] && Map.take(s.members[uid], [:x, :y])
    total = max(Enum.sum(Map.values(f.hitters)), 1)

    {t, pts, msg, stage} =
      case s.kind do
        :ds ->
          {t, pts} = DevilSquare.room_kill(s.t, m)
          {t, pts, nil, :guard}

        :bc ->
          {t, msg, stage} = BloodCastle.room_kill(s.t, m, pos)
          {t, 0, msg, stage}

        :kal ->
          {t, msg, stage} = Kalima.room_kill(s.t, m, pos)
          {t, 0, msg, stage}
      end

    for {u, d} <- f.hitters, u != uid, do: cast(u, {:room_kill, s.id, mid, d / total})
    if msg, do: for(u <- Map.keys(s.members), do: notice(u, msg))
    s = %{s | t: t, fights: Map.delete(s.fights, mid)} |> dirty(:sync)
    killed = %{pts: pts, role: m[:role], share: Map.get(f.hitters, uid, 0) / total}

    if stage == :done do
      # trùm gục: Lâu Đài thưởng theo sát thương lên trùm, Kalima cả tổ đội cùng thắng
      {top, _} = Enum.max_by(f.hitters, &elem(&1, 1))
      info = fn u -> %{success: true, top: u == top, share: Map.get(f.hitters, u, 0) / total} end
      s = flush(s)
      for u <- Map.keys(s.members), u != uid, do: cast(u, {:room_end, s.id, info.(u)})
      {:stop, :normal, {:killed, Map.put(killed, :end, info.(uid))}, s}
    else
      {:reply, {:killed, killed}, s}
    end
  end

  # kết thúc cả phòng: báo từng người (trừ `except`, người đang gọi tự kết thúc)
  defp finish(s, info, except) do
    for u <- Map.keys(s.members), u != except, do: cast(u, {:room_end, s.id, info})
  end

  defp dirty(s, what) do
    s = Map.put(s, what, true)

    if s.flush,
      do: s,
      else:
        (
          Process.send_after(self(), :flush, @flush_ms)
          %{s | flush: true}
        )
  end

  defp flush(s) do
    if s.sync do
      v = view(s)
      for u <- Map.keys(s.members), do: cast(u, {:room_sync, s.id, v})
    end

    if s.sync or s.snap,
      do:
        Phoenix.PubSub.broadcast(
          HacLong.PubSub,
          topic(s.id),
          {:map_state, {:room, s.id}, snapshot_of(s)}
        )

    %{s | sync: false, snap: false}
  end

  # bản sao tháp gửi người chơi (điểm / số quái riêng bắt đầu từ 0, Session giữ phần của mình khi `merge/2`)
  defp view(s) do
    s.t
    |> Map.update!(s.kind, &Map.merge(&1, %{score: 0, mine: 0}))
    |> Map.merge(%{room: s.id, k: s.k, room_label: s.label, people: map_size(s.members)})
  end

  defp snapshot_of(s) do
    %{
      map: Tower.map_id(),
      phase: HacLong.World.Clock.phase(),
      monsters: [],
      nodes: [],
      players:
        Enum.map(s.members, fn {uid, m} ->
          %{
            id: uid,
            name: m.name,
            cls: m.cls,
            level: m.level,
            rebirths: m[:rebirths] || 0,
            look: m[:look],
            tag: m[:tag],
            red: false,
            x: m.x,
            y: m.y
          }
        end)
    }
  end

  defp cast(uid, msg), do: HacLong.Game.Session.room_cast(uid, msg)

  defp notice(uid, text),
    do: Phoenix.PubSub.broadcast(HacLong.PubSub, HacLong.Game.Session.topic(uid), {:notice, text})
end

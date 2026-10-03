defmodule Mu.Party do
  @moduledoc """
  Nhóm (Party, `KB_GAME_DESIGN §12`, P3-M4 theo P3-5). Một tiến trình giữ mọi nhóm **trong RAM**
  (không có bảng DB); nhóm là giữa nhiều tài khoản nên không nằm trong Session.

  - Thao tác (Session gọi): `invite/2` (tự lập nhóm khi người được mời đồng ý, chỉ trưởng nhóm
    mời được), `accept/2`, `decline/2`, `leave/1`, `kick/2`, `disband/1`; tối đa `party.maxSize`,
    lời mời hết hạn sau `party.inviteSeconds`.
  - Trưởng nhóm rời → người vào sớm nhất còn lại làm trưởng; còn 1 người → nhóm giải tán.
  - Session báo trạng thái (`update/2`: cấp, map, online). Mỗi `party.statusIntervalMs` đọc HP /
    vị trí từ MapServer, đổi thì đẩy event `party {leader, members}` cho mọi thành viên (gửi qua
    Session: `{:party_push, event, payload}`). Mất kết nối: `online: false`; quá hạn reconnect
    (Session rời map) → `leave/1` (P3-5 (6)).
  - ETS `#{inspect(__MODULE__)}` (đọc trực tiếp, không gọi tiến trình): `mates/1` cho MapServer
    chia EXP và loot protect cả nhóm. MapServer không bao giờ gọi tiến trình này (tiến trình này
    gọi MapServer) nên không khóa chéo.
  - Thông báo trong nhóm (vào / rời / bị đuổi / giải tán / từ chối) là dòng chat `SYSTEM`.
  """
  use GenServer
  require Logger

  alias Mu.Chat
  alias Mu.Game.Config
  alias Mu.World.MapServer

  @table __MODULE__

  # ---------- API ----------

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  `me`: `%{cid, name, class, level, map_id}` của người gọi (tiến trình gọi = Session của họ).
  Mời người chơi tên `to` (đang online). `:ok` hoặc `{:error, code}`.
  """
  def invite(me, to), do: GenServer.call(__MODULE__, {:invite, me, to, self()})

  @doc "Nhận lời mời của `from` (tên). Vào nhóm của `from` (lập nhóm mới nếu chưa có)."
  def accept(me, from), do: GenServer.call(__MODULE__, {:accept, me, from, self()})

  def decline(me, from), do: GenServer.call(__MODULE__, {:decline, me, from})
  def leave(cid), do: GenServer.call(__MODULE__, {:leave, cid})
  def kick(cid, name), do: GenServer.call(__MODULE__, {:kick, cid, name})
  def disband(cid), do: GenServer.call(__MODULE__, {:disband, cid})

  @doc "Tin chat PARTY tới mọi thành viên (kể cả người gửi); `{:error, INVALID_TARGET}` nếu không có nhóm."
  def chat(cid, msg), do: GenServer.call(__MODULE__, {:chat, cid, msg})

  @doc "Session báo đổi `%{level?, map_id?, online?}` (bất đồng bộ)."
  def update(cid, changes), do: GenServer.cast(__MODULE__, {:update, cid, changes, self()})

  @doc "Đẩy `party` ngay cho mọi nhóm có thay đổi (test / sau thao tác)."
  def flush, do: GenServer.call(__MODULE__, :flush)

  @doc "Id nhân vật cùng nhóm với `cid` (kể cả `cid`); không có nhóm → `[cid]`. Đọc ETS."
  def mates(cid) do
    with [{_, pid}] <- :ets.lookup(@table, {:member, cid}),
         [{_, cids}] <- :ets.lookup(@table, {:party, pid}) do
      cids
    else
      _ -> [cid]
    end
  rescue
    ArgumentError -> [cid]
  end

  @doc "`a` và `b` cùng nhóm (hoặc là một)."
  def same?(a, b), do: a == b or b in mates(a)

  # ---------- GenServer ----------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :protected, read_concurrency: true])
    schedule()

    {:ok,
     %{
       # id → %{id, leader: cid, members: [cid] (thứ tự vào nhóm)}
       parties: %{},
       # cid → %{name, class, level, map_id, session, online, party, ref}
       chars: %{},
       # tên chữ thường → cid
       names: %{},
       # tên người được mời (chữ thường) → %{cid người mời => hạn ms}
       invites: %{},
       # id nhóm → payload đã đẩy lần cuối
       last: %{},
       next_id: 1
     }}
  end

  @impl true
  def handle_call({:invite, me, to, session}, _from, s) do
    s = register(s, me, session)
    target = to_string(to) |> String.downcase()
    mine = party_of(s, me.cid)

    cond do
      not is_binary(to) or target == String.downcase(me.name) ->
        {:reply, {:error, "INVALID_TARGET"}, s}

      mine && mine.leader != me.cid ->
        {:reply, {:error, "FORBIDDEN"}, s}

      mine && length(mine.members) >= max_size() ->
        {:reply, {:error, "FORBIDDEN"}, s}

      true ->
        case Registry.lookup(Mu.Game.NameRegistry, target) do
          [{pid, _}] ->
            if in_party?(s, s.names[target]) do
              {:reply, {:error, "INVALID_TARGET"}, s}
            else
              until = now() + Config.get(["party", "inviteSeconds"]) * 1000

              invites =
                Map.update(s.invites, target, %{me.cid => until}, &Map.put(&1, me.cid, until))

              send(pid, {:party_push, "party_invite", %{from: me.name}})
              {:reply, :ok, %{s | invites: invites}}
            end

          [] ->
            {:reply, {:error, "INVALID_TARGET"}, s}
        end
    end
  end

  def handle_call({:accept, me, from, session}, _from, s) do
    s = register(s, me, session)

    with {:ok, inviter, s} <- take_invite(s, me, from),
         :ok <- if(in_party?(s, me.cid), do: {:error, "INVALID_TARGET"}, else: :ok),
         p = party_of(s, inviter) || %{id: nil, leader: inviter, members: [inviter]},
         true <- p.leader == inviter || {:error, "INVALID_TARGET"},
         true <- length(p.members) < max_size() || {:error, "FORBIDDEN"} do
      {s, p} =
        if p.id,
          do: {s, p},
          else: {%{s | next_id: s.next_id + 1}, %{p | id: s.next_id}}

      p = %{p | members: p.members ++ [me.cid]}
      s = put_party(s, p)
      notice(s, p, "#{me.name} đã vào nhóm.")
      {:reply, :ok, push_now(s, p.id)}
    else
      {:error, code} -> {:reply, {:error, code}, s}
    end
  end

  def handle_call({:decline, me, from}, _from, s) do
    case take_invite(s, me, from) do
      {:ok, inviter, s} ->
        system(s, inviter, "#{me.name} từ chối lời mời vào nhóm.")
        {:reply, :ok, s}

      {:error, code} ->
        {:reply, {:error, code}, s}
    end
  end

  def handle_call({:leave, cid}, _from, s) do
    case party_of(s, cid) do
      nil -> {:reply, {:error, "INVALID_TARGET"}, s}
      p -> {:reply, :ok, remove(s, p, cid, "#{name(s, cid)} đã rời nhóm.")}
    end
  end

  def handle_call({:kick, cid, target}, _from, s) do
    victim = s.names[String.downcase(to_string(target))]

    case party_of(s, cid) do
      %{leader: ^cid} = p when victim != nil and victim != cid ->
        if victim in p.members,
          do: {:reply, :ok, remove(s, p, victim, "#{name(s, victim)} bị mời ra khỏi nhóm.")},
          else: {:reply, {:error, "INVALID_TARGET"}, s}

      %{leader: ^cid} ->
        {:reply, {:error, "INVALID_TARGET"}, s}

      nil ->
        {:reply, {:error, "INVALID_TARGET"}, s}

      _ ->
        {:reply, {:error, "FORBIDDEN"}, s}
    end
  end

  def handle_call({:disband, cid}, _from, s) do
    case party_of(s, cid) do
      %{leader: ^cid} = p ->
        notice(s, p, "Nhóm đã giải tán.")
        {:reply, :ok, dissolve(s, p)}

      nil ->
        {:reply, {:error, "INVALID_TARGET"}, s}

      _ ->
        {:reply, {:error, "FORBIDDEN"}, s}
    end
  end

  def handle_call({:chat, cid, msg}, _from, s) do
    case party_of(s, cid) do
      nil ->
        {:reply, {:error, "INVALID_TARGET"}, s}

      p ->
        for m <- p.members, pid = s.chars[m].session, do: send(pid, {:party_push, "chat", msg})
        {:reply, :ok, s}
    end
  end

  def handle_call(:flush, _from, s), do: {:reply, :ok, push_all(s)}

  @impl true
  def handle_cast({:update, cid, changes, session}, s) do
    case s.chars[cid] do
      nil ->
        {:noreply, s}

      c ->
        c = Map.merge(c, Map.take(changes, [:level, :map_id, :online]))
        c = if c.session != session, do: watch(c, session), else: c
        {:noreply, put_in(s.chars[cid], c)}
    end
  end

  @impl true
  def handle_info(:tick, s) do
    schedule()
    t = now()

    invites =
      for {to, from} <- s.invites,
          live = Map.filter(from, fn {_, until} -> until > t end),
          map_size(live) > 0,
          into: %{},
          do: {to, live}

    {:noreply, push_all(%{s | invites: invites})}
  end

  # Session tắt (rời game hẳn / lỗi): rời nhóm
  def handle_info({:DOWN, _ref, :process, pid, _}, s) do
    case Enum.find(s.chars, fn {_, c} -> c.session == pid end) do
      {cid, _} ->
        s = put_in(s.chars[cid].session, nil)

        case party_of(s, cid) do
          nil -> {:noreply, s}
          p -> {:noreply, remove(s, p, cid, "#{name(s, cid)} đã rời nhóm.")}
        end

      nil ->
        {:noreply, s}
    end
  end

  def handle_info(_msg, s), do: {:noreply, s}

  # ---------- Nội bộ ----------

  defp register(s, me, session) do
    old = s.chars[me.cid]

    c =
      Map.merge(
        old || %{party: nil, online: true, session: nil, ref: nil},
        Map.take(me, [:name, :class, :level, :map_id])
      )

    c = if c.session != session, do: watch(c, session), else: c

    %{
      s
      | chars: Map.put(s.chars, me.cid, c),
        names: Map.put(s.names, String.downcase(me.name), me.cid)
    }
  end

  defp watch(c, session) do
    if c.ref, do: Process.demonitor(c.ref, [:flush])
    %{c | session: session, ref: session && Process.monitor(session)}
  end

  defp take_invite(s, me, from) do
    key = String.downcase(me.name)
    inviter = s.names[String.downcase(to_string(from))]

    case get_in(s.invites, [key, inviter]) do
      until when is_integer(until) ->
        s = update_in(s.invites[key], &Map.delete(&1, inviter))
        if until > now(), do: {:ok, inviter, s}, else: {:error, "INVALID_TARGET"}

      _ ->
        {:error, "INVALID_TARGET"}
    end
  end

  defp party_of(s, cid) do
    with %{party: id} when id != nil <- s.chars[cid], do: s.parties[id], else: (_ -> nil)
  end

  defp in_party?(s, cid), do: party_of(s, cid) != nil

  defp put_party(s, p) do
    chars = Enum.reduce(p.members, s.chars, fn m, acc -> put_in(acc[m].party, p.id) end)
    for m <- p.members, do: :ets.insert(@table, {{:member, m}, p.id})
    :ets.insert(@table, {{:party, p.id}, p.members})
    %{s | parties: Map.put(s.parties, p.id, p), chars: chars}
  end

  # bỏ `cid` khỏi nhóm: báo cả nhóm (gồm người bị bỏ), đẩy party rỗng cho người đó; trưởng nhóm
  # rời → người vào sớm nhất còn lại làm trưởng; còn 1 người → giải tán
  defp remove(s, p, cid, text) do
    notice(s, p, text)
    s = detach(s, cid)

    case List.delete(p.members, cid) do
      [last] ->
        system(s, last, "Nhóm đã giải tán.")
        dissolve(s, %{p | members: [last]})

      members ->
        p2 = %{p | members: members, leader: if(p.leader == cid, do: hd(members), else: p.leader)}
        if p2.leader != p.leader, do: notice(s, p2, "#{name(s, p2.leader)} làm trưởng nhóm.")
        s |> put_party(p2) |> push_now(p2.id)
    end
  end

  defp dissolve(s, p) do
    s = Enum.reduce(p.members, s, &detach(&2, &1))
    :ets.delete(@table, {:party, p.id})
    %{s | parties: Map.delete(s.parties, p.id), last: Map.delete(s.last, p.id)}
  end

  defp detach(s, cid) do
    :ets.delete(@table, {:member, cid})

    if pid = s.chars[cid].session,
      do: send(pid, {:party_push, "party", %{leader: nil, members: []}})

    put_in(s.chars[cid].party, nil)
  end

  defp push_all(s), do: Enum.reduce(Map.keys(s.parties), s, &push_changed(&2, &1))

  defp push_now(s, id), do: push_changed(%{s | last: Map.delete(s.last, id)}, id)

  defp push_changed(s, id) do
    p = s.parties[id]
    view = view(s, p)

    if s.last[id] == view do
      s
    else
      for m <- p.members, pid = s.chars[m].session, do: send(pid, {:party_push, "party", view})
      %{s | last: Map.put(s.last, id, view)}
    end
  end

  # `{leader, members: [{name, class, level, hp, maxHp, mapId, x, y, online}]}`
  defp view(s, p) do
    %{
      leader: name(s, p.leader),
      members:
        for m <- p.members do
          c = s.chars[m]
          st = player_state(c.map_id, m)

          %{
            name: c.name,
            class: c.class,
            level: c.level,
            mapId: c.map_id,
            online: c.online and c.session != nil,
            hp: st[:hp],
            maxHp: st[:hp_max],
            x: st[:x],
            y: st[:y]
          }
        end
    }
  end

  defp player_state(nil, _cid), do: %{}

  defp player_state(map_id, cid) do
    MapServer.player_state(map_id, cid) || %{}
  catch
    :exit, _ -> %{}
  end

  defp notice(s, p, text), do: Enum.each(p.members, &system(s, &1, text))

  defp system(s, cid, text) do
    if pid = s.chars[cid] && s.chars[cid].session,
      do: send(pid, {:party_push, "chat", Chat.message("SYSTEM", "Nhóm", text)})
  end

  defp name(s, cid), do: s.chars[cid].name
  defp max_size, do: Config.get(["party", "maxSize"])
  defp now, do: System.monotonic_time(:millisecond)
  defp schedule, do: Process.send_after(self(), :tick, Config.get(["party", "statusIntervalMs"]))
end

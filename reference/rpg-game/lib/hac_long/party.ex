defmodule HacLong.Party do
  @moduledoc """
  Tổ đội (tối đa `@max` người) và trận đánh chung. Giữ trong bộ nhớ, không lưu database:
  server khởi động lại thì tổ đội tan.

  - Mời (`invite/2`) người đang online; người được mời nhận (`accept/1`) hoặc từ chối.
    Người mời chưa có tổ đội thì tổ đội được lập, người mời làm đội trưởng.
  - Trận đánh chung: người trong tổ đội chạm quái thì trận được ghi ở đây (`open_fight/2`) với
    máu chung; đồng đội chạm vào con quái đang đánh đó thì vào cùng trận (`join_fight/2`).
    Mỗi đòn trừ vào máu chung (`hit/3`), như trùm thế giới. Quái gục thì mọi người trong trận
    đều thắng; phần thưởng mỗi người = thưởng gốc × `RULES.party.share_bonus` (1,2) / số người
    (đánh chung nhanh hơn một chút, không nhân đôi nhân ba).
  - Lời mời hết hạn sau `RULES.party.invite_s` giây (Phase 5, H2). Người chơi đóng hết tab / rớt
    mạng quá `RULES.party.leave_after_s` giây thì tự rời tổ đội (`away/1`, `back/1` do Session gọi);
    đội trưởng rời thì người vào sớm nhất còn lại lên thay (H3).
  - Thay đổi tổ đội phát `{:party, id | nil}` tới kênh của từng thành viên; máu chung phát
    `{:shared_hp, khóa, máu, số_người}`.

  Khóa trận: `"<bản đồ>:<id quái>"`.
  """
  use GenServer

  alias HacLong.Game.Session

  # `RULES.party.max` (`priv/game_data/rules.json`)
  @rules HacLong.Game.Data.rules().party
  @max @rules.max

  def max, do: @max
  def topic(id), do: "party:#{id}"

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  # ---------- Tổ đội ----------

  @doc "Tổ đội của người chơi: `%{id, leader, members}` hoặc nil."
  def of(uid), do: GenServer.call(__MODULE__, {:of, uid})

  def invite(from, to), do: GenServer.call(__MODULE__, {:invite, from, to})
  def accept(uid), do: GenServer.call(__MODULE__, {:accept, uid})
  def decline(uid), do: GenServer.call(__MODULE__, {:decline, uid})
  def leave(uid), do: GenServer.call(__MODULE__, {:leave, uid})
  def kick(leader, uid), do: GenServer.call(__MODULE__, {:kick, leader, uid})

  @doc "Người chơi vừa đóng hết tab / rớt mạng: hết `leave_after_s` giây chưa quay lại thì rời tổ đội."
  def away(uid), do: GenServer.cast(__MODULE__, {:away, uid})

  @doc "Người chơi quay lại (mở tab): hủy hẹn giờ rời tổ đội."
  def back(uid), do: GenServer.cast(__MODULE__, {:back, uid})

  @doc "Lời mời đang chờ của người chơi: `%{party, from}` hoặc nil."
  def invitation(uid), do: GenServer.call(__MODULE__, {:invitation, uid})

  # ---------- Trận đánh chung ----------

  @doc """
  Ghi trận của `uid` (đang ở trong tổ đội) để đồng đội vào đánh cùng. `m`: quái trong trận
  (`hp`, `maxHp`, `xp`, `gold`). Không có tổ đội thì không làm gì.
  """
  def open_fight(key, uid, m), do: GenServer.call(__MODULE__, {:open_fight, key, uid, m})

  @doc "Vào trận `key` của đồng đội: `{:ok, %{hp, max, n}}` hoặc `{:error, lý_do}`."
  def join_fight(key, uid), do: GenServer.call(__MODULE__, {:join_fight, key, uid})

  @doc "Trạng thái trận chung trước một đòn: `%{hp, n, xp, gold}` hoặc nil nếu trận đã hết."
  def fight(key), do: GenServer.call(__MODULE__, {:fight, key})

  @doc """
  `uid` gây `dmg` sát thương. `{:alive, máu_còn}`, `{:killed, số_người}` (đòn này hạ quái)
  hoặc `:gone` (trận đã hết).
  """
  def hit(key, uid, dmg), do: GenServer.call(__MODULE__, {:hit, key, uid, dmg})

  @doc """
  `uid` rời trận (thua, bỏ chạy). Trả về `{:owner, người_mới}` nếu người rời đang giữ con
  quái trên bản đồ và trận còn người khác, còn lại `:ok`.
  """
  def leave_fight(key, uid), do: GenServer.call(__MODULE__, {:leave_fight, key, uid})

  # ---------- Tiến trình ----------

  @impl true
  def init(_),
    do: {:ok, %{parties: %{}, of: %{}, invites: %{}, fights: %{}, away: %{}, next: 1}}

  @impl true
  def handle_call({:of, uid}, _from, s), do: {:reply, party_of(s, uid), s}

  def handle_call({:invitation, uid}, _from, s), do: {:reply, s.invites[uid], s}

  def handle_call({:invite, from, to}, _from, s) do
    mine = party_of(s, from)

    cond do
      from == to ->
        {:reply, {:error, "Không tự mời mình được."}, s}

      s.of[to] ->
        {:reply, {:error, "Người này đã ở trong một tổ đội."}, s}

      mine && mine.leader != from ->
        {:reply, {:error, "Chỉ đội trưởng mới mời được."}, s}

      mine && length(mine.members) >= @max ->
        {:reply, {:error, "Tổ đội đã đủ #{@max} người."}, s}

      true ->
        {s, party} = if mine, do: {s, mine}, else: create(s, from)
        ref = make_ref()
        Process.send_after(self(), {:invite_expired, to, ref}, @rules.invite_s * 1000)
        s = put_in(s.invites[to], %{party: party.id, from: from, ref: ref})
        Phoenix.PubSub.broadcast(HacLong.PubSub, Session.topic(to), {:party_invite, from})
        {:reply, :ok, s}
    end
  end

  def handle_call({:accept, uid}, _from, s) do
    with %{party: pid} <- s.invites[uid],
         %{} = party <- s.parties[pid],
         true <- length(party.members) < @max || :full do
      s = %{s | invites: Map.delete(s.invites, uid)}
      s = put_in(s.parties[pid].members, party.members ++ [uid])
      s = put_in(s.of[uid], pid)
      notify(s, pid)
      {:reply, :ok, s}
    else
      :full ->
        {:reply, {:error, "Tổ đội đã đủ người."}, %{s | invites: Map.delete(s.invites, uid)}}

      _ ->
        {:reply, {:error, "Lời mời không còn."}, %{s | invites: Map.delete(s.invites, uid)}}
    end
  end

  def handle_call({:decline, uid}, _from, s),
    do: {:reply, :ok, %{s | invites: Map.delete(s.invites, uid)}}

  def handle_call({:leave, uid}, _from, s), do: {:reply, :ok, remove(s, uid)}

  def handle_call({:kick, leader, uid}, _from, s) do
    case party_of(s, leader) do
      %{leader: ^leader, members: ms} when leader != uid ->
        if uid in ms,
          do: {:reply, :ok, remove(s, uid)},
          else: {:reply, {:error, "Người này không ở trong tổ đội."}, s}

      _ ->
        {:reply, {:error, "Chỉ đội trưởng mới mời người khác ra được."}, s}
    end
  end

  def handle_call({:open_fight, key, uid, m}, _from, s) do
    case s.of[uid] do
      nil ->
        {:reply, :ok, s}

      pid ->
        f = %{
          hp: m.hp,
          max: m.maxHp,
          xp: m.xp,
          gold: m.gold,
          members: [uid],
          owner: uid,
          party: pid
        }

        {:reply, :ok, put_in(s.fights[key], f)}
    end
  end

  def handle_call({:join_fight, key, uid}, _from, s) do
    f = s.fights[key]

    cond do
      f == nil ->
        {:reply, {:error, "Con quái này đang giao chiến với người khác."}, s}

      s.of[uid] != f.party ->
        {:reply, {:error, "Con quái này đang giao chiến với người khác."}, s}

      uid in f.members ->
        {:reply, {:ok, %{hp: f.hp, max: f.max, n: length(f.members)}}, s}

      true ->
        f = %{f | members: f.members ++ [uid]}
        s = put_in(s.fights[key], f)
        broadcast_hp(key, f)
        {:reply, {:ok, %{hp: f.hp, max: f.max, n: length(f.members)}}, s}
    end
  end

  def handle_call({:fight, key}, _from, s) do
    case s.fights[key] do
      nil -> {:reply, nil, s}
      f -> {:reply, %{hp: f.hp, n: length(f.members), xp: f.xp, gold: f.gold}, s}
    end
  end

  def handle_call({:hit, key, uid, dmg}, _from, s) do
    case s.fights[key] do
      nil ->
        {:reply, :gone, s}

      f ->
        f = %{f | hp: max(0, f.hp - dmg)}

        if f.hp == 0 do
          # báo các đồng đội còn trong trận (không đồng bộ, như thưởng trùm thế giới)
          n = length(f.members)
          info = %{key: key, n: n, xp: f.xp, gold: f.gold, killer: uid}

          for other <- f.members,
              other != uid,
              do: Task.start(fn -> Session.shared_end(other, info) end)

          {:reply, {:killed, n}, %{s | fights: Map.delete(s.fights, key)}}
        else
          broadcast_hp(key, f)
          {:reply, {:alive, f.hp}, put_in(s.fights[key], f)}
        end
    end
  end

  def handle_call({:leave_fight, key, uid}, _from, s) do
    case s.fights[key] do
      nil ->
        {:reply, :ok, s}

      f ->
        rest = List.delete(f.members, uid)

        cond do
          rest == [] ->
            {:reply, :ok, %{s | fights: Map.delete(s.fights, key)}}

          f.owner == uid ->
            f = %{f | members: rest, owner: hd(rest)}
            broadcast_hp(key, f)
            {:reply, {:owner, hd(rest)}, put_in(s.fights[key], f)}

          true ->
            f = %{f | members: rest}
            broadcast_hp(key, f)
            {:reply, :ok, put_in(s.fights[key], f)}
        end
    end
  end

  # ---------- Nội bộ ----------

  defp party_of(s, uid) do
    case s.of[uid] do
      nil -> nil
      pid -> s.parties[pid]
    end
  end

  defp create(s, leader) do
    party = %{id: s.next, leader: leader, members: [leader]}
    s = %{s | parties: Map.put(s.parties, party.id, party), next: s.next + 1}
    s = put_in(s.of[leader], party.id)
    notify(s, party.id)
    {s, party}
  end

  @impl true
  def handle_cast({:away, uid}, s) do
    if s.of[uid] do
      ref = make_ref()
      Process.send_after(self(), {:away_expired, uid, ref}, @rules.leave_after_s * 1000)
      {:noreply, put_in(s.away[uid], ref)}
    else
      {:noreply, s}
    end
  end

  def handle_cast({:back, uid}, s), do: {:noreply, %{s | away: Map.delete(s.away, uid)}}

  @impl true
  def handle_info({:invite_expired, to, ref}, s) do
    case s.invites[to] do
      %{ref: ^ref, party: pid, from: from} ->
        s = %{s | invites: Map.delete(s.invites, to)}

        Phoenix.PubSub.broadcast(
          HacLong.PubSub,
          Session.topic(from),
          {:notice, "Lời mời tổ đội đã hết hạn."}
        )

        Phoenix.PubSub.broadcast(HacLong.PubSub, Session.topic(to), {:party_invite, nil})
        {:noreply, drop_lonely(s, pid)}

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:away_expired, uid, ref}, s) do
    case s.away[uid] do
      ^ref -> {:noreply, %{s | away: Map.delete(s.away, uid)} |> remove(uid)}
      _ -> {:noreply, s}
    end
  end

  # tổ đội lập lúc mời mà không ai vào, cũng không còn lời mời nào: tan
  defp drop_lonely(s, pid) do
    case s.parties[pid] do
      %{members: [only]} ->
        if Enum.any?(s.invites, fn {_, i} -> i.party == pid end) do
          s
        else
          tell(only, nil)
          %{s | parties: Map.delete(s.parties, pid), of: Map.delete(s.of, only)}
        end

      _ ->
        s
    end
  end

  defp remove(s, uid) do
    case party_of(s, uid) do
      nil ->
        s

      party ->
        rest = List.delete(party.members, uid)
        s = %{s | of: Map.delete(s.of, uid)}
        tell(uid, nil)

        cond do
          # còn một người thì tổ đội tan
          length(rest) <= 1 ->
            Enum.each(rest, &tell(&1, nil))
            s = %{s | of: Map.drop(s.of, rest), parties: Map.delete(s.parties, party.id)}
            %{s | invites: Map.reject(s.invites, fn {_, i} -> i.party == party.id end)}

          true ->
            leader = if party.leader == uid, do: hd(rest), else: party.leader
            s = put_in(s.parties[party.id], %{party | members: rest, leader: leader})
            notify(s, party.id)
            s
        end
    end
  end

  defp notify(s, pid), do: Enum.each(s.parties[pid].members, &tell(&1, pid))

  defp tell(uid, pid),
    do: Phoenix.PubSub.broadcast(HacLong.PubSub, Session.topic(uid), {:party, pid})

  defp broadcast_hp(key, f) do
    for uid <- f.members,
        do:
          Phoenix.PubSub.broadcast(
            HacLong.PubSub,
            Session.topic(uid),
            {:shared_hp, key, f.hp, length(f.members)}
          )
  end
end

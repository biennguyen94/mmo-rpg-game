defmodule HacLong.PkBet do
  @moduledoc """
  PK cược vàng (Phase 5, H7 + H8; `INTEGRATION_PLAN.md §13.2`).

  1. `invite/4`: A mời B (cả hai online) với số vàng cược; B nhận `{:pk_invite, ...}`. Lời mời hết hạn sau
     `RULES.pk.invite_s` giây. Mỗi người chỉ dính một lời mời (gửi hay nhận) cùng lúc.
  2. `decline/1` (B) / `cancel/1` (A) hủy; `take/1` (B nhận) lấy lời mời ra khỏi hàng chờ.
  3. `execute/1` (chạy ở tiến trình của người nhận, không phải ở GenServer này): giữ Session của A rồi B
     (như `HacLong.Trade`), kiểm lại vàng / trận / số trận hôm nay, cho hai bản sao tự đánh
     (`HacLong.Game.PkFight`), rồi trong **một transaction** ghi dòng `pk_matches` và hai nhân vật
     (nhật ký vàng lý do `PK_BET`). Lỗi ở bất kỳ bước nào thì không ai mất gì.

  Không phí, không giới hạn chênh cấp (câu 5-C, 5-D); cược trong `RULES.pk.min..max`, tối đa
  `RULES.pk.per_day` trận cược mỗi người mỗi ngày (giờ Việt Nam).
  """
  use GenServer
  require Logger
  import Ecto.Query

  alias HacLong.{Arena, Repo}
  alias HacLong.Game.{Characters, Daily, Data, PkFight, Session}

  @pk Data.rules().pk

  def rules, do: @pk

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: {:ok, %{by_to: %{}, by_from: %{}}}

  @doc "Mời `to` cược `wager` vàng. `from_info`: `%{name, level, cls}` của người mời."
  def invite(from, from_info, to, wager),
    do: GenServer.call(__MODULE__, {:invite, from, from_info, to, wager})

  @doc "Người nhận lấy lời mời ra (để `execute/1`); `{:ok, lời_mời}` hoặc `{:error, lý_do}`."
  def take(uid), do: GenServer.call(__MODULE__, {:take, uid})

  def decline(uid), do: GenServer.call(__MODULE__, {:drop, uid, :to, "từ chối"})
  def cancel(uid), do: GenServer.call(__MODULE__, {:drop, uid, :from, "hủy lời mời"})

  @doc "Người chơi rớt mạng / đóng hết tab: hủy lời mời cược đang dính (gửi hay nhận)."
  def disconnect(uid) do
    decline(uid)
    cancel(uid)
  end

  @doc "Lời mời `uid` đang dính: `%{incoming: bool, ...}` hoặc nil."
  def of(uid), do: GenServer.call(__MODULE__, {:of, uid})

  @doc false
  def reset, do: GenServer.call(__MODULE__, :reset)

  @doc "Số trận cược hôm nay của `uid`."
  def today_count(uid, day \\ Date.from_iso8601!(Daily.today())) do
    Repo.aggregate(
      from(m in "pk_matches", where: (m.a_id == ^uid or m.b_id == ^uid) and m.day == ^day),
      :count
    )
  end

  @doc "Các trận cược gần nhất của `uid`."
  def history(uid, n \\ 20) do
    from(m in "pk_matches",
      where: m.a_id == ^uid or m.b_id == ^uid,
      order_by: [desc: m.id],
      limit: ^n,
      select: %{
        id: m.id,
        a_id: m.a_id,
        b_id: m.b_id,
        a_name: m.a_name,
        b_name: m.b_name,
        wager: m.wager,
        winner_id: m.winner_id,
        rounds: m.rounds,
        at: m.inserted_at
      }
    )
    |> Repo.all()
  end

  @doc "Kiểm số vàng cược (số nguyên trong giới hạn)."
  def check_wager(w) when is_integer(w) and w >= @pk.min and w <= @pk.max, do: :ok
  def check_wager(_), do: {:error, "Cược từ #{@pk.min} đến #{@pk.max} vàng."}

  # ---------- Máy chủ ----------

  @impl true
  def handle_call({:invite, from, info, to, wager}, _from, s) do
    cond do
      from == to ->
        {:reply, {:error, "Không tự cược với mình được."}, s}

      (err = check_wager(wager)) != :ok ->
        {:reply, err, s}

      busy?(s, from) ->
        {:reply, {:error, "Bạn đang có một lời mời cược khác."}, s}

      busy?(s, to) ->
        {:reply, {:error, "Người này đang có lời mời cược khác."}, s}

      true ->
        ref = make_ref()
        timer = Process.send_after(self(), {:expire, to, ref}, @pk.invite_s * 1000)

        inv = %{
          ref: ref,
          timer: timer,
          from: from,
          to: to,
          name: info.name,
          level: info.level,
          cls: info.cls,
          wager: wager,
          expires: System.system_time(:second) + @pk.invite_s
        }

        send_to(to, {:pk_invite, public(inv)})

        {:reply, :ok,
         %{s | by_to: Map.put(s.by_to, to, inv), by_from: Map.put(s.by_from, from, to)}}
    end
  end

  def handle_call({:take, uid}, _from, s) do
    case s.by_to[uid] do
      nil ->
        {:reply, {:error, "Lời mời không còn nữa."}, s}

      inv ->
        Process.cancel_timer(inv.timer)
        {:reply, {:ok, inv}, remove(s, inv)}
    end
  end

  def handle_call({:drop, uid, side, why}, _from, s) do
    inv = if side == :to, do: s.by_to[uid], else: (to = s.by_from[uid]) && s.by_to[to]

    case inv do
      nil ->
        {:reply, :ok, s}

      inv ->
        Process.cancel_timer(inv.timer)
        other = if side == :to, do: inv.from, else: inv.to
        who = if side == :to, do: "Người được mời", else: inv.name
        send_to(other, {:pk_invite, nil})
        send_to(other, {:notice, "⚔ #{who} đã #{why} cược đấu."})
        {:reply, :ok, remove(s, inv)}
    end
  end

  def handle_call({:of, uid}, _from, s) do
    inv = s.by_to[uid] || ((to = s.by_from[uid]) && s.by_to[to])
    {:reply, inv && Map.put(public(inv), :incoming, inv.to == uid), s}
  end

  def handle_call(:reset, _from, _s), do: {:reply, :ok, elem(init(:ok), 1)}

  @impl true
  def handle_info({:expire, to, ref}, s) do
    case s.by_to[to] do
      %{ref: ^ref} = inv ->
        for u <- [inv.from, inv.to] do
          send_to(u, {:pk_invite, nil})
          send_to(u, {:notice, "⚔ Lời mời cược đấu đã hết hạn."})
        end

        {:noreply, remove(s, inv)}

      _ ->
        {:noreply, s}
    end
  end

  defp busy?(s, uid), do: Map.has_key?(s.by_to, uid) or Map.has_key?(s.by_from, uid)

  defp remove(s, inv),
    do: %{s | by_to: Map.delete(s.by_to, inv.to), by_from: Map.delete(s.by_from, inv.from)}

  defp public(inv), do: Map.take(inv, [:from, :to, :name, :level, :cls, :wager, :expires])

  # ---------- Đánh và trả vàng ----------

  @doc """
  Chạy trận cược của lời mời `inv` (đã `take/1`). Trả `{:ok, kết_quả}` hoặc `{:error, lý_do}`; kết quả
  cũng gửi cho người mời qua `{:pk_result, ...}`.
  """
  def execute(inv) do
    with {:ok, ra, pa} <- hold(inv.from, inv.name),
         {:ok, rb, pb} <- hold_or_release(inv, ra) do
      result =
        try do
          settle(inv, pa, pb)
        rescue
          e ->
            Logger.error("PK cược #{inv.from}-#{inv.to} lỗi: " <> Exception.message(e))
            {:error, "Lỗi máy chủ, chưa ai mất gì."}
        end

      case result do
        {:ok, pa2, pb2, view} ->
          Session.release(inv.from, ra, pa2)
          Session.release(inv.to, rb, pb2)
          send_to(inv.from, {:pk_result, view})
          {:ok, view}

        err ->
          Session.release(inv.from, ra, nil)
          Session.release(inv.to, rb, nil)
          {:error, msg} = err
          send_to(inv.from, {:notice, "⚔ Cược đấu chưa diễn ra: #{msg}"})
          err
      end
    end
  end

  defp hold(uid, name) do
    case Session.hold(uid) do
      {:ok, ref, nil} ->
        Session.release(uid, ref, nil)
        {:error, "#{name}: chưa có nhân vật."}

      {:ok, _, _} = ok ->
        ok

      _ ->
        {:error, "#{name} đang bận."}
    end
  end

  defp hold_or_release(inv, ra) do
    case hold(inv.to, "Người được mời") do
      {:ok, _, _} = ok ->
        ok

      err ->
        Session.release(inv.from, ra, nil)
        send_to(inv.from, {:notice, "⚔ Cược đấu chưa diễn ra: #{elem(err, 1)}"})
        err
    end
  end

  @doc false
  def settle(inv, pa, pb) do
    w = inv.wager
    day = Date.from_iso8601!(Daily.today())

    with :ok <- ready(pa, w),
         :ok <- ready(pb, w),
         :ok <- under_limit(inv.from, pa.name, day),
         :ok <- under_limit(inv.to, pb.name, day) do
      r = PkFight.fight(Arena.opponent(pa, inv.from), Arena.opponent(pb, inv.to))

      {winner, pa2, pb2} =
        case r.winner do
          :a -> {inv.from, %{pa | gold: pa.gold + w}, %{pb | gold: pb.gold - w}}
          :b -> {inv.to, %{pa | gold: pa.gold - w}, %{pb | gold: pb.gold + w}}
          :draw -> {nil, pa, pb}
        end

      {:ok, id} =
        Repo.transaction(fn ->
          {1, [%{id: id}]} =
            Repo.insert_all(
              "pk_matches",
              [
                %{
                  a_id: inv.from,
                  b_id: inv.to,
                  a_name: pa.name,
                  b_name: pb.name,
                  wager: w,
                  winner_id: winner,
                  rounds: r.rounds,
                  day: day,
                  inserted_at: DateTime.truncate(DateTime.utc_now(), :second)
                }
              ],
              returning: [:id]
            )

          Characters.save!(inv.from, pa2, "PK_BET", "pk:#{id}")
          Characters.save!(inv.to, pb2, "PK_BET", "pk:#{id}")
          id
        end)

      view = %{
        id: id,
        a: %{uid: inv.from, name: pa.name, level: pa.level, cls: pa.cls},
        b: %{uid: inv.to, name: pb.name, level: pb.level, cls: pb.cls},
        wager: w,
        winner: winner,
        rounds: r.rounds,
        log: r.log
      }

      {:ok, pa2, pb2, view}
    end
  end

  defp ready(p, w) do
    cond do
      p.battle -> {:error, "#{p.name} đang trong trận."}
      p.hp <= 0 -> {:error, "#{p.name} đã gục, cần hồi máu."}
      p.gold < w -> {:error, "#{p.name} không đủ #{w} vàng."}
      true -> :ok
    end
  end

  defp under_limit(uid, name, day) do
    if today_count(uid, day) >= @pk.per_day,
      do: {:error, "#{name} đã cược đủ #{@pk.per_day} trận hôm nay."},
      else: :ok
  end

  defp send_to(uid, msg), do: Phoenix.PubSub.broadcast(HacLong.PubSub, Session.topic(uid), msg)
end

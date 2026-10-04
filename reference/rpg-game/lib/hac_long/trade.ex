defmodule HacLong.Trade do
  @moduledoc """
  Giao dịch trực tiếp giữa hai người chơi đang online (giữ trong bộ nhớ).

  1. `request/3`: A mời B; B nhận `{:trade_request, %{from, name}}` trên kênh người chơi.
  2. `accept/2` (B) mở bảng giao dịch; `decline/1` / `cancel/1` (một trong hai) hủy.
  3. `offer/2`: đặt những món mình đưa ra (đã kiểm tra bằng `HacLong.Game.TradeOffer.parse/2`).
     Đổi món của bất kỳ bên nào thì cả hai phải xác nhận lại.
  4. `ready/1`: xác nhận. Cả hai cùng xác nhận thì đổi (`execute/1`, chạy ngoài tiến trình
     này vì phải gọi `Session` của hai người): giữ Session của A rồi B (`Session.hold/1`), tính
     đồ hai bên, ghi cả hai nhân vật trong một transaction (nhật ký vàng/đồ lý do `TRADE`), rồi
     nhả (`Session.release/3`). Lỗi ở bất kỳ bước nào thì không ai đổi gì.

  Mỗi khi bảng giao dịch đổi, cả hai nhận `{:trade, view | nil}` (xem `view/2`).
  """
  use GenServer
  require Logger

  alias HacLong.Repo
  alias HacLong.Game.{Characters, Session, TradeOffer}

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: {:ok, %{trades: %{}, of: %{}, next: 1}}

  def request(from, name, to), do: GenServer.call(__MODULE__, {:request, from, name, to})
  def accept(uid, name), do: GenServer.call(__MODULE__, {:accept, uid, name})
  def decline(uid), do: GenServer.call(__MODULE__, {:cancel, uid, "từ chối"})
  def cancel(uid), do: GenServer.call(__MODULE__, {:cancel, uid, "hủy giao dịch"})
  def offer(uid, offer), do: GenServer.call(__MODULE__, {:offer, uid, offer})
  def ready(uid), do: GenServer.call(__MODULE__, {:ready, uid})

  @doc "Bảng giao dịch của `uid` nhìn từ phía người đó (nil nếu không có)."
  def of(uid), do: GenServer.call(__MODULE__, {:of, uid})

  @doc false
  def reset, do: GenServer.call(__MODULE__, :reset)

  # ---------- Máy chủ ----------

  @impl true
  def handle_call({:request, from, name, to}, _from, s) do
    cond do
      from == to ->
        {:reply, {:error, "Không tự giao dịch với mình được."}, s}

      Map.has_key?(s.of, from) ->
        {:reply, {:error, "Bạn đang có một giao dịch khác."}, s}

      Map.has_key?(s.of, to) ->
        {:reply, {:error, "Người này đang bận giao dịch."}, s}

      true ->
        id = s.next

        t = %{
          id: id,
          a: from,
          b: to,
          names: %{from => name},
          status: :pending,
          offers: %{from => TradeOffer.empty(), to => TradeOffer.empty()},
          ready: %{from => false, to => false}
        }

        s = %{
          s
          | trades: Map.put(s.trades, id, t),
            of: s.of |> Map.put(from, id) |> Map.put(to, id),
            next: id + 1
        }

        send_to(to, {:trade_request, %{from: from, name: name}})
        push(t, [from])
        {:reply, :ok, s}
    end
  end

  def handle_call({:accept, uid, name}, _from, s) do
    case trade(s, uid) do
      %{status: :pending, b: ^uid} = t ->
        t = %{t | status: :open, names: Map.put(t.names, uid, name)}
        push(t)
        {:reply, :ok, put(s, t)}

      _ ->
        {:reply, {:error, "Lời mời không còn nữa."}, s}
    end
  end

  def handle_call({:cancel, uid, why}, _from, s) do
    case trade(s, uid) do
      %{status: :executing} ->
        {:reply, {:error, "Đang đổi đồ, đợi một chút."}, s}

      nil ->
        {:reply, :ok, s}

      t ->
        other = other(t, uid)
        send_to(other, {:notice, "#{name(t, uid)} đã #{why}."})
        {:reply, :ok, drop(s, t)}
    end
  end

  def handle_call({:offer, uid, offer}, _from, s) do
    case trade(s, uid) do
      %{status: :open} = t ->
        t = %{
          t
          | offers: Map.put(t.offers, uid, offer),
            ready: Map.new(t.ready, fn {k, _} -> {k, false} end)
        }

        push(t)
        {:reply, :ok, put(s, t)}

      _ ->
        {:reply, {:error, "Không có giao dịch nào đang mở."}, s}
    end
  end

  def handle_call({:ready, uid}, _from, s) do
    case trade(s, uid) do
      %{status: :open} = t ->
        t = %{t | ready: Map.put(t.ready, uid, true)}

        t =
          if Enum.all?(Map.values(t.ready)) do
            # chạy ngoài GenServer: Session của hai người có thể đang gọi vào đây
            me = self()
            Task.start(fn -> send(me, {:executed, t.id, execute(t)}) end)
            %{t | status: :executing}
          else
            t
          end

        push(t)
        {:reply, :ok, put(s, t)}

      _ ->
        {:reply, {:error, "Không có giao dịch nào đang mở."}, s}
    end
  end

  def handle_call({:of, uid}, _from, s) do
    {:reply, (t = trade(s, uid)) && view(t, uid), s}
  end

  def handle_call(:reset, _from, _s), do: {:reply, :ok, elem(init(:ok), 1)}

  @impl true
  def handle_info({:executed, id, result}, s) do
    case s.trades[id] do
      nil ->
        {:noreply, s}

      t ->
        case result do
          :ok ->
            for uid <- [t.a, t.b] do
              send_to(
                uid,
                {:notice,
                 "🤝 Giao dịch xong: nhận #{TradeOffer.summary(t.offers[other(t, uid)])}."}
              )
            end

            {:noreply, drop(s, t)}

          {:error, msg} ->
            # không đổi được (thiếu đồ, túi đầy...): mở lại, hai bên xác nhận lại
            t = %{t | status: :open, ready: %{t.a => false, t.b => false}}
            for uid <- [t.a, t.b], do: send_to(uid, {:notice, "Giao dịch chưa thành: #{msg}"})
            push(t)
            {:noreply, put(s, t)}
        end
    end
  end

  # ---------- Đổi đồ ----------

  # Giữ Session của hai người (lệnh khác của họ xếp hàng đợi), tính đồ của cả hai bằng hàm
  # thuần rồi ghi hai nhân vật trong MỘT transaction: hoặc cả hai đổi, hoặc không ai đổi.
  @doc false
  def execute(t) do
    with {:ok, ra, pa} <- Session.hold(t.a) |> who(t, t.a),
         {:ok, rb, pb} <- hold_or_release(t, ra) do
      result =
        try do
          settle(t, pa, pb)
        rescue
          e ->
            Logger.error("Giao dịch #{t.id} lỗi: " <> Exception.message(e))
            {:error, "Lỗi máy chủ, chưa đổi gì."}
        end

      case result do
        {:ok, pa2, pb2} ->
          Session.release(t.a, ra, pa2)
          Session.release(t.b, rb, pb2)
          :ok

        err ->
          Session.release(t.a, ra, nil)
          Session.release(t.b, rb, nil)
          err
      end
    end
  end

  defp hold_or_release(t, ra) do
    case Session.hold(t.b) |> who(t, t.b) do
      {:ok, _, _} = ok ->
        ok

      err ->
        Session.release(t.a, ra, nil)
        err
    end
  end

  defp settle(t, pa, pb) do
    oa = t.offers[t.a]
    ob = t.offers[t.b]

    with {:ok, pa, ga} <- TradeOffer.take(pa, oa, length(ob.gear)) |> who(t, t.a),
         {:ok, pb, gb} <- TradeOffer.take(pb, ob, length(oa.gear)) |> who(t, t.b) do
      pa = TradeOffer.give(pa, gb)
      pb = TradeOffer.give(pb, ga)
      ref = "trade:#{t.a}-#{t.b}-#{System.system_time(:millisecond)}"

      {:ok, _} =
        Repo.transaction(fn ->
          Characters.save!(t.a, pa, "TRADE", ref)
          Characters.save!(t.b, pb, "TRADE", ref)
        end)

      {:ok, pa, pb}
    end
  end

  defp who({:error, msg}, t, uid), do: {:error, "#{name(t, uid)}: #{msg}"}
  defp who(ok, _t, _uid), do: ok

  # ---------- Tiện ích ----------

  defp trade(s, uid), do: (id = s.of[uid]) && s.trades[id]
  defp put(s, t), do: %{s | trades: Map.put(s.trades, t.id, t)}

  defp drop(s, t) do
    for uid <- [t.a, t.b], do: send_to(uid, {:trade, nil})
    %{s | trades: Map.delete(s.trades, t.id), of: Map.drop(s.of, [t.a, t.b])}
  end

  defp other(t, uid), do: if(uid == t.a, do: t.b, else: t.a)
  defp name(t, uid), do: Map.get(t.names, uid) || "Người kia"

  @doc "Bảng giao dịch nhìn từ phía `uid`."
  def view(t, uid) do
    o = other(t, uid)

    %{
      id: t.id,
      partner: o,
      partner_name: name(t, o),
      status: t.status,
      incoming: t.status == :pending and uid == t.b,
      mine: t.offers[uid],
      theirs: t.offers[o],
      my_ready: t.ready[uid],
      their_ready: t.ready[o]
    }
  end

  defp push(t, who \\ nil) do
    for uid <- who || [t.a, t.b], do: send_to(uid, {:trade, view(t, uid)})
  end

  defp send_to(uid, msg), do: Phoenix.PubSub.broadcast(HacLong.PubSub, Session.topic(uid), msg)
end

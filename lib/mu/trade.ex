defmodule Mu.Trade do
  @moduledoc """
  Giao dịch giữa hai tài khoản (`KB_TECHNICAL §10`, P5-M4 theo P5-5). Mỗi giao dịch là một
  tiến trình `Mu.Trade.Settlement` dưới `DynamicSupervisor` `Mu.Trade.Supervisor`; trạng thái
  (đồ đặt lên bàn, Zen, khóa, đồng ý) **chỉ** nằm ở đó, không nằm trong Session và không ghi DB
  cho tới khi chốt (`Mu.Game.Items.trade/3`, một transaction).

  Registry `Mu.Trade.Registry` (khóa unique):
  - `{:cid, cid}` → giao dịch của nhân vật (người mời từ lúc mời; người nhận từ lúc nhận) ⇒ mỗi
    nhân vật tối đa một giao dịch;
  - `{:invite, cid người được mời, tên người mời chữ thường}` → lời mời đang chờ.

  Session gọi các hàm dưới đây (tiến trình gọi = Session). Settlement không bao giờ gọi Session
  (chỉ gửi tin `{:trade_push, event, payload}` / `{:trade_done, result}`) nên không khóa chéo.
  """

  alias Mu.Trade.Settlement

  @registry Mu.Trade.Registry

  @doc """
  `me`, `target`: `%{cid, name, session}` (đã kiểm cùng map, trong tầm ở MapServer). Mời giao dịch:
  `:ok` hoặc `{:error, code}`.
  """
  def request(me, target, map_id) do
    cond do
      whereis(me.cid) -> {:error, "FORBIDDEN"}
      whereis(target.cid) -> {:error, "FORBIDDEN"}
      true -> start(me, target, map_id)
    end
  end

  defp start(me, target, map_id) do
    case DynamicSupervisor.start_child(
           Mu.Trade.Supervisor,
           {Settlement, %{from: me, to: target, map_id: map_id}}
         ) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "FORBIDDEN"}
    end
  end

  @doc "Nhận lời mời của `from` (tên)."
  def accept(me, from), do: invite_call(me.cid, from, {:accept, me})

  @doc "Từ chối lời mời của `from` (tên)."
  def decline(cid, from), do: invite_call(cid, from, {:decline, cid})

  defp invite_call(cid, from, msg) when is_binary(from) do
    case Registry.lookup(@registry, {:invite, cid, String.downcase(from)}) do
      [{pid, _}] -> safe_call(pid, msg)
      [] -> {:error, "INVALID_TARGET"}
    end
  end

  defp invite_call(_cid, _from, _msg), do: {:error, "INVALID_TARGET"}

  @doc "Đặt món `view` (`Characters.item_view/1`, đồ trong túi) lên bàn."
  def put(cid, view), do: mine(cid, {:put, cid, view})
  def take(cid, item_id), do: mine(cid, {:take, cid, item_id})
  def zen(cid, amount), do: mine(cid, {:zen, cid, amount})
  def lock(cid), do: mine(cid, {:lock, cid})
  def confirm(cid), do: mine(cid, {:confirm, cid})
  def cancel(cid), do: mine(cid, {:cancel, cid, "cancelled"})

  @doc "Hủy giao dịch của `cid` (nếu có) vì `reason` (mất kết nối, đổi map, chết, …) — bất đồng bộ."
  def close(cid, reason) do
    if pid = whereis(cid), do: GenServer.cast(pid, {:close, cid, reason})
    :ok
  end

  @doc "Túi của `cid` vừa đổi: món trên bàn không còn trong túi thì gỡ (bất đồng bộ)."
  def sync(cid, items) do
    if pid = whereis(cid) do
      ids = for it <- items, it.location == "INVENTORY", into: MapSet.new(), do: it.id
      GenServer.cast(pid, {:sync, cid, ids})
    end

    :ok
  end

  @doc "Giao dịch đang mở / đang mời của `cid` (pid) hoặc `nil`."
  def whereis(cid) do
    case Registry.lookup(@registry, {:cid, cid}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp mine(cid, msg) do
    case whereis(cid) do
      nil -> {:error, "INVALID_TARGET"}
      pid -> safe_call(pid, msg)
    end
  end

  # giao dịch vừa kết thúc đúng lúc gọi
  defp safe_call(pid, msg) do
    GenServer.call(pid, msg)
  catch
    :exit, _ -> {:error, "INVALID_TARGET"}
  end
end

defmodule Mu.Trade.Settlement do
  @moduledoc """
  Một giao dịch (`Mu.Trade`). Pha `:pending` (chờ người được mời nhận, `trade.inviteSeconds`) →
  `:open`. Mỗi bên: món trên bàn (tối đa `trade.maxItems`, cả stack từ túi), Zen, `locked`,
  `confirmed`. Mọi thay đổi bỏ khóa + đồng ý của cả hai; chỉ đồng ý được khi cả hai đã khóa; cả
  hai đồng ý → `Items.trade/3`. Hủy: bấm Hủy, mất kết nối / Session tắt (monitor), đổi map, chết,
  cách nhau > `trade.cancelRange` ô (kiểm mỗi giây), quá `trade.timeoutSeconds`.

  Event `trade` tới hai Session: `%{state: "open", partner, mine, theirs, error?}` (`mine` /
  `theirs` = `%{items, zen, locked, confirmed}`) hoặc `%{state: "closed", partner, result,
  by?}` (`result`: `done`, `cancelled`, `declined`, `timeout`, `far`, `disconnect`, `map`,
  `dead`).
  """
  use GenServer, restart: :temporary

  alias Mu.Game.{Config, Items}
  alias Mu.World.MapServer

  @registry Mu.Trade.Registry

  def start_link(arg), do: GenServer.start_link(__MODULE__, arg)

  @impl true
  def init(%{from: from, to: to, map_id: map_id}) do
    cfg = Config.get(["trade"])

    with {:ok, _} <- Registry.register(@registry, {:cid, from.cid}, nil),
         {:ok, _} <-
           Registry.register(@registry, {:invite, to.cid, String.downcase(from.name)}, nil) do
      send(
        to.session,
        {:trade_push, "trade_invite", %{from: from.name, seconds: cfg["inviteSeconds"]}}
      )

      Process.send_after(self(), :invite_timeout, cfg["inviteSeconds"] * 1000)

      {:ok,
       %{
         id: "trade:" <> Integer.to_string(System.unique_integer([:positive])),
         phase: :pending,
         map_id: map_id,
         a: from.cid,
         b: to.cid,
         sides: %{from.cid => side(from), to.cid => side(to)},
         error: nil
       }}
    else
      _ -> :ignore
    end
  end

  defp side(p),
    do: %{
      cid: p.cid,
      name: p.name,
      session: p.session,
      items: [],
      zen: 0,
      locked: false,
      confirmed: false
    }

  # ---------- Mời ----------

  @impl true
  def handle_call({:accept, %{cid: b} = me}, _from, %{phase: :pending, b: b} = s) do
    case Registry.register(@registry, {:cid, b}, nil) do
      {:ok, _} ->
        Registry.unregister(@registry, {:invite, b, String.downcase(s.sides[s.a].name)})
        for {_, sd} <- s.sides, do: Process.monitor(sd.session)
        s = put_in(s.sides[b].session, me.session)
        Process.send_after(self(), :timeout, Config.get(["trade", "timeoutSeconds"]) * 1000)
        schedule()
        s = %{s | phase: :open}
        push_state(s)
        {:reply, :ok, s}

      {:error, _} ->
        {:reply, {:error, "FORBIDDEN"}, s}
    end
  end

  def handle_call({:decline, cid}, _from, %{phase: :pending, b: cid} = s) do
    {:stop, :normal, :ok, closed(s, "declined", s.sides[cid].name)}
  end

  def handle_call({kind, _}, _from, s) when kind in [:accept, :decline],
    do: {:reply, {:error, "INVALID_TARGET"}, s}

  # người mời hủy lời mời đang chờ
  def handle_call({:cancel, cid, reason}, _from, s) do
    {:stop, :normal, :ok, closed(s, reason, s.sides[cid].name)}
  end

  def handle_call(_msg, _from, %{phase: :pending} = s),
    do: {:reply, {:error, "INVALID_TARGET"}, s}

  # ---------- Bàn giao dịch ----------

  def handle_call({:put, cid, view}, _from, s) do
    sd = s.sides[cid]

    cond do
      sd.locked -> {:reply, {:error, "FORBIDDEN"}, s}
      Enum.any?(sd.items, &(&1.id == view.id)) -> {:reply, {:error, "INVALID_TARGET"}, s}
      length(sd.items) >= Config.get(["trade", "maxItems"]) -> {:reply, {:error, "FORBIDDEN"}, s}
      true -> changed(s, cid, &%{&1 | items: &1.items ++ [view]})
    end
  end

  def handle_call({:take, cid, item_id}, _from, s) do
    sd = s.sides[cid]

    cond do
      sd.locked ->
        {:reply, {:error, "FORBIDDEN"}, s}

      not Enum.any?(sd.items, &(&1.id == item_id)) ->
        {:reply, {:error, "INVALID_TARGET"}, s}

      true ->
        changed(s, cid, &%{&1 | items: Enum.reject(&1.items, fn it -> it.id == item_id end)})
    end
  end

  def handle_call({:zen, cid, amount}, _from, s) do
    if s.sides[cid].locked,
      do: {:reply, {:error, "FORBIDDEN"}, s},
      else: changed(s, cid, &%{&1 | zen: amount})
  end

  def handle_call({:lock, cid}, _from, s) do
    s = put_in(s.sides[cid].locked, true)
    push_state(%{s | error: nil})
    {:reply, :ok, %{s | error: nil}}
  end

  def handle_call({:confirm, cid}, _from, s) do
    if Enum.all?(s.sides, fn {_, sd} -> sd.locked end) do
      s = put_in(s.sides[cid].confirmed, true)

      if Enum.all?(s.sides, fn {_, sd} -> sd.confirmed end) do
        settle(s)
      else
        push_state(s)
        {:reply, :ok, s}
      end
    else
      {:reply, {:error, "FORBIDDEN"}, s}
    end
  end

  # ---------- Hủy / đồng bộ ----------

  @impl true
  def handle_cast({:close, cid, reason}, s),
    do: {:stop, :normal, closed(s, reason, s.sides[cid] && s.sides[cid].name)}

  def handle_cast({:sync, cid, ids}, %{phase: :open} = s) do
    sd = s.sides[cid]
    kept = Enum.filter(sd.items, &MapSet.member?(ids, &1.id))

    if length(kept) == length(sd.items) do
      {:noreply, s}
    else
      {:reply, :ok, s} = changed(s, cid, &%{&1 | items: kept})
      {:noreply, s}
    end
  end

  def handle_cast({:sync, _, _}, s), do: {:noreply, s}

  @impl true
  def handle_info(:invite_timeout, %{phase: :pending} = s),
    do: {:stop, :normal, closed(s, "timeout", nil)}

  def handle_info(:timeout, %{phase: :open} = s), do: {:stop, :normal, closed(s, "timeout", nil)}

  def handle_info(:tick, %{phase: :open} = s) do
    schedule()

    # một người chết / rời map: `nil` → hủy
    case MapServer.distance(s.map_id, s.a, s.b) do
      d when is_integer(d) ->
        if d > Config.get(["trade", "cancelRange"]),
          do: {:stop, :normal, closed(s, "far", nil)},
          else: {:noreply, s}

      nil ->
        {:stop, :normal, closed(s, "far", nil)}
    end
  catch
    :exit, _ -> {:stop, :normal, closed(s, "far", nil)}
  end

  def handle_info({:DOWN, _ref, :process, pid, _}, s) do
    who = Enum.find_value(s.sides, fn {_, sd} -> sd.session == pid && sd.name end)
    {:stop, :normal, closed(s, "disconnect", who)}
  end

  def handle_info(_msg, s), do: {:noreply, s}

  # ---------- Nội bộ ----------

  # thay đổi bàn của `cid`: bỏ khóa + đồng ý của cả hai, đẩy trạng thái
  defp changed(s, cid, fun) do
    s = update_in(s.sides[cid], fun)

    s = %{
      s
      | sides: Map.new(s.sides, fn {k, sd} -> {k, %{sd | locked: false, confirmed: false}} end),
        error: nil
    }

    push_state(s)
    {:reply, :ok, s}
  end

  defp settle(s) do
    side = fn cid ->
      %{cid: cid, items: Enum.map(s.sides[cid].items, & &1.id), zen: s.sides[cid].zen}
    end

    case Items.trade(side.(s.a), side.(s.b), s.id) do
      {:ok, res} ->
        for {cid, sd} <- s.sides, do: send(sd.session, {:trade_done, res[cid]})
        {:stop, :normal, :ok, closed(s, "done", nil)}

      {:error, code} ->
        # chốt hỏng (túi đầy, đồ đã đổi chỗ, thiếu Zen): giữ giao dịch, bỏ khóa cả hai
        s = %{
          s
          | sides:
              Map.new(s.sides, fn {k, sd} -> {k, %{sd | locked: false, confirmed: false}} end),
            error: code
        }

        push_state(s)
        {:reply, {:error, code}, s}
    end
  end

  defp push_state(s) do
    for {cid, sd} <- s.sides do
      other = s.sides[other(s, cid)]

      send(
        sd.session,
        {:trade_push, "trade",
         %{
           state: "open",
           partner: other.name,
           mine: view(sd),
           theirs: view(other),
           error: s.error
         }}
      )
    end

    :ok
  end

  defp view(sd), do: %{items: sd.items, zen: sd.zen, locked: sd.locked, confirmed: sd.confirmed}

  # báo kết thúc cho hai bên (lời mời chưa nhận: chỉ người mời có bàn)
  defp closed(s, result, by) do
    targets = if s.phase == :pending, do: [s.a], else: [s.a, s.b]

    for cid <- targets do
      send(
        s.sides[cid].session,
        {:trade_push, "trade",
         %{state: "closed", partner: s.sides[other(s, cid)].name, result: result, by: by}}
      )
    end

    s
  end

  defp other(%{a: a, b: b}, cid), do: if(cid == a, do: b, else: a)

  defp schedule, do: Process.send_after(self(), :tick, 1000)
end

defmodule Mu.Game.Session do
  @moduledoc """
  Một tiến trình / tài khoản đang online (`KB_TECH_STACK §4`), giữ trạng thái nhân vật.
  Mọi lệnh của tài khoản đi qua đúng tiến trình này nên được xử lý tuần tự.

  Khung lấy từ `HacLong.Game.Session` (Registry + DynamicSupervisor, `call` thử lại khi
  tiến trình vừa tự tắt, theo dõi tab bằng monitor, `trap_exit` + ghi nốt khi tắt).

  - `session.singleLoginPerAccount`: tab mới vào thì tab cũ nhận `{:session_kicked, _}`;
    nhân vật vẫn ở trên map (cùng Session), chỉ đổi tab.
  - Vị trí do `Mu.World.MapServer` giữ khi đang online (một chiều sở hữu, PHASE1_PLAN R5);
    Session ghi DB mỗi `session.saveIntervalSeconds` nếu đổi, và ngay khi rời map.
  - Tab cuối đóng → rời map ngay và lưu (G21; ở lại khi đang combat thêm ở M3).
  """
  use GenServer, restart: :transient
  require Logger

  alias Mu.Game.{Characters, Config, Stats}
  alias Mu.World.MapServer

  # không còn tab nào trong khoảng này thì tự tắt
  @idle_timeout :timer.minutes(1)

  @doc """
  Tab `pid` vào game với nhân vật `character_id`.
  `{:ok, character, map_info}` (`map_info`: `MapServer.join/3`) hoặc `{:error, :not_found}`.
  """
  def attach(account_id, character_id, pid), do: call(account_id, {:attach, character_id, pid})

  @doc "Nhân vật đang được giữ (`nil` nếu chưa có tab nào vào)."
  def get(account_id), do: call(account_id, :get)

  @doc "Lệnh `act` đã qua kiểm tra phong bì/rate-limit: `:ok` hoặc `{:error, code}`."
  def command(account_id, act, payload), do: call(account_id, {:command, act, payload})

  @doc "Pid của Session nếu đang chạy."
  def whereis(account_id) do
    case Registry.lookup(Mu.Game.Registry, account_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp call(account_id, msg, retry \\ true) do
    pid =
      case DynamicSupervisor.start_child(Mu.Game.SessionSupervisor, {__MODULE__, account_id}) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    GenServer.call(pid, msg)
  catch
    # tiến trình vừa tự tắt vì rảnh đúng lúc gọi: khởi động lại và thử một lần nữa
    :exit, {reason, _} when retry and reason in [:noproc, :normal] ->
      call(account_id, msg, false)
  end

  def start_link(account_id) do
    GenServer.start_link(__MODULE__, account_id,
      name: {:via, Registry, {Mu.Game.Registry, account_id}}
    )
  end

  @impl true
  def init(account_id) do
    Process.flag(:trap_exit, true)

    {:ok, %{account_id: account_id, character: nil, tabs: %{}, on_map: false, save_timer: nil},
     @idle_timeout}
  end

  @impl true
  def handle_call({:attach, character_id, pid}, _from, s) do
    case load(s, character_id) do
      nil ->
        reply({:error, :not_found}, s)

      character ->
        # nhân vật khác với nhân vật đang trên map (Phase 1 không xảy ra: 1 nhân vật/tài khoản)
        s = if s.character && s.character.id != character.id, do: leave_map(s), else: s
        s = kick_tabs(%{s | character: character}, pid)
        s = %{s | tabs: Map.put(s.tabs, Process.monitor(pid), pid)}

        {:ok, info} = MapServer.join(character.map_id, map_player(character), self())

        c = %{s.character | position_x: info.x, position_y: info.y}
        s = %{s | character: c, on_map: true} |> schedule_save()
        reply({:ok, c, info}, s)
    end
  end

  def handle_call(:get, _from, s), do: reply(s.character, s)

  def handle_call({:command, "move_to", %{"x" => x, "y" => y}}, _from, %{on_map: true} = s) do
    reply(MapServer.move_to(s.character.map_id, s.character.id, x, y), s)
  end

  def handle_call({:command, "move_to", _}, _from, s), do: reply({:error, "INVALID_TARGET"}, s)

  # act khác: M3 (attack, skill, alloc), M4 (item, shop) — DEC-16
  def handle_call({:command, _act, _payload}, _from, s), do: reply({:error, "FORBIDDEN"}, s)

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, s) do
    s = %{s | tabs: Map.delete(s.tabs, ref)}
    s = if map_size(s.tabs) == 0, do: leave_map(s), else: s
    {:noreply, s, timeout(s)}
  end

  def handle_info(:save, %{on_map: true} = s) do
    s = %{s | save_timer: nil}

    s =
      case MapServer.position(s.character.map_id, s.character.id) do
        {x, y} -> save_position(s, x, y)
        nil -> s
      end

    {:noreply, schedule_save(s), timeout(s)}
  end

  def handle_info(:timeout, %{tabs: tabs} = s) when map_size(tabs) == 0,
    do: {:stop, :normal, s}

  def handle_info(_msg, s), do: {:noreply, s, timeout(s)}

  @impl true
  def terminate(_reason, s) do
    leave_map(s)
    :ok
  end

  # Nhân vật đang giữ trùng id thì dùng luôn (không đọc lại DB, tránh mất trạng thái chưa lưu)
  defp load(%{character: %{id: id} = c}, id), do: c
  defp load(s, character_id), do: Characters.get_owned(s.account_id, character_id)

  defp kick_tabs(s, pid) do
    if Config.get(["session", "singleLoginPerAccount"]) do
      for {ref, old} <- s.tabs, old != pid do
        Process.demonitor(ref, [:flush])
        send(old, {:session_kicked, :new_login})
      end

      %{s | tabs: %{}}
    else
      s
    end
  end

  defp map_player(c) do
    %{
      character_id: c.id,
      name: c.name,
      level: c.level,
      hp: c.hp_current,
      hp_max: Stats.hp_max(c.class, c.level, c.vitality),
      x: c.position_x,
      y: c.position_y
    }
  end

  defp leave_map(%{on_map: true, character: c} = s) do
    if s.save_timer, do: Process.cancel_timer(s.save_timer)
    s = %{s | on_map: false, save_timer: nil}

    case MapServer.leave(c.map_id, c.id) do
      {:ok, {x, y}} -> save_position(s, x, y)
      :error -> s
    end
  end

  defp leave_map(s), do: s

  defp save_position(s, x, y) do
    case Characters.save_position(s.character, x, y) do
      {:ok, c} ->
        %{s | character: c}

      {:error, reason} ->
        Logger.error("Không lưu được vị trí #{s.character.id}: #{inspect(reason)}")
        s
    end
  end

  defp schedule_save(%{save_timer: nil} = s) do
    ms = Config.get(["session", "saveIntervalSeconds"]) * 1000
    %{s | save_timer: Process.send_after(self(), :save, ms)}
  end

  defp schedule_save(s), do: s

  defp reply(result, s), do: {:reply, result, s, timeout(s)}

  defp timeout(%{tabs: tabs}) when map_size(tabs) == 0, do: @idle_timeout
  defp timeout(_), do: :infinity
end

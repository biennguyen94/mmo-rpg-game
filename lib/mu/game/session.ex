defmodule Mu.Game.Session do
  @moduledoc """
  Một tiến trình / tài khoản đang online (`KB_TECH_STACK §4`), giữ trạng thái nhân vật.
  Mọi lệnh của tài khoản đi qua đúng tiến trình này nên được xử lý tuần tự.

  Khung lấy từ `HacLong.Game.Session` (Registry + DynamicSupervisor, `call` thử lại khi
  tiến trình vừa tự tắt, theo dõi tab bằng monitor, tự tắt khi rảnh). Khác repo nền:
  `session.singleLoginPerAccount` — tab mới vào thì tab cũ bị đá (`{:session_kicked, reason}`).

  M1 chỉ có attach/get. Di chuyển, lưu DB debounce, idempotency theo `rid`... thêm ở M2–M4.
  """
  use GenServer, restart: :transient

  alias Mu.Game.{Characters, Config}

  # không còn tab nào trong khoảng này thì tự tắt
  @idle_timeout :timer.minutes(1)

  @doc """
  Tab `pid` vào game với nhân vật `character_id`. `{:ok, character}` hoặc `{:error, :not_found}`.
  Tab đang gắn trước đó (nếu có và `singleLoginPerAccount`) nhận `{:session_kicked, :new_login}`.
  """
  def attach(account_id, character_id, pid), do: call(account_id, {:attach, character_id, pid})

  @doc "Nhân vật đang được giữ (`nil` nếu chưa có tab nào vào)."
  def get(account_id), do: call(account_id, :get)

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
    {:ok, %{account_id: account_id, character: nil, tabs: %{}}, @idle_timeout}
  end

  @impl true
  def handle_call({:attach, character_id, pid}, _from, s) do
    case load(s, character_id) do
      nil ->
        reply({:error, :not_found}, s)

      character ->
        if Config.get(["session", "singleLoginPerAccount"]) do
          for {ref, old} <- s.tabs, old != pid do
            Process.demonitor(ref, [:flush])
            send(old, {:session_kicked, :new_login})
          end
        end

        tabs =
          if Config.get(["session", "singleLoginPerAccount"]), do: %{}, else: s.tabs

        s = %{s | character: character, tabs: Map.put(tabs, Process.monitor(pid), pid)}
        reply({:ok, character}, s)
    end
  end

  def handle_call(:get, _from, s), do: reply(s.character, s)

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, s) do
    s = %{s | tabs: Map.delete(s.tabs, ref)}
    {:noreply, s, timeout(s)}
  end

  def handle_info(:timeout, %{tabs: tabs} = s) when map_size(tabs) == 0,
    do: {:stop, :normal, s}

  def handle_info(_msg, s), do: {:noreply, s, timeout(s)}

  # Nhân vật đang giữ trùng id thì dùng luôn (không đọc lại DB, tránh mất trạng thái chưa lưu)
  defp load(%{character: %{id: id} = c}, id), do: c
  defp load(s, character_id), do: Characters.get_owned(s.account_id, character_id)

  defp reply(result, s), do: {:reply, result, s, timeout(s)}

  defp timeout(%{tabs: tabs}) when map_size(tabs) == 0, do: @idle_timeout
  defp timeout(_), do: :infinity
end

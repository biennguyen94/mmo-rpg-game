defmodule Mu.Game.OrphanSweeper do
  @moduledoc """
  Job dọn item orphan định kỳ (`KB_TECHNICAL §9`: mỗi giờ, log rồi xóa). Việc dọn ở
  `Mu.Game.Items.delete_orphans/0`.
  """
  use GenServer
  require Logger

  @every :timer.hours(1)

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    Process.send_after(self(), :sweep, @every)
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, s) do
    case Mu.Game.Items.delete_orphans() do
      {:ok, 0} -> :ok
      {:ok, n} -> Logger.warning("Đã xóa #{n} item orphan (xem item_audit_log ORPHAN_DELETE)")
      other -> Logger.error("Dọn item orphan lỗi: #{inspect(other)}")
    end

    Process.send_after(self(), :sweep, @every)
    {:noreply, s}
  end
end

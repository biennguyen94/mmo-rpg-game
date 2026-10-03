defmodule Mu.Accounts.WsTicket do
  @moduledoc """
  WS ticket dùng một lần (`KB_TECHNICAL §4`): sinh ngẫu nhiên, lưu ETS với TTL
  `auth.wsTicketTtlSeconds`, xóa ngay khi dùng. Không nằm trong DB.

  ETS là theo từng node: chạy nhiều node phải chuyển sang store dùng chung hoặc sticky routing.
  `:ets.take/2` lấy và xóa trong một thao tác nên hai kết nối dùng cùng ticket chỉ một cái qua.
  """
  use GenServer

  alias Mu.Game.Config

  @table __MODULE__
  @sweep_ms :timer.minutes(1)

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Sinh ticket cho tài khoản. `now` (ms, monotonic) chỉ truyền trong test."
  def issue(account_id, now \\ now()) do
    ticket = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    expires = now + Config.get(["auth", "wsTicketTtlSeconds"]) * 1000
    true = :ets.insert_new(@table, {ticket, account_id, expires})
    ticket
  end

  @doc "Dùng ticket: `{:ok, account_id}` (ticket bị xóa) hoặc `:error` (sai, đã dùng, hết hạn)."
  def consume(ticket, now \\ now())

  def consume(ticket, now) when is_binary(ticket) do
    case :ets.take(@table, ticket) do
      [{^ticket, account_id, expires}] when now < expires -> {:ok, account_id}
      _ -> :error
    end
  end

  def consume(_, _), do: :error

  defp now, do: System.monotonic_time(:millisecond)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, s) do
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now()}], [true]}])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:noreply, s}
  end
end

defmodule HacLong.Accounts.WsTicket do
  @moduledoc """
  Vé WebSocket dùng một lần (lấy từ MU Web, FEATURE_CATALOG I1).

  Trước đây client mở `/socket?token=<token đăng nhập 30 ngày>`: token nằm trong URL nên có thể
  lọt vào log proxy / máy chủ. Nay client gọi `POST /api/ws-ticket` (token ở header) lấy một vé
  ngẫu nhiên, sống `@ttl_ms`, rồi mở `/socket?ticket=<vé>`; vé bị xóa ngay khi dùng.

  Lưu ETS (không DB). `:ets.take/2` lấy và xóa trong một thao tác nên hai kết nối dùng cùng vé
  chỉ một cái qua. ETS theo từng node: chạy nhiều node phải đổi sang store dùng chung.
  """
  use GenServer

  @table __MODULE__
  @ttl_ms 30_000
  @sweep_ms :timer.minutes(1)

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Thời gian sống của vé (ms)."
  def ttl_ms, do: @ttl_ms

  @doc "Sinh vé cho `user_id`. `now` (ms, monotonic) chỉ truyền trong test."
  def issue(user_id, now \\ now()) do
    ticket = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    true = :ets.insert_new(@table, {ticket, user_id, now + @ttl_ms})
    ticket
  end

  @doc "Dùng vé: `{:ok, user_id}` (vé bị xóa) hoặc `:error` (sai, đã dùng, hết hạn)."
  def consume(ticket, now \\ now())

  def consume(ticket, now) when is_binary(ticket) do
    case :ets.take(@table, ticket) do
      [{^ticket, user_id, expires}] when now < expires -> {:ok, user_id}
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

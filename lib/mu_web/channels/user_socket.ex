defmodule MuWeb.UserSocket do
  @moduledoc """
  WebSocket `/socket?ticket=...`: ticket một lần lấy từ `POST /ws-ticket`, bị xóa ngay khi
  kiểm tra (`KB_TECHNICAL §4`). Repo nền dùng thẳng access token ở đây; KB yêu cầu ticket.
  """
  use Phoenix.Socket

  channel "game", MuWeb.GameChannel

  @impl true
  def connect(%{"ticket" => ticket}, socket, _connect_info) do
    case Mu.Accounts.consume_ws_ticket(ticket) do
      {:ok, account} -> {:ok, assign(socket, account_id: account.id, username: account.username)}
      :error -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "account_socket:#{socket.assigns.account_id}"
end

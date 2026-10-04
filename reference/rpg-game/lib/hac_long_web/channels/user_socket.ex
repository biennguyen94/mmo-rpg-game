defmodule HacLongWeb.UserSocket do
  use Phoenix.Socket

  channel "game", HacLongWeb.GameChannel

  @impl true
  # Mở bằng vé dùng một lần (`POST /api/ws-ticket`), không nhận token đăng nhập trong URL nữa.
  def connect(%{"ticket" => ticket}, socket, _connect_info) do
    case HacLong.Accounts.consume_ws_ticket(ticket) do
      {:ok, user} ->
        {:ok, assign(socket, user_id: user.id, username: user.username, admin: user.admin)}

      _ ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end

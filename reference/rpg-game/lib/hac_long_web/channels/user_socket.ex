defmodule HacLongWeb.UserSocket do
  use Phoenix.Socket

  channel "game", HacLongWeb.GameChannel

  @impl true
  # Mở bằng vé dùng một lần (`POST /api/ws-ticket`), không nhận token đăng nhập trong URL nữa.
  def connect(%{"ticket" => ticket}, socket, _connect_info) do
    case HacLong.Accounts.consume_ws_ticket(ticket) do
      # `user_id`: mã người chơi của nhân vật đang vào; tên đăng nhập, vai trò lấy từ tài khoản (DECISIONS "Nhiều nhân
      # vật"). Mỗi tài khoản một nhân vật online: ngắt kết nối và tắt Session của các nhân vật khác.
      {:ok, user, acct} ->
        for sib <- HacLong.Accounts.siblings(user.id) do
          Phoenix.PubSub.broadcast(HacLong.PubSub, HacLong.Game.Session.topic(sib), :kicked)
          HacLong.Game.Session.stop(sib)
        end

        {:ok,
         assign(socket,
           user_id: user.id,
           account_id: acct.id,
           username: acct.username,
           role: acct.role
         )}

      _ ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end

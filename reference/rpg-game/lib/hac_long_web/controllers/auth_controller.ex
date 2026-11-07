defmodule HacLongWeb.AuthController do
  use HacLongWeb, :controller

  alias HacLong.{Accounts, RateLimit}

  # Giới hạn để chống dò mật khẩu và tạo tài khoản hàng loạt: {số lần, trong bao lâu}.
  @login_per_ip {30, :timer.minutes(5)}
  @login_per_name {10, :timer.minutes(5)}
  @register_per_ip {5, :timer.hours(1)}
  @password_per_user {5, :timer.minutes(5)}
  @ws_ticket_per_user {20, :timer.minutes(1)}
  @new_char_per_user {10, :timer.minutes(10)}
  @forgot_per_ip {5, :timer.hours(1)}
  # câu hỏi bảo mật: xem câu hỏi / trả lời (chống dò câu trả lời)
  @question_per_ip {30, :timer.hours(1)}
  @account HacLong.Game.Data.rules().account
  @recover_per_user {@account.recover_per_user, :timer.minutes(@account.recover_window_min)}
  @recover_per_ip {20, :timer.hours(1)}

  def register(conn, params) do
    with :ok <- limit(conn, {:register, ip(conn)}, @register_per_ip) do
      case Accounts.register(Map.take(params, ["username", "password", "question", "answer"])) do
        {:ok, user} ->
          conn |> put_status(:created) |> json(session(user))

        {:error, cs} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: first_error(cs)})
      end
    end
  end

  def login(conn, params) do
    name = params["username"] |> to_string() |> String.trim() |> String.downcase()

    with :ok <- limit(conn, {:login_ip, ip(conn)}, @login_per_ip),
         :ok <- limit(conn, {:login_name, name}, @login_per_name) do
      case Accounts.authenticate(params["username"], params["password"]) do
        {:ok, user} ->
          json(conn, session(user))

        {:error, {:banned, user}} ->
          conn |> put_status(:forbidden) |> json(%{error: banned_msg(user)})

        {:error, _} ->
          conn |> put_status(:unauthorized) |> json(%{error: "Sai tên đăng nhập hoặc mật khẩu."})
      end
    end
  end

  @doc "Quên mật khẩu: ghi yêu cầu cho quản trị (luôn trả ok, không lộ tài khoản có tồn tại hay không)."
  def forgot(conn, params) do
    with :ok <- limit(conn, {:forgot, ip(conn)}, @forgot_per_ip) do
      Accounts.PasswordReset.request(to_string(params["username"]), to_string(params["contact"]))
      json(conn, %{ok: true})
    end
  end

  @doc """
  Quên mật khẩu bằng câu hỏi bảo mật, bước 1: câu hỏi của tài khoản (`{question: id | nil}`; nil thì gửi yêu cầu cho
  quản trị như cũ).
  """
  def question(conn, params) do
    with :ok <- limit(conn, {:question, ip(conn)}, @question_per_ip) do
      json(conn, %{question: Accounts.security_question(to_string(params["username"]))})
    end
  end

  @doc "Bước 2: trả lời đúng thì đặt mật khẩu mới, đăng xuất mọi thiết bị khác, đăng nhập luôn."
  def recover(conn, params) do
    name = params["username"] |> to_string() |> String.trim() |> String.downcase()

    with :ok <- limit(conn, {:recover_ip, ip(conn)}, @recover_per_ip),
         :ok <- limit(conn, {:recover_name, name}, @recover_per_user) do
      case Accounts.recover(name, params["answer"], params["password"]) do
        {:ok, user} ->
          disconnect(user)
          json(conn, session(user))

        {:error, :invalid} ->
          conn |> put_status(:unauthorized) |> json(%{error: "Câu trả lời không đúng."})

        {:error, cs} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: first_error(cs)})
      end
    end
  end

  @doc "Đặt / đổi câu hỏi bảo mật (cần mật khẩu hiện tại)."
  def security(conn, params) do
    with {:ok, user, _token} <- current(conn),
         :ok <- limit(conn, {:password, user.id}, @password_per_user) do
      case Accounts.set_security(
             user,
             to_string(params["current"]),
             params["question"],
             params["answer"]
           ) do
        {:ok, user} ->
          json(conn, %{ok: true, question: user.security_question})

        {:error, :invalid} ->
          conn |> put_status(:unauthorized) |> json(%{error: "Mật khẩu hiện tại không đúng."})

        {:error, cs} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: first_error(cs)})
      end
    end
  end

  def me(conn, _params) do
    with {:ok, user, _token} <- current(conn) do
      json(conn, %{
        username: user.username,
        question: user.security_question,
        characters: Accounts.characters(user.id),
        max_characters: Accounts.max_characters()
      })
    end
  end

  @doc """
  Chỗ tạo nhân vật mới (DECISIONS "Nhiều nhân vật"): `{cid}` — mã để lấy vé WebSocket vào màn tạo nhân vật; đã đủ số
  nhân vật thì lỗi.
  """
  def new_character(conn, _params) do
    with {:ok, user, _token} <- current(conn),
         :ok <- limit(conn, {:new_char, user.id}, @new_char_per_user) do
      case Accounts.character_slot(user) do
        {:ok, cid} -> json(conn, %{cid: cid})
        {:error, msg} -> conn |> put_status(:unprocessable_entity) |> json(%{error: msg})
      end
    end
  end

  @doc "Xóa nhân vật: gõ lại tên nhân vật và mật khẩu tài khoản. Đồ trên nhân vật mất hẳn."
  def delete_character(conn, params) do
    with {:ok, user, _token} <- current(conn),
         :ok <- limit(conn, {:password, user.id}, @password_per_user) do
      case Accounts.delete_character(user, params["cid"], params["name"], params["password"]) do
        {:ok, name} ->
          json(conn, %{ok: true, msg: "Đã xóa #{name}.", characters: Accounts.characters(user.id)})

        {:error, msg} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: msg})
      end
    end
  end

  @doc "Đăng xuất thiết bị này (thu hồi token đang dùng)."
  def logout(conn, _params) do
    with {:ok, _user, token} <- current(conn) do
      Accounts.revoke_token(token)
      json(conn, %{ok: true})
    end
  end

  @doc "Đăng xuất mọi thiết bị: thu hồi mọi token và ngắt mọi kết nối game đang mở."
  def logout_all(conn, _params) do
    with {:ok, user, _token} <- current(conn) do
      Accounts.revoke_all(user)
      disconnect(user)
      json(conn, %{ok: true})
    end
  end

  @doc "Đổi mật khẩu. Mọi thiết bị khác bị đăng xuất; thiết bị này nhận token mới."
  def password(conn, params) do
    with {:ok, user, _token} <- current(conn),
         :ok <- limit(conn, {:password, user.id}, @password_per_user) do
      case Accounts.change_password(user, to_string(params["current"]), params["password"]) do
        {:ok, user} ->
          disconnect(user)
          json(conn, session(user))

        {:error, :invalid} ->
          conn |> put_status(:unauthorized) |> json(%{error: "Mật khẩu hiện tại không đúng."})

        {:error, cs} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: first_error(cs)})
      end
    end
  end

  @doc """
  Vé WebSocket dùng một lần (`{ticket}`), sống vài chục giây: client lấy trước mỗi lần mở / mở lại
  WebSocket, để token đăng nhập không nằm trong URL `/socket`.
  """
  def ws_ticket(conn, params) do
    with {:ok, user, _token} <- current(conn),
         :ok <- limit(conn, {:ws_ticket, user.id}, @ws_ticket_per_user) do
      # `cid`: nhân vật muốn vào (mặc định nhân vật trên dòng tài khoản)
      case Accounts.issue_ws_ticket(user, if(is_integer(params["cid"]), do: params["cid"])) do
        nil -> conn |> put_status(:forbidden) |> json(%{error: "Không có nhân vật này."})
        ticket -> json(conn, %{ticket: ticket})
      end
    end
  end

  # ---------- Nội bộ ----------

  defp current(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Accounts.verify_token(token) do
      {:ok, user, token}
    else
      _ -> conn |> put_status(:unauthorized) |> json(%{error: "Phiên đăng nhập đã hết hạn."})
    end
  end

  defp limit(conn, key, {n, window}) do
    case RateLimit.hit(key, n, window) do
      :ok ->
        :ok

      {:error, secs} ->
        wait = if secs >= 60, do: "#{div(secs + 59, 60)} phút", else: "#{secs} giây"

        conn
        |> put_resp_header("retry-after", Integer.to_string(secs))
        |> put_status(:too_many_requests)
        |> json(%{error: "Thử quá nhiều lần. Đợi #{wait} rồi thử lại."})
    end
  end

  # Ngắt mọi WebSocket của tài khoản này, mọi nhân vật (xem `HacLongWeb.UserSocket.id/1`).
  defp disconnect(user) do
    for id <- Accounts.account_rows(user.id),
        do: HacLongWeb.Endpoint.broadcast("user_socket:#{id}", "disconnect", %{})
  end

  # Địa chỉ IP của người gọi (đã tính X-Forwarded-For nếu có proxy tin cậy, xem
  # HacLongWeb.RemoteIp).
  defp ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp banned_msg(user) do
    until =
      if user.banned_until.year >= 9999,
        do: "vĩnh viễn",
        else:
          "đến " <> Calendar.strftime(DateTime.add(user.banned_until, 7 * 3600), "%H:%M %d/%m/%Y")

    "Tài khoản bị khóa #{until}" <> if(user.ban_reason, do: ": #{user.ban_reason}.", else: ".")
  end

  defp session(user), do: %{token: Accounts.sign_token(user), username: user.username}

  @labels %{
    username: "Tên đăng nhập",
    password: "Mật khẩu",
    security_question: "Câu hỏi bảo mật",
    security_answer: "Câu trả lời"
  }

  defp first_error(cs) do
    {field, {msg, _}} = hd(cs.errors)
    "#{Map.get(@labels, field, field)} #{msg}."
  end
end

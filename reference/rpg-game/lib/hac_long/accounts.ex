defmodule HacLong.Accounts do
  @moduledoc "Tài khoản người chơi: đăng ký, đăng nhập, token đăng nhập, đổi mật khẩu."

  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Accounts.{Password, User, UserToken}

  # token đăng nhập có hạn 30 ngày
  @token_max_age 30 * 24 * 3600

  def get_user(id), do: Repo.get(User, id)

  def register(attrs) do
    %User{} |> User.registration_changeset(attrs) |> Repo.insert()
  end

  def authenticate(username, password) when is_binary(username) and is_binary(password) do
    user = Repo.get_by(User, username: username |> String.trim() |> String.downcase())

    cond do
      user && Password.verify(password, user.password_hash) ->
        if banned?(user), do: {:error, {:banned, user}}, else: {:ok, user}

      user ->
        {:error, :invalid}

      true ->
        # chạy hash giả để thời gian phản hồi không lộ tên đăng nhập có tồn tại hay không
        Password.no_user_verify()
        {:error, :invalid}
    end
  end

  def authenticate(_, _), do: {:error, :invalid}

  @doc "Tài khoản đang bị khóa?"
  def banned?(%User{banned_until: nil}), do: false
  def banned?(%User{banned_until: t}), do: DateTime.compare(t, DateTime.utc_now()) == :gt

  @doc "Đang bị cấm chat?"
  def muted?(%User{muted_until: nil}), do: false
  def muted?(%User{muted_until: t}), do: DateTime.compare(t, DateTime.utc_now()) == :gt

  # ---------- Token đăng nhập ----------
  # Token là chuỗi ngẫu nhiên 32 byte; database chỉ giữ mã băm của nó. Mỗi lần đăng nhập
  # một token mới (mỗi thiết bị một token), xóa token là đăng xuất thiết bị đó.

  @doc "Tạo token đăng nhập mới cho `user`."
  def sign_token(%User{id: id}) do
    token = :crypto.strong_rand_bytes(32)
    Repo.insert!(%UserToken{user_id: id, token_hash: hash(token)})
    Base.url_encode64(token, padding: false)
  end

  def verify_token(token) when is_binary(token) do
    cutoff = DateTime.add(DateTime.utc_now(), -@token_max_age, :second)

    with {:ok, raw} <- Base.url_decode64(token, padding: false),
         %User{} = user <-
           Repo.one(
             from t in UserToken,
               join: u in assoc(t, :user),
               where: t.token_hash == ^hash(raw) and t.inserted_at > ^cutoff,
               select: u
           ),
         false <- banned?(user) do
      {:ok, user}
    else
      _ -> {:error, :invalid}
    end
  end

  def verify_token(_), do: {:error, :invalid}

  @doc "Vé WebSocket dùng một lần cho `user` (xem `HacLong.Accounts.WsTicket`)."
  def issue_ws_ticket(%User{id: id}), do: HacLong.Accounts.WsTicket.issue(id)

  @doc "Dùng vé WebSocket: `{:ok, user}` (vé bị xóa) hoặc `:error` (sai / đã dùng / hết hạn / bị khóa)."
  def consume_ws_ticket(ticket) do
    with {:ok, id} <- HacLong.Accounts.WsTicket.consume(ticket),
         %User{} = user <- get_user(id),
         false <- banned?(user) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  @doc "Đăng xuất thiết bị đang dùng `token`."
  def revoke_token(token) when is_binary(token) do
    with {:ok, raw} <- Base.url_decode64(token, padding: false) do
      Repo.delete_all(from t in UserToken, where: t.token_hash == ^hash(raw))
    end

    :ok
  end

  def revoke_token(_), do: :ok

  @doc "Đăng xuất mọi thiết bị của `user`."
  def revoke_all(%User{id: id}) do
    Repo.delete_all(from t in UserToken, where: t.user_id == ^id)
    :ok
  end

  @doc "Đổi mật khẩu: kiểm tra mật khẩu cũ, rồi thu hồi mọi token cũ."
  def change_password(%User{} = user, current, new) do
    with {:ok, _} <- authenticate(user.username, current) do
      cs = User.password_changeset(user, %{"password" => new})

      case Repo.update(cs) do
        {:ok, user} ->
          revoke_all(user)
          {:ok, user}

        error ->
          error
      end
    end
  end

  # ---------- Câu hỏi bảo mật (DECISIONS "Câu hỏi bảo mật") ----------

  @doc "Câu trả lời chuẩn hóa trước khi băm / so: bỏ khoảng trắng thừa, không phân biệt hoa thường."
  def normalize_answer(a) when is_binary(a),
    do:
      a
      |> :unicode.characters_to_nfc_binary()
      |> String.downcase()
      |> String.split()
      |> Enum.join(" ")

  def normalize_answer(_), do: nil

  @doc "Câu hỏi bảo mật của tài khoản `username` (id), nil nếu không có tài khoản / chưa đặt (tài khoản bot: nil)."
  def security_question(username) when is_binary(username) do
    case Repo.get_by(User, username: username |> String.trim() |> String.downcase()) do
      %User{role: role, security_question: q} when role != "bot" -> q
      _ -> nil
    end
  end

  def security_question(_), do: nil

  @doc """
  Quên mật khẩu: câu trả lời đúng thì đặt mật khẩu mới và đăng xuất mọi thiết bị. `{:ok, user}`,
  `{:error, :invalid}` (sai / không có tài khoản / chưa đặt câu hỏi) hoặc `{:error, changeset}` (mật khẩu mới không hợp lệ).
  """
  def recover(username, answer, new_password) when is_binary(username) do
    u = Repo.get_by(User, username: username |> String.trim() |> String.downcase())
    a = normalize_answer(answer)

    cond do
      u == nil or u.role == "bot" or u.security_answer_hash == nil or a == nil ->
        Password.no_user_verify()
        {:error, :invalid}

      not Password.verify(a, u.security_answer_hash) ->
        {:error, :invalid}

      true ->
        case Repo.update(User.password_changeset(u, %{"password" => new_password})) do
          {:ok, u} ->
            revoke_all(u)
            {:ok, u}

          error ->
            error
        end
    end
  end

  def recover(_, _, _), do: {:error, :invalid}

  @doc "Đặt / đổi câu hỏi bảo mật: cần mật khẩu hiện tại."
  def set_security(%User{} = user, current, question, answer) do
    with {:ok, _} <- authenticate(user.username, current) do
      user
      |> User.security_changeset(%{"question" => question, "answer" => answer})
      |> Repo.update()
    end
  end

  defp hash(raw), do: :crypto.hash(:sha256, raw)
end

defmodule Mu.Accounts do
  @moduledoc """
  Tài khoản: đăng ký, đăng nhập (Argon2id), access token băm trong DB, WS ticket
  (`KB_TECHNICAL §4`). Học từ `HacLong.Accounts` của repo nền (token băm, hash giả khi
  không có tài khoản); bỏ ban/mute/đổi mật khẩu (ngoài Phase 1).
  """

  import Ecto.Query

  alias Mu.Repo
  alias Mu.Accounts.{Account, AccessToken, WsTicket}
  alias Mu.Game.Config

  def get_account(id), do: Repo.get(Account, id)

  def register(attrs) do
    %Account{} |> Account.registration_changeset(attrs) |> Repo.insert()
  end

  @doc "`{:ok, account}` hoặc `{:error, :invalid}` (không lộ tên đăng nhập có tồn tại hay không)."
  def authenticate(username, password) when is_binary(username) and is_binary(password) do
    name = String.trim(username)

    account =
      Repo.one(
        from a in Account, where: fragment("lower(?)", a.username) == ^String.downcase(name)
      )

    cond do
      account && Argon2.verify_pass(password, account.password_hash) ->
        {:ok, account}

      account ->
        {:error, :invalid}

      true ->
        # chạy hash giả để thời gian phản hồi không lộ tên đăng nhập có tồn tại hay không
        Argon2.no_user_verify()
        {:error, :invalid}
    end
  end

  def authenticate(_, _), do: {:error, :invalid}

  # ---------- Access token ----------
  # 32 byte ngẫu nhiên (256 bit); DB chỉ giữ SHA-256. Mỗi lần đăng nhập một token.

  @doc "Tạo access token mới. Trả về chuỗi gửi cho client (chỉ lần này)."
  def create_access_token(%Account{id: id}) do
    token = :crypto.strong_rand_bytes(32)
    ttl = Config.get(["auth", "accessTokenTtlSeconds"])

    Repo.insert!(%AccessToken{
      account_id: id,
      token_hash: hash(token),
      expires_at: DateTime.add(DateTime.utc_now(), ttl, :second)
    })

    Base.url_encode64(token, padding: false)
  end

  @doc "`{:ok, account}` nếu token đúng và chưa hết hạn."
  def verify_access_token(token) when is_binary(token) do
    now = DateTime.utc_now()

    with {:ok, raw} <- Base.url_decode64(token, padding: false),
         %Account{} = account <-
           Repo.one(
             from t in AccessToken,
               join: a in assoc(t, :account),
               where: t.token_hash == ^hash(raw) and t.expires_at > ^now,
               select: a
           ) do
      {:ok, account}
    else
      _ -> {:error, :invalid}
    end
  end

  def verify_access_token(_), do: {:error, :invalid}

  @doc "Thu hồi token (đăng xuất thiết bị đó)."
  def revoke_access_token(token) when is_binary(token) do
    with {:ok, raw} <- Base.url_decode64(token, padding: false) do
      Repo.delete_all(from t in AccessToken, where: t.token_hash == ^hash(raw))
    end

    :ok
  end

  def revoke_access_token(_), do: :ok

  @doc "Xóa các token đã hết hạn (dọn dẹp, trả về số row đã xóa)."
  def delete_expired_tokens do
    now = DateTime.utc_now()
    {n, _} = Repo.delete_all(from t in AccessToken, where: t.expires_at <= ^now)
    n
  end

  # ---------- WS ticket ----------

  @doc "Ticket một lần để mở WebSocket."
  def issue_ws_ticket(%Account{id: id}), do: WsTicket.issue(id)

  @doc "Dùng ticket (xóa ngay): `{:ok, account}` hoặc `:error`."
  def consume_ws_ticket(ticket) do
    with {:ok, id} <- WsTicket.consume(ticket),
         %Account{} = account <- get_account(id) do
      {:ok, account}
    else
      _ -> :error
    end
  end

  defp hash(raw), do: :crypto.hash(:sha256, raw)
end

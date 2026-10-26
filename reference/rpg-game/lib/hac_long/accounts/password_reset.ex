defmodule HacLong.Accounts.PasswordReset do
  @moduledoc """
  Quên mật khẩu (DECISIONS "Quên mật khẩu"): tài khoản không có email, nên người chơi gửi yêu cầu
  (tên đăng nhập + cách liên lạc: Zalo, Facebook, số điện thoại…), quản trị thấy ở tab Quản trị,
  đặt lại mật khẩu tạm (`reset/2`) rồi báo cho người chơi. Đặt lại thì mọi thiết bị bị đăng xuất.
  """
  use Ecto.Schema
  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Accounts
  alias HacLong.Accounts.User

  schema "password_resets" do
    belongs_to :user, User
    field :contact, :string
    field :resolved_at, :utc_datetime
    field :resolved_by, :id
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Ghi yêu cầu cho tài khoản `username`. Luôn trả `:ok` (không lộ tên đăng nhập có tồn tại hay không).
  """
  def request(username, contact) when is_binary(username) and is_binary(contact) do
    contact = contact |> String.trim() |> String.slice(0, 120)

    with true <- contact != "",
         %User{role: role} = u when role != "bot" <-
           Repo.get_by(User, username: username |> String.trim() |> String.downcase()) do
      # mỗi tài khoản một yêu cầu chờ xử lý: gửi lại thì thay cái cũ
      Repo.delete_all(from r in __MODULE__, where: r.user_id == ^u.id and is_nil(r.resolved_at))

      Repo.insert!(%__MODULE__{user_id: u.id, contact: contact})
    end

    :ok
  end

  def request(_, _), do: :ok

  @doc "Yêu cầu chưa xử lý, mới nhất trước: `[%{id, uid, username, contact, at}]`."
  def open do
    from(r in __MODULE__,
      join: u in assoc(r, :user),
      where: is_nil(r.resolved_at),
      order_by: [desc: r.id],
      limit: 50,
      select: %{id: r.id, uid: u.id, username: u.username, contact: r.contact, at: r.inserted_at}
    )
    |> Repo.all()
  end

  @doc """
  Quản trị `admin_id` đặt lại mật khẩu người chơi `uid`: mật khẩu tạm ngẫu nhiên, thu hồi mọi token,
  đóng các yêu cầu của người đó. Trả `{:ok, username, mật khẩu tạm}`.
  """
  def reset(uid, admin_id) do
    with %User{} = u <- Repo.get(User, uid),
         temp = temp_password(),
         {:ok, u} <- u |> User.password_changeset(%{"password" => temp}) |> Repo.update() do
      Accounts.revoke_all(u)
      HacLongWeb.Endpoint.broadcast("user_socket:#{u.id}", "disconnect", %{})

      from(r in __MODULE__, where: r.user_id == ^u.id and is_nil(r.resolved_at))
      |> Repo.update_all(set: [resolved_at: DateTime.utc_now(:second), resolved_by: admin_id])

      {:ok, u.username, temp}
    else
      nil -> {:error, "Không có tài khoản này."}
      {:error, _} -> {:error, "Không đặt lại được mật khẩu."}
    end
  end

  @doc "Bỏ qua một yêu cầu (không đặt lại)."
  def dismiss(id, admin_id) do
    from(r in __MODULE__, where: r.id == ^id and is_nil(r.resolved_at))
    |> Repo.update_all(set: [resolved_at: DateTime.utc_now(:second), resolved_by: admin_id])

    :ok
  end

  # 8 ký tự dễ đọc (bỏ 0/O, 1/l/I)
  @alphabet ~c"abcdefghjkmnpqrstuvwxyz23456789"
  defp temp_password do
    for _ <- 1..8, into: "", do: <<Enum.random(@alphabet)>>
  end
end

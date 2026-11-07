defmodule HacLong.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    # "player" | "mod" (xử lý báo cáo, cấm chat) | "admin" (mọi lệnh quản trị)
    field :role, :string, default: "player"
    field :banned_until, :utc_datetime
    field :ban_reason, :string
    field :muted_until, :utc_datetime

    # câu hỏi bảo mật (id trong `RULES.account.security_questions`) và câu trả lời đã băm (DECISIONS "Câu hỏi bảo mật")
    field :security_question, :string
    field :security_answer, :string, virtual: true, redact: true
    field :security_answer_hash, :string, redact: true

    # nhân vật thêm của tài khoản (DECISIONS "Nhiều nhân vật"): dòng `users` riêng, trỏ về tài khoản đăng nhập;
    # nil = chính là tài khoản (đăng nhập được, có thể giữ nhân vật đầu tiên)
    belongs_to :account, __MODULE__
    timestamps(type: :utc_datetime)
  end

  # vai trò quản trị đặt được; tài khoản người chơi AI có `role = "bot"` (Phase 16, `HacLong.Bots`)
  @roles ~w(player mod admin)
  def roles, do: @roles

  @doc "Quản trị viên (mọi lệnh)."
  def admin?(%{role: role}), do: role == "admin"

  @doc "Người kiểm duyệt hoặc quản trị viên (thấy tab Quản trị)."
  def staff?(%{role: role}), do: role in ~w(mod admin)

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password])
    |> update_change(:username, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:username, :password], message: "không được để trống")
    |> validate_length(:username, min: 3, max: 20, message: "phải dài 3–20 ký tự")
    |> validate_format(:username, ~r/^[a-z0-9_]+$/,
      message: "chỉ gồm chữ không dấu, số và dấu gạch dưới"
    )
    |> validate_length(:password, min: 6, max: 72, message: "phải dài 6–72 ký tự")
    |> unique_constraint(:username, message: "đã có người dùng")
    |> hash_password()
    |> security(attrs, false)
  end

  @doc "Đặt / đổi câu hỏi bảo mật (`question`, `answer`)."
  def security_changeset(user, attrs), do: security(change(user), attrs, true)

  @account HacLong.Game.Data.rules().account
  @questions Enum.map(@account.security_questions, & &1.id)

  def questions, do: @questions

  # đăng ký: câu hỏi không bắt buộc ở server (tài khoản tạo bằng công cụ, test); có một trong hai thì phải đủ cả hai
  defp security(cs, attrs, required?) do
    q = attrs["question"] || attrs[:question]
    a = attrs["answer"] || attrs[:answer]

    if required? or q not in [nil, ""] or a not in [nil, ""] do
      a = HacLong.Accounts.normalize_answer(a)

      cs
      |> put_change(:security_question, q)
      |> put_change(:security_answer, a)
      |> validate_required([:security_question], message: "chưa chọn")
      |> validate_inclusion(:security_question, @questions, message: "không hợp lệ")
      |> validate_required([:security_answer], message: "không được để trống")
      |> validate_length(:security_answer,
        min: @account.answer_min,
        max: @account.answer_max,
        message: "phải dài #{@account.answer_min}–#{@account.answer_max} ký tự"
      )
      |> hash_answer()
    else
      cs
    end
  end

  defp hash_answer(%{valid?: true, changes: %{security_answer: a}} = cs) do
    cs
    |> put_change(:security_answer_hash, HacLong.Accounts.Password.hash(a))
    |> delete_change(:security_answer)
  end

  defp hash_answer(cs), do: cs

  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password], message: "không được để trống")
    |> validate_length(:password, min: 6, max: 72, message: "phải dài 6–72 ký tự")
    |> hash_password()
  end

  defp hash_password(%{valid?: true, changes: %{password: pw}} = cs) do
    cs
    |> put_change(:password_hash, HacLong.Accounts.Password.hash(pw))
    |> delete_change(:password)
  end

  defp hash_password(cs), do: cs
end

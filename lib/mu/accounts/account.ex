defmodule Mu.Accounts.Account do
  @moduledoc "Bảng `accounts` (`KB_TECHNICAL §9`). Mật khẩu băm Argon2id."
  use Ecto.Schema
  import Ecto.Changeset

  alias Mu.Game.Config

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "accounts" do
    field :username, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :status, :integer, default: 0
    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime_usec)
  end

  def registration_changeset(account, attrs) do
    names = Config.get(["names"])

    account
    |> cast(attrs, [:username, :email, :password])
    |> update_change(:username, &String.trim/1)
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:username, :password], message: "không được để trống")
    |> validate_format(:username, Regex.compile!(names["usernamePattern"]),
      message: "phải dài 3–32 ký tự, chỉ gồm chữ không dấu, số và dấu gạch dưới"
    )
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/, message: "không hợp lệ")
    |> validate_length(:password,
      min: names["passwordMinLength"],
      max: names["passwordMaxLength"],
      message: "phải dài #{names["passwordMinLength"]}–#{names["passwordMaxLength"]} ký tự"
    )
    |> unique_constraint(:username, name: :accounts_username_ci, message: "đã có người dùng")
    |> unique_constraint(:email, name: :accounts_email_key, message: "đã có người dùng")
    |> hash_password()
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(email) do
    case String.trim(email) do
      "" -> nil
      e -> String.downcase(e)
    end
  end

  defp hash_password(%{valid?: true, changes: %{password: pw}} = cs) do
    cs |> put_change(:password_hash, Argon2.hash_pwd_salt(pw)) |> delete_change(:password)
  end

  defp hash_password(cs), do: cs
end

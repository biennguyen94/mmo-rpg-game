defmodule Mu.Accounts.AccessToken do
  @moduledoc """
  Access token đăng nhập (`KB_TECHNICAL §4`): DB chỉ giữ SHA-256 của token, có hạn
  (`auth.accessTokenTtlSeconds`), xóa row là thu hồi.
  """
  use Ecto.Schema

  @foreign_key_type :binary_id
  schema "access_tokens" do
    belongs_to :account, Mu.Accounts.Account
    field :token_hash, :binary
    field :expires_at, :utc_datetime_usec
    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime_usec)
  end
end

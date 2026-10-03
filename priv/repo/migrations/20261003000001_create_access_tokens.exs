defmodule Mu.Repo.Migrations.CreateAccessTokens do
  @moduledoc """
  CHANGE_REASON: `KB_TECHNICAL §4` yêu cầu access token ngẫu nhiên, DB chỉ lưu **hash**,
  có TTL, thu hồi được, nhưng §9 không có bảng cho nó. Bảng này là phần tối thiểu để làm
  đúng §4 (xem docs/DECISIONS.md). WS ticket không nằm trong DB (ETS, §4).
  """
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE access_tokens (
      id BIGSERIAL PRIMARY KEY,
      account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      token_hash BYTEA NOT NULL UNIQUE,
      expires_at TIMESTAMPTZ NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """

    execute "CREATE INDEX access_tokens_account_id ON access_tokens (account_id)"
  end

  def down do
    execute "DROP TABLE access_tokens"
  end
end

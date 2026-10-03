defmodule Mu.Repo.Migrations.CreatePhase1Schema do
  @moduledoc """
  Schema Phase 1 theo `docs/kb/KB_TECHNICAL.md §9` (viết bằng SQL để giữ đúng từng CHECK,
  partial index và kiểu cột). Bảng `access_tokens` không có trong §9: xem migration sau.
  """
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE accounts (
      id UUID PRIMARY KEY,
      username VARCHAR(32) NOT NULL,
      email TEXT UNIQUE,
      password_hash TEXT NOT NULL,
      status SMALLINT NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """

    execute "CREATE UNIQUE INDEX accounts_username_ci ON accounts (lower(username))"

    execute """
    CREATE TABLE characters (
      id UUID PRIMARY KEY,
      account_id UUID NOT NULL REFERENCES accounts(id),
      name VARCHAR(10) NOT NULL CHECK (name ~ '^[A-Za-z0-9]{4,10}$'),
      class VARCHAR(8) NOT NULL CHECK (class IN ('DK','DW','ELF','MG')),
      level INT NOT NULL DEFAULT 1,
      experience BIGINT NOT NULL DEFAULT 0,
      strength INT NOT NULL, agility INT NOT NULL, vitality INT NOT NULL, energy INT NOT NULL,
      free_stat_points INT NOT NULL DEFAULT 0,
      hp_current INT NOT NULL, mana_current INT NOT NULL,
      zen BIGINT NOT NULL DEFAULT 0 CHECK (zen >= 0),
      map_id VARCHAR(32) NOT NULL, position_x INT NOT NULL, position_y INT NOT NULL,
      pk_points INT NOT NULL DEFAULT 0,
      last_pk_at TIMESTAMPTZ,
      version INT NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """

    execute "CREATE UNIQUE INDEX characters_name_ci ON characters (lower(name))"

    # tra nhân vật theo tài khoản (không có trong §9; chỉ là index, không đổi dữ liệu)
    execute "CREATE INDEX characters_account_id ON characters (account_id)"

    execute """
    CREATE TABLE items (
      id UUID PRIMARY KEY,
      serial CHAR(26) NOT NULL UNIQUE,
      template_id VARCHAR(50) NOT NULL,
      quantity INT NOT NULL DEFAULT 1 CHECK (quantity >= 1),
      item_level SMALLINT NOT NULL DEFAULT 0,
      durability INT,
      luck BOOLEAN NOT NULL DEFAULT FALSE,
      skill BOOLEAN NOT NULL DEFAULT FALSE,
      excellent_options JSONB NOT NULL DEFAULT '[]',
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """

    execute """
    CREATE TABLE item_locations (
      item_id UUID PRIMARY KEY REFERENCES items(id),
      location VARCHAR(12) NOT NULL CHECK (location IN ('INVENTORY','EQUIPMENT','WAREHOUSE')),
      character_id UUID REFERENCES characters(id) ON DELETE CASCADE,
      account_id   UUID REFERENCES accounts(id)   ON DELETE CASCADE,
      slot INT NOT NULL,
      CHECK (
        (location IN ('INVENTORY','EQUIPMENT') AND character_id IS NOT NULL AND account_id IS NULL)
        OR
        (location = 'WAREHOUSE' AND account_id IS NOT NULL AND character_id IS NULL)
      ),
      CHECK (
        (location = 'EQUIPMENT' AND slot BETWEEN 0 AND 9)  OR
        (location = 'INVENTORY' AND slot BETWEEN 0 AND 63) OR
        (location = 'WAREHOUSE' AND slot BETWEEN 0 AND 119)
      )
    )
    """

    execute """
    CREATE UNIQUE INDEX item_loc_char_slot ON item_locations (character_id, location, slot)
      WHERE character_id IS NOT NULL
    """

    execute """
    CREATE UNIQUE INDEX item_loc_acc_slot ON item_locations (account_id, location, slot)
      WHERE account_id IS NOT NULL
    """

    execute """
    CREATE TABLE item_audit_log (
      id BIGSERIAL PRIMARY KEY,
      item_id UUID NOT NULL, action VARCHAR(20) NOT NULL,
      from_owner TEXT, to_owner TEXT, detail JSONB,
      at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """

    execute "CREATE INDEX item_audit_item_at ON item_audit_log (item_id, at)"
  end

  def down do
    execute "DROP TABLE item_audit_log"
    execute "DROP TABLE item_locations"
    execute "DROP TABLE items"
    execute "DROP TABLE characters"
    execute "DROP TABLE accounts"
  end
end

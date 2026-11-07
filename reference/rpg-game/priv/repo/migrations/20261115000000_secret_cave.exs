defmodule HacLong.Repo.Migrations.SecretCave do
  use Ecto.Migration

  # DECISIONS "Động Bí Ẩn": số đêm đã vào động của nhân vật (thành tựu Kẻ Đi Đêm) và Bia Động Bí Ẩn
  # (người tìm ra động đầu tiên mỗi đêm, người hạ Thạch Long Ẩn).
  def change do
    alter table(:characters) do
      add :secret, :map
    end

    create table(:secret_records) do
      add :user_id, :integer, null: false
      add :name, :string, null: false
      add :kind, :string, null: false
      add :night, :date, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:secret_records, [:kind, :night, :user_id])
    create index(:secret_records, [:inserted_at])
  end
end

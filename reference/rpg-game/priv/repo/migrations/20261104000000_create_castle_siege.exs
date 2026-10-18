defmodule HacLong.Repo.Migrations.CreateCastleSiege do
  use Ecto.Migration

  def change do
    # Công Thành Chiến (B-22): một dòng duy nhất (id = 1): bang đang giữ thành, các bang đăng ký trận tới
    create table(:castle_siege) do
      add :owner_guild_id, references(:guilds, on_delete: :nilify_all)
      add :owner_since, :utc_datetime
      add :registered, {:array, :integer}, null: false, default: []
      timestamps(type: :utc_datetime)
    end
  end
end

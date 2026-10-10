defmodule HacLong.Repo.Migrations.CreateTienlen do
  use Ecto.Migration

  def change do
    # Tiến Lên (Phase 17): mỗi lần trả vàng (chuỗi chặt, cuối ván) một khóa, trả lại không trả hai lần
    create table(:tienlen_settlements, primary_key: false) do
      add :key, :string, size: 120, primary_key: true
      timestamps(type: :utc_datetime, updated_at: false)
    end

    # ván đã chơi, để xem lại (V5): người chơi thật, kết quả, bài chia + các nước đánh công khai
    create table(:tienlen_games) do
      add :room_id, :string, null: false
      add :ref, :string, size: 120, null: false
      add :player_ids, {:array, :integer}, null: false, default: []
      add :players, :map, null: false
      add :replay, :map
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:tienlen_games, [:ref])
    create index(:tienlen_games, [:player_ids], using: :gin)
  end
end

defmodule HacLong.Repo.Migrations.Phase5Social do
  use Ecto.Migration

  def change do
    # PK cược vàng (H7 + H8): mỗi trận một dòng; người thắng nil = hòa
    create table(:pk_matches) do
      add :a_id, references(:users, on_delete: :delete_all), null: false
      add :b_id, references(:users, on_delete: :delete_all), null: false
      add :a_name, :string, null: false
      add :b_name, :string, null: false
      add :wager, :bigint, null: false
      add :winner_id, :integer
      add :rounds, :integer, null: false
      # ngày giờ Việt Nam (đếm số trận cược mỗi ngày)
      add :day, :date, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:pk_matches, [:a_id, :day])
    create index(:pk_matches, [:b_id, :day])

    # chiến bang trên đấu trường (H5)
    create table(:guild_wars) do
      add :a_id, references(:guilds, on_delete: :delete_all), null: false
      add :b_id, references(:guilds, on_delete: :delete_all), null: false
      add :a_points, :integer, null: false, default: 0
      add :b_points, :integer, null: false, default: 0

      # điểm từng thành viên: %{"uid" => số}; số lần thắng từng cặp (chống cày): %{"uid:uid" => số}
      add :scores, :map, null: false, default: %{}
      add :pairs, :map, null: false, default: %{}
      add :ends_at, :utc_datetime, null: false
      # nil: đang chiến; "a" | "b" | "draw"
      add :result, :string
      add :surrender_id, :integer
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:guild_wars, [:a_id])
    create index(:guild_wars, [:b_id])
    create index(:guild_wars, [:result])

    # bảng xếp hạng theo lớp (H14)
    create index(:characters, [:cls, :rebirths, :level, :xp])
  end
end

defmodule HacLong.Repo.Migrations.CreateRarePets do
  use Ecto.Migration

  # CHANGE_REASON: Bia Long Vương (DECISIONS "Long Vương"): ghi người câu được thú hiếm theo thứ tự thời gian,
  # để đánh số "Long Vương Chủ thứ #n" và hiện bảng tên ở Miếu Long Vương. Mỗi tài khoản một dòng cho mỗi thú.
  def change do
    create table(:rare_pets) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :pet, :string, null: false
      add :name, :string, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:rare_pets, [:user_id, :pet])
    create index(:rare_pets, [:pet, :inserted_at])
  end
end

defmodule HacLong.Repo.Migrations.AddStorageToCharacters do
  use Ecto.Migration

  # Tủ Đồ ở Nhà (Phase 4, C7): đồ thường đang cất `%{"inv" => %{id => số}, "extra" => số_lần_mở_rộng}`.
  # Đồ hiếm đang cất vẫn nằm trong `gear` (cờ `stored`), nên nhật ký / đối soát đồ hiếm không đổi.
  def change do
    alter table(:characters) do
      add :storage, :map, null: false, default: %{}
    end
  end
end

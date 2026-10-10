defmodule HacLong.Repo.Migrations.AddVisitedToCharacters do
  use Ecto.Migration

  # Phase 15a: bản đồ phụ đã đi tới (qua cổng ít nhất một lần) để dịch chuyển bằng bảng chọn bản đồ.
  def change do
    alter table(:characters) do
      add :visited, {:array, :string}, null: false, default: []
    end
  end
end

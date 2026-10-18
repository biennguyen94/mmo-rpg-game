defmodule HacLong.Repo.Migrations.AddLongKhi do
  use Ecto.Migration

  # CHANGE_REASON: DECISIONS "Long Vương nổi mỗi giờ" — Long Khí tích lũy khi câu cá ở Hồ Long Vương.
  def change do
    alter table(:characters) do
      add :long_khi, :integer, default: 0, null: false
    end
  end
end

defmodule HacLong.Repo.Migrations.AddBlessing do
  use Ecto.Migration

  # CHANGE_REASON: Phase 2 (DECISIONS B-26) Đài Phúc Lành thay đá dịch chuyển: phúc lành đang có và điểm hồi sinh
  def change do
    alter table(:characters) do
      add :blessing, :map
    end
  end
end

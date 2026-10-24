defmodule HacLong.Repo.Migrations.AddSkillMastery do
  use Ecto.Migration

  # Thông thạo kỹ năng (DECISIONS "Thông thạo kỹ năng"): NULL = nhân vật có trước tính năng (nạp lên cấp tối đa)
  def change do
    alter table(:characters) do
      add :skill_mastery, :map
    end
  end
end

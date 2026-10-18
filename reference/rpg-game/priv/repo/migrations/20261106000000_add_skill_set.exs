defmodule HacLong.Repo.Migrations.AddSkillSet do
  use Ecto.Migration

  # CHANGE_REASON: Phase 3 (DECISIONS B-29) bộ kỹ năng mang vào trận (tối đa 4, chọn từ kỹ năng lớp + kỹ năng tháp)
  def change do
    alter table(:characters) do
      add :skill_set, {:array, :string}
    end
  end
end

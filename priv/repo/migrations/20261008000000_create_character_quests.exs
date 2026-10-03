defmodule Mu.Repo.Migrations.CreateCharacterQuests do
  @moduledoc """
  CHANGE_REASON: Phase 6 "Quest" (`KB_00_RULES §7`, `KB_GAME_DESIGN §15`) cần lưu quest đang làm /
  đã xong và tiến độ của từng nhân vật, nhưng `KB_TECHNICAL §9` chưa có bảng nào cho việc này.
  Theo đề xuất P6-2 đã duyệt 2026-10-03 (docs/OPEN_QUESTIONS.md); chờ chủ dự án chép vào
  `KB_TECHNICAL §9` (agent không sửa `docs/kb/`).

  - Một row / (nhân vật, quest): `state` `ACTIVE` | `DONE`; `progress` JSONB (số quái đã hạ theo
    vị trí mục tiêu, vd `{"0": 7}`); mỗi quest làm một lần nên `DONE` ở lại mãi.
  - Bỏ quest = xóa row `ACTIVE`. Xóa nhân vật thì xóa theo (FK `ON DELETE CASCADE`).
  """
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE character_quests (
      character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
      quest_id VARCHAR(40) NOT NULL,
      state VARCHAR(10) NOT NULL CHECK (state IN ('ACTIVE', 'DONE')),
      progress JSONB NOT NULL DEFAULT '{}'::jsonb,
      started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      completed_at TIMESTAMPTZ,
      PRIMARY KEY (character_id, quest_id)
    )
    """
  end

  def down do
    execute "DROP TABLE character_quests"
  end
end

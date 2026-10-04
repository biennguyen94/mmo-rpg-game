defmodule Mu.Repo.Migrations.CreateAdminLog do
  @moduledoc """
  CHANGE_REASON: lệnh quản trị tặng EXP / đặt cấp (`Mu.Admin`, anh duyệt phương án A ngày
  2026-10-04, DEC-187) cần ghi lại ai được tặng, bao nhiêu, lý do — `KB_TECHNICAL §9` chưa có
  bảng nhật ký thao tác quản trị. Chờ chủ dự án chép vào `KB_TECHNICAL §9`.

  - Một row / lần thao tác: `action` (`GIVE_EXP`, `SET_LEVEL`), `detail` JSONB (số EXP, cấp trước /
    sau), `reason` do người vận hành ghi.
  - Giữ `character_name` để log còn đọc được khi nhân vật bị xóa (FK `ON DELETE SET NULL`).
  """
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE admin_log (
      id BIGSERIAL PRIMARY KEY,
      action VARCHAR(20) NOT NULL,
      character_id UUID REFERENCES characters(id) ON DELETE SET NULL,
      character_name VARCHAR(10) NOT NULL,
      detail JSONB NOT NULL DEFAULT '{}'::jsonb,
      reason TEXT NOT NULL DEFAULT '',
      at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """

    execute "CREATE INDEX admin_log_character_idx ON admin_log (character_id, at)"
  end

  def down do
    execute "DROP TABLE admin_log"
  end
end

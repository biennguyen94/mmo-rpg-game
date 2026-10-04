defmodule Mu.Repo.Migrations.AddItemOptionLevel do
  @moduledoc """
  CHANGE_REASON: Jewel of Life (Phase 5, `KB_ITEM_REFERENCE`: Life 14/16 là Phase 5) thêm "option"
  cho đồ, nhưng bảng `items` của `KB_TECHNICAL §9` chỉ có `item_level` (cường hóa +N), `luck`,
  `skill`, `excellent_options` — không có chỗ cho cấp option. Theo đề xuất P5-4 (A) đã duyệt
  2026-10-03 (docs/OPEN_QUESTIONS.md); chờ chủ dự án chép vào `KB_TECHNICAL §9` (agent không sửa
  `docs/kb/`).

  - `items.option_level`: 0 … 4 (mỗi cấp +4 đòn cho vũ khí / +4 thủ cho giáp, khiên — config
    `upgrade.life`). Mặc định 0 nên mọi đồ cũ giữ nguyên.
  """
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE items
      ADD COLUMN option_level SMALLINT NOT NULL DEFAULT 0
      CHECK (option_level BETWEEN 0 AND 4)
    """
  end

  def down do
    execute "ALTER TABLE items DROP COLUMN option_level"
  end
end

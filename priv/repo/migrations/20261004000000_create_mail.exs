defmodule Mu.Repo.Migrations.CreateMail do
  @moduledoc """
  CHANGE_REASON: `KB_GAME_DESIGN §19.10` (Hộp thư hệ thống, Phase 2) yêu cầu bổ sung bảng
  `mail` + act `mail_list` / `mail_claim` / `mail_delete` vào `KB_TECHNICAL` trước khi làm.
  Schema theo đề xuất P2-13 đã duyệt 2026-10-03 (docs/OPEN_QUESTIONS.md); chờ chủ dự án chép
  vào `KB_TECHNICAL §9` (agent không sửa `docs/kb/`).

  Mail giữ **template + số lượng**, không giữ row `items` (location `MAIL` là `LATER_VERSION`):
  item chỉ được tạo lúc nhận (transaction + `item_audit_log` `MAIL_CLAIM`), nên không sinh orphan.
  """
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE mail (
      id UUID PRIMARY KEY,
      character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
      kind VARCHAR(12) NOT NULL CHECK (kind IN ('WELCOME','SYSTEM','GIFT')),
      title VARCHAR(80) NOT NULL,
      body TEXT NOT NULL DEFAULT '',
      zen BIGINT NOT NULL DEFAULT 0 CHECK (zen >= 0),
      item_template_id VARCHAR(64),
      item_quantity INT CHECK (item_quantity >= 1),
      CHECK ((item_template_id IS NULL) = (item_quantity IS NULL)),
      read_at TIMESTAMPTZ,
      claimed_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      expires_at TIMESTAMPTZ NOT NULL
    )
    """

    execute "CREATE INDEX mail_character_created ON mail (character_id, created_at DESC)"
  end

  def down do
    execute "DROP TABLE mail"
  end
end

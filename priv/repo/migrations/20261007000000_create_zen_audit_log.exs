defmodule Mu.Repo.Migrations.CreateZenAuditLog do
  @moduledoc """
  CHANGE_REASON: Phase 5 "serial/anti-dupe audit" (`KB_00_RULES §7`) và `KB_GAME_DESIGN §17`
  ("Theo dõi tổng cung Zen") cần biết Zen sinh ra / mất đi ở đâu, nhưng `KB_TECHNICAL §9` chỉ có
  `item_audit_log` (đồ), không có bảng nào cho Zen. Theo đề xuất P5-6 đã duyệt 2026-10-03
  (docs/OPEN_QUESTIONS.md); chờ chủ dự án chép vào `KB_TECHNICAL §9` (agent không sửa `docs/kb/`).

  - Mỗi lần Zen của nhân vật đổi: một dòng (`delta`, `balance` sau khi đổi, `reason`, `ref`), ghi
    trong cùng transaction với thay đổi đó. Như `item_audit_log`: không FK (log sống lâu hơn
    nhân vật).
  - Lúc chạy migration: một dòng `BASELINE` = Zen đang có của mỗi nhân vật có Zen ≠ 0, để
    `Zen = tổng delta` đúng ngay từ đầu.
  """
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE zen_audit_log (
      id BIGSERIAL PRIMARY KEY,
      character_id UUID NOT NULL,
      delta BIGINT NOT NULL,
      balance BIGINT NOT NULL,
      reason VARCHAR(20) NOT NULL,
      ref TEXT,
      at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """

    execute "CREATE INDEX zen_audit_char_at ON zen_audit_log (character_id, at)"
    execute "CREATE INDEX zen_audit_at ON zen_audit_log (at)"

    execute """
    INSERT INTO zen_audit_log (character_id, delta, balance, reason)
    SELECT id, zen, zen, 'BASELINE' FROM characters WHERE zen <> 0
    """
  end

  def down do
    execute "DROP TABLE zen_audit_log"
  end
end

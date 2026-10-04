defmodule HacLong.Repo.Migrations.MuClassesResetCharacters do
  @moduledoc """
  Đổi sang 4 lớp nhân vật MU (Kiếm Sĩ `dk`, Phù Thủy `dw`, Tiên Nữ `elf`, Đấu Sĩ `mg`) với chỉ số
  STR / AGI / VIT / ENE và MP (anh chốt 2026-10-04: **xóa nhân vật cũ**, người chơi tạo lại).

  - Thêm cột `characters.mp`.
  - Ghi nhật ký `DELETE` (vàng về 0, đồ hiếm `out`) cho từng nhân vật để `mix hac_long.audit` vẫn khớp,
    rồi xóa toàn bộ nhân vật.
  - Xóa hàng đang rao ở chợ (đồ hiếm cũ có chỉ số `def` không còn dùng) và điểm đấu trường.
  - Giữ tài khoản, bang hội, bạn bè, thư (vàng / đồ thường trong thư vẫn nhận được khi có nhân vật mới).

  Không quay lại được dữ liệu cũ (`down` chỉ bỏ cột `mp`).
  """
  use Ecto.Migration

  def up do
    alter table(:characters), do: add(:mp, :integer, null: false, default: 0)
    flush()

    execute("""
    INSERT INTO gold_log (user_id, delta, balance, reason)
    SELECT user_id, -gold, 0, 'DELETE' FROM characters WHERE gold <> 0
    """)

    execute("""
    INSERT INTO gear_log (user_id, uid, base, rarity, action, reason)
    SELECT c.user_id, g->>'uid', g->>'base', (g->>'rarity')::int, 'out', 'DELETE'
    FROM characters c, unnest(c.gear) AS g
    """)

    execute("DELETE FROM market_listings")
    execute("DELETE FROM pvp")
    execute("DELETE FROM characters")
  end

  def down do
    alter table(:characters), do: remove(:mp)
  end
end

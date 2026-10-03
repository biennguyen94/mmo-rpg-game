# CHỈ DÙNG CHO SOAK / TEST (không phải tính năng game, không có trong release):
# đặt cấp + Zen cho mọi nhân vật có tên bắt đầu bằng `prefix` (bot soak) để bot lập guild và đánh
# guild war (P4-M5).
#
#   mix run scripts/e2e_soak_seed.exs <prefix> <level> <zen>
#
# Chạy TRƯỚC khi bot vào game (Session đang giữ nhân vật sẽ ghi đè).
import Ecto.Query
require Logger

[prefix, level, zen] = System.argv()
alias Mu.Game.{Character, Stats}
Logger.configure(level: :warning)
level = String.to_integer(level)

{n, _} =
  Mu.Repo.update_all(from(c in Character, where: like(c.name, ^"#{prefix}%")),
    set: [
      level: level,
      free_stat_points: Stats.earned_points("DK", level),
      hp_current: 999_999,
      mana_current: 999_999
    ]
  )

# Zen qua zen_audit_log (ADMIN) để `mix mu.audit` vẫn khớp sau soak (P5-M3)
for id <- Mu.Repo.all(from(c in Character, where: like(c.name, ^"#{prefix}%"), select: c.id)),
    do: {:ok, _} = Mu.Game.ZenAudit.admin_set(id, String.to_integer(zen), "e2e_soak_seed")

IO.puts("seeded #{n} bot: cấp #{level}, #{zen} Zen")

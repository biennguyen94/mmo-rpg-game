# CHỈ DÙNG CHO TEST E2E (không phải tính năng game, không có trong release):
# đặt nhân vật của tài khoản `username` lên cấp `level` (điểm tự do = (level − 1) × statPerLevel,
# chưa cộng; HP/MP đầy — MapServer cắt về max lúc vào map) để test skill cấp cao (P2-M3).
#
#   mix run scripts/e2e_level.exs <username> <level>
#
# Chạy TRƯỚC khi nhân vật vào game (Session đang giữ nhân vật sẽ ghi đè).
import Ecto.Query
require Logger

[username, level] = System.argv()
level = String.to_integer(level)
alias Mu.Repo
alias Mu.Game.{Character, Stats}

account =
  Repo.one!(
    from a in Mu.Accounts.Account,
      where: fragment("lower(?)", a.username) == ^String.downcase(username)
  )

c = Repo.one!(from c in Character, where: c.account_id == ^account.id)
Logger.configure(level: :warning)

Repo.update_all(from(x in Character, where: x.id == ^c.id),
  set: [
    level: level,
    experience: 0,
    free_stat_points: Stats.earned_points(c.class, level),
    hp_current: 999_999,
    mana_current: 999_999
  ]
)

IO.puts("seeded #{c.name} (#{c.class}): cấp #{level}")

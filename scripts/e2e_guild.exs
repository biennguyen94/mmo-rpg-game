# CHỈ DÙNG CHO TEST E2E (không phải tính năng game, không có trong release):
# đặt cấp + Zen cho nhân vật của tài khoản `username` để test tạo guild (P4-M3).
#
#   mix run scripts/e2e_guild.exs <username> <level> <zen>
#
# Chạy TRƯỚC khi nhân vật vào game (Session đang giữ nhân vật sẽ ghi đè).
import Ecto.Query
require Logger

[username, level, zen] = System.argv()
alias Mu.Repo
alias Mu.Game.Character

account =
  Repo.one!(
    from a in Mu.Accounts.Account,
      where: fragment("lower(?)", a.username) == ^String.downcase(username)
  )

Logger.configure(level: :warning)

Repo.update_all(from(x in Character, where: x.account_id == ^account.id),
  set: [level: String.to_integer(level), zen: String.to_integer(zen)]
)

IO.puts("seeded #{username}: cấp #{level}, #{zen} Zen")

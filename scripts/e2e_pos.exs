# CHỈ DÙNG CHO TEST E2E (không phải tính năng game, không có trong release):
# đặt nhân vật của tài khoản `username` ở `map` (x, y) — vd. mép thị trấn để thấy boss (P6-M5).
#
#   mix run scripts/e2e_pos.exs <username> <map> <x> <y>
#
# Chạy TRƯỚC khi nhân vật vào game (Session đang giữ nhân vật sẽ ghi đè).
import Ecto.Query
require Logger

[username, map, x, y] = System.argv()
alias Mu.Repo
alias Mu.Game.Character
Logger.configure(level: :warning)

account =
  Repo.one!(
    from a in Mu.Accounts.Account,
      where: fragment("lower(?)", a.username) == ^String.downcase(username)
  )

c = Repo.one!(from c in Character, where: c.account_id == ^account.id)

Repo.update_all(from(x in Character, where: x.id == ^c.id),
  set: [map_id: map, position_x: String.to_integer(x), position_y: String.to_integer(y)]
)

IO.puts("seeded #{c.name}: #{map} (#{x},#{y})")

# CHỈ DÙNG CHO TEST E2E (không phải tính năng game, không có trong release):
# đặt nhân vật của tài khoản `username` lên cấp `level`, HP còn `hp` (MapServer cắt về max), điểm PK
# `pk` (mốc last_pk_at = bây giờ) để test PvP / PK (P4-M1).
#
#   mix run scripts/e2e_pvp.exs <username> <level> <hp> <pk>
#
# Chạy TRƯỚC khi nhân vật vào game (Session đang giữ nhân vật sẽ ghi đè).
import Ecto.Query
require Logger

[username, level, hp, pk] = System.argv()
[level, hp, pk] = Enum.map([level, hp, pk], &String.to_integer/1)
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
    hp_current: hp,
    mana_current: 999_999,
    pk_points: pk,
    last_pk_at: if(pk > 0, do: DateTime.utc_now(), else: nil)
  ]
)

IO.puts("seeded #{c.name}: cấp #{level}, HP #{hp}, PK #{pk}")

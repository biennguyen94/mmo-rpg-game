# CHỈ DÙNG CHO TEST E2E (không phải tính năng game, không có trong release):
# nhân vật của tài khoản `username` tới Noria cạnh Chaos Goblin, cấp 25, 300 000 Zen (ADMIN),
# túi: sword_t0 +9, 2 Jewel of Chaos (ép +10), Wings of Satan +7, 5 Bless, 5 Soul, 2 Chaos (cánh 2).
#
#   mix run scripts/e2e_phase7.exs <username>
#
# Chạy TRƯỚC khi nhân vật vào game (Session đang giữ nhân vật sẽ không thấy đồ mới).
import Ecto.Query
require Logger

[username] = System.argv()
alias Mu.Repo
alias Mu.Game.{Character, Items, Stats, ZenAudit}
Logger.configure(level: :warning)

account =
  Repo.one!(
    from a in Mu.Accounts.Account,
      where: fragment("lower(?)", a.username) == ^String.downcase(username)
  )

c = Repo.one!(from c in Character, where: c.account_id == ^account.id)

Repo.update_all(from(x in Character, where: x.id == ^c.id),
  set: [
    level: 25,
    free_stat_points: Stats.earned_points(c.class, 25),
    map_id: "noria",
    position_x: 35,
    position_y: 51
  ]
)

{:ok, _} = ZenAudit.admin_set(c.id, 300_000, "e2e")

# Chaos 4 cái một stack: 1 cái ép +10, 2 cái cho cánh 2 (lấy từ cùng stack)
for {tid, q, attrs} <- [
      {"sword_t0", 1, %{item_level: 9}},
      {"jewel_chaos", 4, %{}},
      {"wing_satan", 1, %{item_level: 7}},
      {"jewel_bless", 5, %{}},
      {"jewel_soul", 5, %{}}
    ] do
  {:ok, _} =
    Items.pickup(
      c.id,
      %{serial: Mu.Ulid.generate(), template_id: tid, quantity: q, attrs: attrs},
      "e2e"
    )
end

IO.puts("seeded #{c.name}: Noria, cấp 25, 300 000 Zen, sword +9, Chaos ×4, Satan +7, Bless ×5, Soul ×5")

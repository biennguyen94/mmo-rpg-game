# CHỈ DÙNG CHO TEST E2E (không phải tính năng game, không có trong release):
# đưa nhân vật của tài khoản `username` tới Noria cạnh Chaos Goblin, cấp 20, 100 000 Zen (ADMIN),
# túi: sword_t0 +9, 2 Jewel of Chaos, 1 Wings of Satan (để test mặc cánh / vẽ cánh — P6-M3 / M4).
#
#   mix run scripts/e2e_chaos.exs <username>
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
    level: 20,
    free_stat_points: Stats.earned_points(c.class, 20),
    map_id: "noria",
    position_x: 35,
    position_y: 51
  ]
)

{:ok, _} = ZenAudit.admin_set(c.id, 100_000, "e2e")

for {tid, q, attrs} <- [
      {"sword_t0", 1, %{item_level: 9}},
      {"jewel_chaos", 2, %{}},
      {"wing_satan", 1, %{}}
    ] do
  {:ok, _} =
    Items.pickup(
      c.id,
      %{serial: Mu.Ulid.generate(), template_id: tid, quantity: q, attrs: attrs},
      "e2e"
    )
end

IO.puts("seeded #{c.name}: Noria (35,51), cấp 20, 100 000 Zen, sword_t0 +9, Chaos ×2, Wings of Satan")

# CHỈ DÙNG CHO TEST E2E (không phải tính năng game, không có trong release):
# cho nhân vật của tài khoản `username` đồ + jewel trong túi để test ép đồ (P5-M2):
# sword_t0 +0, helm_t0 +6, 5 Bless, 3 Soul, 8 Life.
#
#   mix run scripts/e2e_upgrade.exs <username>
#
# Chạy TRƯỚC khi nhân vật vào game (Session đang giữ nhân vật sẽ không thấy đồ mới).
import Ecto.Query
require Logger

[username] = System.argv()
alias Mu.Repo
alias Mu.Game.{Character, Items}
Logger.configure(level: :warning)

account =
  Repo.one!(
    from a in Mu.Accounts.Account,
      where: fragment("lower(?)", a.username) == ^String.downcase(username)
  )

c = Repo.one!(from c in Character, where: c.account_id == ^account.id)

for {tid, q, attrs} <- [
      {"sword_t0", 1, %{}},
      {"helm_t0", 1, %{item_level: 6}},
      {"jewel_bless", 5, %{}},
      {"jewel_soul", 3, %{}},
      {"jewel_life", 8, %{}}
    ] do
  {:ok, _} =
    Items.pickup(
      c.id,
      %{serial: Mu.Ulid.generate(), template_id: tid, quantity: q, attrs: attrs},
      "e2e"
    )
end

IO.puts("seeded #{c.name}: sword_t0, helm_t0 +6, Bless ×5, Soul ×3, Life ×8")

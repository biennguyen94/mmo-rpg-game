# CHỈ DÙNG CHO TEST E2E (không phải tính năng game, không có trong release):
# cho nhân vật của tài khoản `username` cấp 3 + 10 điểm, Zen, HP thấp và vài món đồ để test UI mặc/
# dùng potion/bán. Mọi item tạo qua Mu.Game.Items (có audit, from_owner "seed:e2e").
#
#   mix run scripts/e2e_seed.exs <username>
#
# Chạy TRƯỚC khi nhân vật vào game (Session đang giữ nhân vật sẽ ghi đè Zen/HP).
import Ecto.Query
require Logger

[username] = System.argv()
alias Mu.{Repo, Ulid}
alias Mu.Game.{Character, Items}

account = Repo.one!(from a in Mu.Accounts.Account, where: fragment("lower(?)", a.username) == ^String.downcase(username))
c = Repo.one!(from c in Character, where: c.account_id == ^account.id)

# cấp 3 với đủ 10 điểm tự do (= (3 − 1) × 5, chưa cộng): hợp lệ theo KB_GAME_DESIGN §1;
# EXP 515/520: hạ 1 Spider là lên cấp 4 (test lên cấp qua UI)
Logger.configure(level: :warning)
Repo.update_all(from(x in Character, where: x.id == ^c.id),
  set: [hp_current: 100, level: 3, experience: 515, free_stat_points: 10]
)

# Zen qua zen_audit_log (ADMIN) để `mix mu.audit` vẫn khớp (P5-M3)
{:ok, _} = Mu.Game.ZenAudit.admin_set(c.id, 1000, "e2e_seed")

for tid <- ~w(sword_t0 armor_t0 ring_hp_t0 hp_potion_small hp_potion_small) do
  {:ok, _} = Items.pickup(c.id, %{serial: Ulid.generate(), template_id: tid}, "seed:e2e")
end

IO.puts("seeded #{c.name}: cấp 3 (EXP 515/520, 10 điểm), zen 1000, hp 100, sword/armor/ring + 2 HP potion")

defmodule HacLong.Repo.Migrations.CreateGoldGearAdminLogs do
  @moduledoc """
  Đợt 2 (FEATURE_CATALOG E1, K1, K2):

  - `gold_log`: mỗi lần vàng của nhân vật đổi (ghi cùng transaction với lần lưu nhân vật).
    Tổng `delta` của một tài khoản luôn bằng vàng hiện có; dòng `BASELINE` lấy số vàng lúc chạy
    migration này làm điểm xuất phát.
  - `gear_log`: đồ chỉ số ngẫu nhiên (`uid` bắt đầu bằng `#`) vào (`in`) / ra (`out`) nhân vật.
  - `admin_log`: mọi thao tác quản trị có thay đổi dữ liệu.
  - `users.role`: `player` / `mod` / `admin` thay cho cột `admin` (true → `admin`).

  Không đặt khóa ngoại cho các bảng log: xóa nhân vật/tài khoản vẫn giữ lịch sử.
  """
  use Ecto.Migration

  def up do
    create table(:gold_log) do
      add :user_id, :bigint, null: false
      add :delta, :bigint, null: false
      add :balance, :bigint, null: false
      add :reason, :string, size: 32, null: false
      add :ref, :string, size: 64
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:gold_log, [:user_id, :id])
    create index(:gold_log, [:inserted_at])

    create table(:gear_log) do
      add :user_id, :bigint, null: false
      add :uid, :string, size: 32, null: false
      add :base, :string, size: 64
      add :rarity, :integer
      add :action, :string, size: 3, null: false
      add :reason, :string, size: 32, null: false
      add :ref, :string, size: 64
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:gear_log, [:uid, :id])
    create index(:gear_log, [:user_id, :id])
    create index(:gear_log, [:inserted_at])
    create constraint(:gear_log, :gear_log_action, check: "action IN ('in', 'out')")

    create table(:admin_log) do
      add :admin_id, :bigint, null: false
      add :admin_name, :string, null: false
      add :op, :string, size: 32, null: false
      add :target_id, :bigint
      add :params, :map, null: false, default: %{}
      add :result, :string, size: 200
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:admin_log, [:inserted_at])
    create index(:admin_log, [:target_id, :id])

    alter table(:users), do: add(:role, :string, size: 8, null: false, default: "player")
    create constraint(:users, :users_role, check: "role IN ('player', 'mod', 'admin')")

    flush()

    execute("UPDATE users SET role = 'admin' WHERE admin")

    execute("""
    INSERT INTO gold_log (user_id, delta, balance, reason)
    SELECT user_id, gold, gold, 'BASELINE' FROM characters
    """)

    execute("""
    INSERT INTO gear_log (user_id, uid, base, rarity, action, reason)
    SELECT c.user_id, g->>'uid', g->>'base', (g->>'rarity')::int, 'in', 'BASELINE'
    FROM characters c, unnest(c.gear) AS g
    """)

    alter table(:users), do: remove(:admin)
  end

  def down do
    alter table(:users), do: add(:admin, :boolean, null: false, default: false)
    flush()
    execute("UPDATE users SET admin = (role = 'admin')")
    drop constraint(:users, :users_role)
    alter table(:users), do: remove(:role)
    drop table(:admin_log)
    drop table(:gear_log)
    drop table(:gold_log)
  end
end

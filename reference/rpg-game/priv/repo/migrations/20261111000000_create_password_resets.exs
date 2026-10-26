defmodule HacLong.Repo.Migrations.CreatePasswordResets do
  use Ecto.Migration

  # CHANGE_REASON: DECISIONS "Quên mật khẩu": tài khoản không có email, người chơi gửi yêu cầu,
  # quản trị đặt lại mật khẩu tạm rồi báo qua kênh liên lạc người chơi để lại.
  def change do
    create table(:password_resets) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :contact, :string, null: false
      add :resolved_at, :utc_datetime
      add :resolved_by, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:password_resets, [:user_id])
    create index(:password_resets, [:resolved_at])
  end
end

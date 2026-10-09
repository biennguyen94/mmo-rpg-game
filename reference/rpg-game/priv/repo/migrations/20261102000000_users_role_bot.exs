defmodule HacLong.Repo.Migrations.UsersRoleBot do
  use Ecto.Migration

  # Phase 16: tài khoản người chơi AI có `role = "bot"`.
  def up do
    drop constraint(:users, :users_role)
    create constraint(:users, :users_role, check: "role IN ('player', 'mod', 'admin', 'bot')")
  end

  def down do
    execute "UPDATE users SET role = 'player' WHERE role = 'bot'"
    drop constraint(:users, :users_role)
    create constraint(:users, :users_role, check: "role IN ('player', 'mod', 'admin')")
  end
end

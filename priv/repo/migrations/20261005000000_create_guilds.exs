defmodule Mu.Repo.Migrations.CreateGuilds do
  @moduledoc """
  CHANGE_REASON: `KB_GAME_DESIGN §14` (Guild, Phase 4) cần lưu guild và thành viên lâu dài, nhưng
  `KB_TECHNICAL §9` chưa có bảng nào cho guild. Schema theo đề xuất P4-5 đã duyệt 2026-10-03
  (docs/OPEN_QUESTIONS.md); chờ chủ dự án chép vào `KB_TECHNICAL §9` (agent không sửa `docs/kb/`).

  - `guilds`: tên 3–8 ký tự ASCII chữ / số, unique không phân biệt hoa thường; `master_id` là
    nhân vật master.
  - `guild_members`: `character_id` là khóa chính ⇒ mỗi nhân vật tối đa một guild; vai trò
    `master` / `assistant` / `member`; mỗi guild đúng một master (index partial).
  - Nhân vật bị xóa (chưa có ở Phase 3–4) thì dòng thành viên / guild của master đi theo (CASCADE).
  """
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE guilds (
      id UUID PRIMARY KEY,
      name VARCHAR(8) NOT NULL CHECK (name ~ '^[A-Za-z0-9]{3,8}$'),
      master_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """

    execute "CREATE UNIQUE INDEX guilds_name_ci ON guilds (lower(name))"

    execute """
    CREATE TABLE guild_members (
      character_id UUID PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
      guild_id UUID NOT NULL REFERENCES guilds(id) ON DELETE CASCADE,
      role VARCHAR(9) NOT NULL CHECK (role IN ('master','assistant','member')),
      joined_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """

    execute "CREATE INDEX guild_members_guild ON guild_members (guild_id)"

    execute "CREATE UNIQUE INDEX guild_one_master ON guild_members (guild_id) WHERE role = 'master'"
  end

  def down do
    execute "DROP TABLE guild_members"
    execute "DROP TABLE guilds"
  end
end

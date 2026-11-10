defmodule HacLong.Repo.Migrations.SkyKite do
  use Ecto.Migration

  # CHANGE_REASON: DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long" — Phong Khí (thả diều), Bọc Trăm Trứng đang ấp, lần
  # hưởng lộc Long Phượng Hội gần nhất của nhân vật (`HacLong.Game.Kite.load/1`).
  def change do
    alter table(:characters) do
      add :sky, :map
    end
  end
end

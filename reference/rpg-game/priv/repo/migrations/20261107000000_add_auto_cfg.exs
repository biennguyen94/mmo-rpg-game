defmodule HacLong.Repo.Migrations.AddAutoCfg do
  use Ecto.Migration

  # CHANGE_REASON: tự đánh kiểu MU Helper (DECISIONS "Tự đánh: phạm vi, kỹ năng, lọc đồ, lưu cài đặt") — cài đặt tự đánh
  # lưu theo nhân vật (đổi máy / trình duyệt vẫn giữ)
  def change do
    alter table(:characters) do
      add :auto_cfg, :map
    end
  end
end

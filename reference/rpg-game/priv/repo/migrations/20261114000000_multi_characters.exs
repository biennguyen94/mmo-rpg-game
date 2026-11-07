defmodule HacLong.Repo.Migrations.MultiCharacters do
  use Ecto.Migration

  # CHANGE_REASON: DECISIONS "Nhiều nhân vật": mỗi tài khoản tối đa 5 nhân vật. Mỗi nhân vật là một dòng `users`
  # riêng (mã người chơi, mọi bảng bạn bè / bang / thư / chợ / đồ sát vẫn gắn theo đó); nhân vật thêm có
  # `account_id` = tài khoản đăng nhập (dòng của tài khoản cũ vừa là tài khoản vừa là nhân vật đầu). Thùng đồ chung
  # của tài khoản ở `account_storage` (đồ thường, đồ hiếm kèm cấp ép, vàng, số lần mở rộng).
  def change do
    alter table(:users) do
      add :account_id, references(:users, on_delete: :delete_all)
    end

    create index(:users, [:account_id])

    create table(:account_storage, primary_key: false) do
      add :account_id, references(:users, on_delete: :delete_all), primary_key: true
      add :inv, :map, null: false, default: %{}
      add :gear, {:array, :map}, null: false, default: []
      add :gold, :bigint, null: false, default: 0
      add :extra, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end
  end
end

defmodule HacLong.Repo.Migrations.AddDrink do
  use Ecto.Migration

  # CHANGE_REASON: đồ uống của Bà Lang (Bia Thảo Dược, Rượu Thuốc…) nằm ô riêng, cộng dồn với món ăn
  # (`food`): đồ uống đang có và số trận còn tác dụng (DECISIONS "Bà Lang: đồ uống thay pha bình máu")
  def change do
    alter table(:characters) do
      add :drink, :map
    end
  end
end

defmodule HacLong.Repo.Migrations.GoldBigintNonNegative do
  @moduledoc """
  Vàng không âm, không tràn số (FEATURE_CATALOG E14).

  - `characters.gold`, `mails.gold`: `integer` → `bigint` (tránh tràn khi vàng lớn dần).
  - Thêm CHECK `>= 0`: code lỗi làm vàng âm thì DB từ chối ghi (lưu nhân vật ném lỗi, không âm thầm
    lưu số sai).
  """
  use Ecto.Migration

  def up do
    alter table(:characters), do: modify(:gold, :bigint, null: false)
    alter table(:mails), do: modify(:gold, :bigint, null: false, default: 0)
    create constraint(:characters, :gold_non_negative, check: "gold >= 0")
    create constraint(:mails, :mail_gold_non_negative, check: "gold >= 0")
  end

  def down do
    drop constraint(:mails, :mail_gold_non_negative)
    drop constraint(:characters, :gold_non_negative)
    alter table(:mails), do: modify(:gold, :integer, null: false, default: 0)
    alter table(:characters), do: modify(:gold, :integer, null: false)
  end
end

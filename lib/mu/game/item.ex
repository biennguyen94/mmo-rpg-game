defmodule Mu.Game.Item do
  @moduledoc "Bảng `items` (`KB_TECHNICAL §9`): một row = một stack, `serial` ULID do server sinh."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "items" do
    field :serial, :string
    field :template_id, :string
    field :quantity, :integer, default: 1
    field :item_level, :integer, default: 0
    field :durability, :integer
    field :luck, :boolean, default: false
    field :skill, :boolean, default: false
    field :excellent_options, {:array, :map}, default: []
    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime_usec)
  end
end

defmodule Mu.Game.ItemLocation do
  @moduledoc "Bảng `item_locations`: `item_id` là khóa chính ⇒ mỗi item đúng một chỗ (chặn dupe)."
  use Ecto.Schema

  @primary_key {:item_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "item_locations" do
    field :location, :string
    field :character_id, :binary_id
    field :account_id, :binary_id
    field :slot, :integer
  end
end

defmodule Mu.Game.ItemAudit do
  @moduledoc "Bảng `item_audit_log`: mọi lần tạo/chuyển/xóa item (không FK, sống lâu hơn item)."
  use Ecto.Schema

  schema "item_audit_log" do
    field :item_id, :binary_id
    field :action, :string
    field :from_owner, :string
    field :to_owner, :string
    field :detail, :map
    field :at, :utc_datetime_usec, read_after_writes: true
  end
end

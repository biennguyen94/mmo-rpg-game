defmodule Mu.Game.Character do
  @moduledoc """
  Bảng `characters` (`KB_TECHNICAL §9`): cột rời, không lưu blob; `version` dùng cho
  optimistic lock khi cập nhật.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "characters" do
    belongs_to :account, Mu.Accounts.Account
    field :name, :string
    field :class, :string
    field :level, :integer, default: 1
    field :experience, :integer, default: 0
    field :strength, :integer
    field :agility, :integer
    field :vitality, :integer
    field :energy, :integer
    field :free_stat_points, :integer, default: 0
    field :hp_current, :integer
    field :mana_current, :integer
    field :zen, :integer, default: 0
    field :map_id, :string
    field :position_x, :integer
    field :position_y, :integer
    field :pk_points, :integer, default: 0
    field :last_pk_at, :utc_datetime_usec
    field :version, :integer, default: 0
    timestamps(inserted_at: :created_at, type: :utc_datetime_usec)
  end

  @doc "Changeset tạo mới: mọi giá trị do server tính (`Mu.Game.Characters.create/2`)."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> change(attrs)
    |> unique_constraint(:name, name: :characters_name_ci)
    |> check_constraint(:name, name: :characters_name_check)
  end
end

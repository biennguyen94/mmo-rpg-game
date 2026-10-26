defmodule HacLong.RarePets do
  @moduledoc """
  Bia Long Vương (DECISIONS "Long Vương"): người câu được thú hiếm (`PETS.rare`), theo thứ tự thời gian.

  - `record!/3`: Session ghi khi `HacLong.Game.Fishing` trả `rare_pet`; trả về số thứ tự n (người thứ n có con này).
    Ghi lại lần nữa (cùng tài khoản, cùng thú) không thêm dòng, trả lại số cũ.
  - `list/1`: bảng tên cho Miếu Long Vương, sớm trước.
  """
  use Ecto.Schema
  import Ecto.Query

  alias HacLong.Repo

  schema "rare_pets" do
    field :user_id, :integer
    field :pet, :string
    field :name, :string
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def record!(user_id, name, pet) do
    Repo.insert!(%__MODULE__{user_id: user_id, name: name, pet: pet},
      on_conflict: :nothing,
      conflict_target: [:user_id, :pet]
    )

    rows = list(pet)
    Enum.find_value(rows, length(rows), &(&1.user_id == user_id && &1.n))
  end

  @doc "`[%{n, user_id, name, at}]` của thú `pet`, người câu được sớm nhất trước."
  def list(pet) do
    from(r in __MODULE__, where: r.pet == ^pet, order_by: [asc: r.inserted_at, asc: r.id])
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {r, n} -> %{n: n, user_id: r.user_id, name: r.name, at: r.inserted_at} end)
  end
end

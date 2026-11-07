defmodule HacLong.World.SecretRecords do
  @moduledoc """
  Bia Động Bí Ẩn (DECISIONS "Động Bí Ẩn"): người tìm ra động đầu tiên mỗi đêm (`kind` "found") và người hạ Thạch Long Ẩn
  ("boss"). Mỗi người mỗi loại mỗi đêm một dòng.
  """
  use Ecto.Schema
  import Ecto.Query

  alias HacLong.Repo

  schema "secret_records" do
    field :user_id, :integer
    field :name, :string
    field :kind, :string
    field :night, :date
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def record(user_id, name, kind, night) do
    Repo.insert!(%__MODULE__{user_id: user_id, name: name, kind: kind, night: night},
      on_conflict: :nothing,
      conflict_target: [:kind, :night, :user_id]
    )

    :ok
  rescue
    _ -> :error
  end

  @doc "`n` dòng gần nhất: `[%{name, kind, night}]`, mới trước."
  def recent(n \\ 20) do
    from(r in __MODULE__, order_by: [desc: r.inserted_at, desc: r.id], limit: ^n)
    |> Repo.all()
    |> Enum.map(&%{name: &1.name, kind: &1.kind, night: Date.to_iso8601(&1.night)})
  end
end

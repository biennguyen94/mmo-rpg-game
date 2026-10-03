defmodule Mu.Game.CharacterQuest do
  @moduledoc "Bảng `character_quests` (P6-M2, migration 20261008000000): quest của nhân vật."
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id
  schema "character_quests" do
    field :character_id, :binary_id, primary_key: true
    field :quest_id, :string, primary_key: true
    field :state, :string
    field :progress, :map, default: %{}
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
  end
end

defmodule Mu.Game.QuestStore do
  @moduledoc """
  Đọc / ghi `character_quests` (P6-M2). Session là nơi duy nhất gọi (như `Characters.save`);
  trả quest (đồ + Zen + `DONE`) đi qua `Mu.Game.Items.quest_turnin/4` trong một transaction.
  """
  import Ecto.Query

  alias Mu.Repo
  alias Mu.Game.CharacterQuest

  @doc "`%{quest_id => %{state, progress}}` của nhân vật."
  def load(cid) do
    Repo.all(from q in CharacterQuest, where: q.character_id == ^cid)
    |> Map.new(&{&1.quest_id, %{state: &1.state, progress: &1.progress}})
  end

  @doc "Nhận quest: thêm row `ACTIVE` (đã có row → `FORBIDDEN`)."
  def accept(cid, qid) do
    %CharacterQuest{
      character_id: cid,
      quest_id: qid,
      state: "ACTIVE",
      progress: %{},
      started_at: DateTime.utc_now()
    }
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint([:character_id, :quest_id], name: :character_quests_pkey)
    |> Repo.insert()
    |> case do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "FORBIDDEN"}
    end
  end

  @doc "Ghi tiến độ kill (chỉ khi quest còn `ACTIVE`)."
  def save_progress(cid, qid, progress) do
    Repo.update_all(
      from(q in CharacterQuest,
        where: q.character_id == ^cid and q.quest_id == ^qid and q.state == "ACTIVE"
      ),
      set: [progress: progress]
    )

    :ok
  end

  @doc "Bỏ quest đang làm (xóa row `ACTIVE`; không có → `INVALID_TARGET`)."
  def abandon(cid, qid) do
    case Repo.delete_all(
           from(q in CharacterQuest,
             where: q.character_id == ^cid and q.quest_id == ^qid and q.state == "ACTIVE"
           )
         ) do
      {1, _} -> :ok
      _ -> {:error, "INVALID_TARGET"}
    end
  end
end

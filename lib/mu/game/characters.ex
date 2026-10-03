defmodule Mu.Game.Characters do
  @moduledoc """
  Tạo và đọc nhân vật. Phase 1: chỉ DK, `account.maxCharacters` nhân vật/tài khoản
  (= 1, enforce ở app: Q13). Viết lại so với repo nền (nhân vật ở đó là blob JSON).
  """

  import Ecto.Query

  alias Mu.Repo
  alias Mu.Accounts.Account
  alias Mu.Game.{Character, Config, Data, Names, Stats}
  alias Mu.World.Maps

  def list(account_id) do
    Repo.all(from c in Character, where: c.account_id == ^account_id, order_by: c.created_at)
  end

  @doc "Nhân vật `id` nếu thuộc tài khoản `account_id`, ngược lại `nil`."
  def get_owned(account_id, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.get_by(Character, id: id, account_id: account_id)
    else
      _ -> nil
    end
  end

  @doc """
  Tạo nhân vật mới. `attrs`: `%{"name" => ..., "class" => ...}` (class bỏ trống = class mặc
  định trong config). Mọi chỉ số do server tính từ `classes.json` + `config.json`.

  Lỗi: `:invalid_name`, `:banned_name`, `:name_taken`, `:invalid_class`, `:character_limit`.
  """
  def create(%Account{id: account_id}, attrs) do
    start = Config.get(["newCharacter"])
    class_id = attrs["class"] || start["class"]

    with {:ok, name} <- Names.validate(attrs["name"]),
         %{} = class <- Data.class(class_id) || {:error, :invalid_class} do
      Repo.transaction(fn ->
        # khóa row tài khoản: hai request tạo nhân vật song song không cùng lọt qua giới hạn
        Repo.one!(from a in Account, where: a.id == ^account_id, lock: "FOR UPDATE")

        if count(account_id) >= Config.get(["account", "maxCharacters"]) do
          Repo.rollback(:character_limit)
        end

        insert(account_id, name, class, start)
      end)
    end
  end

  defp insert(account_id, name, class, start) do
    {x, y} = Maps.get(start["mapId"]).player_spawn

    %{
      account_id: account_id,
      name: name,
      class: class["id"],
      level: 1,
      experience: 0,
      strength: class["strength"],
      agility: class["agility"],
      vitality: class["vitality"],
      energy: class["energy"],
      free_stat_points: Stats.earned_points(class["id"], 1),
      hp_current: Stats.hp_max(class["id"], 1, class["vitality"]),
      mana_current: Stats.mp_max(class["id"], 1, class["energy"]),
      zen: start["zen"],
      map_id: start["mapId"],
      position_x: x,
      position_y: y
    }
    |> Character.create_changeset()
    |> Repo.insert()
    |> case do
      {:ok, c} -> c
      {:error, cs} -> Repo.rollback(if name_taken?(cs), do: :name_taken, else: cs)
    end
  end

  defp name_taken?(cs) do
    Enum.any?(cs.errors, fn {field, {_, opts}} ->
      field == :name and opts[:constraint] == :unique
    end)
  end

  defp count(account_id) do
    Repo.aggregate(from(c in Character, where: c.account_id == ^account_id), :count)
  end

  @doc """
  Lưu vị trí (optimistic lock theo `version`: Session là nơi ghi duy nhất, lệch version là lỗi).
  Không đổi gì thì không ghi.
  """
  def save_position(%Character{position_x: x, position_y: y} = c, x, y), do: {:ok, c}

  def save_position(%Character{} = c, x, y) do
    c
    |> Ecto.Changeset.change(position_x: x, position_y: y)
    |> Ecto.Changeset.optimistic_lock(:version)
    |> Repo.update()
  end

  @doc "Tóm tắt cho danh sách nhân vật (HTTP)."
  def summary(%Character{} = c) do
    %{id: c.id, name: c.name, class: c.class, level: c.level, mapId: c.map_id}
  end

  @doc """
  Trạng thái đầy đủ gửi client (event `player`, `KB_TECHNICAL §5`) kèm `view` tính sẵn.
  M1: `view` có HP/MP tối đa; chỉ số chiến đấu thêm ở M3.
  """
  def player_view(%Character{} = c) do
    %{
      id: c.id,
      name: c.name,
      class: c.class,
      level: c.level,
      experience: c.experience,
      strength: c.strength,
      agility: c.agility,
      vitality: c.vitality,
      energy: c.energy,
      freeStatPoints: c.free_stat_points,
      hp: c.hp_current,
      mp: c.mana_current,
      zen: c.zen,
      mapId: c.map_id,
      x: c.position_x,
      y: c.position_y,
      view: %{
        hpMax: Stats.hp_max(c.class, c.level, c.vitality),
        mpMax: Stats.mp_max(c.class, c.level, c.energy)
      }
    }
  end
end

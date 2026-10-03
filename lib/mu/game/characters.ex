defmodule Mu.Game.Characters do
  @moduledoc """
  Tạo và đọc nhân vật. Phase 1: chỉ DK, `account.maxCharacters` nhân vật/tài khoản
  (= 1, enforce ở app: Q13). Viết lại so với repo nền (nhân vật ở đó là blob JSON).
  """

  import Ecto.Query

  alias Mu.Repo
  alias Mu.Accounts.Account
  alias Mu.Game.{Character, Config, Data, Engine, Inventory, Items, Names, Stats}
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
  Tạo nhân vật mới. `attrs`: `%{"name" => ..., "class" => ...}` (class thuộc
  `newCharacter.classes`, bỏ trống = `defaultClass`). Mọi chỉ số do server tính từ
  `classes.json` + `config.json`; đồ `newCharacter.startingEquipment[class]` mặc sẵn (P2-3).

  Lỗi: `:invalid_name`, `:banned_name`, `:name_taken`, `:invalid_class`, `:character_limit`.
  """
  def create(%Account{id: account_id}, attrs) do
    start = Config.get(["newCharacter"])
    class_id = attrs["class"] || start["defaultClass"]

    with {:ok, name} <- Names.validate(attrs["name"]),
         true <- class_id in start["classes"] || {:error, :invalid_class},
         %{} = class <- Data.class(class_id) || {:error, :invalid_class} do
      Repo.transaction(fn ->
        # khóa row tài khoản: hai request tạo nhân vật song song không cùng lọt qua giới hạn
        Repo.one!(from a in Account, where: a.id == ^account_id, lock: "FOR UPDATE")

        if count(account_id) >= Config.get(["account", "maxCharacters"]) do
          Repo.rollback(:character_limit)
        end

        c = insert(account_id, name, class, start)
        Items.give_starting_equipment(c.id, Map.get(start["startingEquipment"], c.class, []))
        c
      end)
    end
  end

  @doc "Class tạo được (`newCharacter.classes`) cho màn tạo nhân vật; mục đầu là `defaultClass`."
  def creatable_classes do
    start = Config.get(["newCharacter"])

    start["classes"]
    |> Enum.sort_by(&(&1 != start["defaultClass"]))
    |> Enum.map(&%{id: &1, name: Data.class(&1)["name"]})
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

  @progress_fields ~w(level experience strength agility vitality energy free_stat_points
                      hp_current mana_current zen position_x position_y)a

  @doc """
  Lưu trạng thái đang giữ trong bộ nhớ (`current`) so với bản đã lưu (`saved`): chỉ ghi các
  cột đổi, optimistic lock theo `version` (Session là nơi ghi duy nhất; lệch version là lỗi
  và raise `Ecto.StaleEntryError`). Không đổi gì thì không ghi. Trả `{:ok, bản_đã_lưu}`.
  """
  def save(%Character{} = saved, %Character{} = current) do
    changes =
      for f <- @progress_fields,
          Map.fetch!(saved, f) != Map.fetch!(current, f),
          into: %{},
          do: {f, Map.fetch!(current, f)}

    if changes == %{} do
      {:ok, saved}
    else
      saved
      |> Ecto.Changeset.change(changes)
      |> Ecto.Changeset.optimistic_lock(:version)
      |> Repo.update()
    end
  end

  @doc "Lưu vị trí (dạng rút gọn của `save/2`)."
  def save_position(%Character{} = c, x, y),
    do: save(c, %{c | position_x: x, position_y: y})

  @doc "Tóm tắt cho danh sách nhân vật (HTTP)."
  def summary(%Character{} = c) do
    %{id: c.id, name: c.name, class: c.class, level: c.level, mapId: c.map_id}
  end

  @doc """
  Trạng thái đầy đủ gửi client (event `player`, `KB_TECHNICAL §5`) kèm `view` tính sẵn
  (`Engine.derived/2`): client chỉ hiển thị, không tính công thức.
  """
  def player_view(%Character{} = c, items \\ [], buffs \\ []) do
    d = Engine.derived(c, Inventory.equipped_templates(items))

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
        hpMax: d.hp_max,
        mpMax: d.mp_max,
        attackMin: d.attack_min,
        attackMax: d.attack_max,
        defense: d.defense,
        attackRate: d.attack_rate,
        defenseRate: d.defense_rate,
        attackSpeed: d.attack_speed,
        cooldownMs: d.cooldown_ms,
        attackRange: d.attack_range,
        expRequired:
          if(c.level >= Engine.max_level(), do: nil, else: Engine.exp_required(c.level)),
        maxLevel: Engine.max_level(),
        skills: Enum.sort(Engine.skills(c)),
        potions: Inventory.potion_counts(items),
        inventoryUsed: length(Inventory.inventory(items)),
        inventorySize: Inventory.inventory_slots(),
        # [{id, stat, value, expiresAt}] — MapServer giữ, Session chuyển tiếp (P2-M3)
        buffs: buffs
      },
      inventory: Enum.map(Inventory.inventory(items), &item_view/1),
      equipment: Enum.map(Inventory.equipment(items), &item_view/1)
    }
  end

  @doc "Một item gửi client: client tra template (tên, chỉ số, icon) theo `templateId`."
  def item_view(it) do
    %{
      id: it.id,
      serial: it.serial,
      templateId: it.template_id,
      quantity: it.quantity,
      slot: it.slot,
      level: it.item_level,
      durability: it.durability,
      luck: it.luck,
      skill: it.skill,
      excellentOptions: it.excellent_options
    }
  end
end

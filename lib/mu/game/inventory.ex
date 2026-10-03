defmodule Mu.Game.Inventory do
  @moduledoc """
  Luật túi đồ và trang bị, **hàm thuần** (DB ở `Mu.Game.Items`). Item là map có `id`,
  `template_id`, `quantity`, `location` (`"INVENTORY"` | `"EQUIPMENT"`), `slot`.

  - Túi 64 ô (`KB_CONFIG §6`, CHECK của DB). Slot trang bị theo §6:
    0 HELM, 1 ARMOR, 2 PANTS, 3 GLOVES, 4 BOOTS, 5 WEAPON, 6 SHIELD, 7 WING, 8 RING1, 9 RING2.
  - Thêm đồ xếp chồng (G20): gộp vào stack cùng template có slot thấp nhất còn chỗ
    (`maxStack`), thừa thì tạo stack mới ở ô trống thấp nhất.
  - Equip (`KB_GAME_DESIGN §8`): đúng slot (nhẫn vào 8 hoặc 9; WING khóa khi
    `features.wings = false`), đúng class, đủ level/stat (`requirements` đã scale lúc import).
  """

  alias Mu.Game.{Config, Data}

  @inventory_slots 64
  @equip_slots %{
    "HELM" => [0],
    "ARMOR" => [1],
    "PANTS" => [2],
    "GLOVES" => [3],
    "BOOTS" => [4],
    "WEAPON" => [5],
    "SHIELD" => [6],
    "WING" => [7],
    "RING1" => [8, 9],
    "RING2" => [8, 9]
  }
  @stats ~w(strength agility energy vitality)

  def inventory_slots, do: @inventory_slots

  def inventory(items),
    do: items |> Enum.filter(&(&1.location == "INVENTORY")) |> Enum.sort_by(& &1.slot)

  def equipment(items),
    do: items |> Enum.filter(&(&1.location == "EQUIPMENT")) |> Enum.sort_by(& &1.slot)

  def in_slot(items, location, slot),
    do: Enum.find(items, &(&1.location == location and &1.slot == slot))

  @doc "Ô túi trống thấp nhất (`nil` nếu đầy)."
  def first_free_slot(items) do
    used = MapSet.new(inventory(items), & &1.slot)
    Enum.find(0..(@inventory_slots - 1), &(not MapSet.member?(used, &1)))
  end

  @doc """
  Kế hoạch thêm `quantity` cái `template_id` vào túi:
  `{:ok, [{:merge, item_id, thêm} | {:new, slot, số_lượng}]}` hoặc `{:error, "INVENTORY_FULL"}`.
  """
  def plan_add(items, template_id, quantity) when quantity >= 1 do
    t = Data.item(template_id)

    {merges, left} =
      if t["stackable"] do
        inventory(items)
        |> Enum.filter(&(&1.template_id == template_id and &1.quantity < t["maxStack"]))
        |> Enum.reduce({[], quantity}, fn
          _, {acc, 0} ->
            {acc, 0}

          it, {acc, left} ->
            add = min(left, t["maxStack"] - it.quantity)
            {[{:merge, it.id, add} | acc], left - add}
        end)
      else
        {[], quantity}
      end

    per = if t["stackable"], do: t["maxStack"], else: 1
    used = MapSet.new(inventory(items), & &1.slot)
    free = Enum.reject(0..(@inventory_slots - 1), &MapSet.member?(used, &1))
    chunks = chunk(left, per)

    if length(chunks) > length(free),
      do: {:error, "INVENTORY_FULL"},
      else: {:ok, Enum.reverse(merges) ++ Enum.zip_with(free, chunks, &{:new, &1, &2})}
  end

  defp chunk(0, _), do: []
  defp chunk(n, per), do: [min(n, per) | chunk(n - min(n, per), per)]

  @doc "Slot trang bị hợp lệ cho template (danh sách số; rỗng = không mặc được)."
  def equip_slots(template) do
    slots = Map.get(@equip_slots, template["slot"], [])
    if 7 in slots and not Config.get(["features", "wings"]), do: [], else: slots
  end

  @doc """
  Nhân vật `c` mặc `template` vào `slot` được không: `:ok` hoặc
  `{:error, "INVALID_SLOT" | "REQUIREMENT_NOT_MET"}`.
  """
  def can_equip(c, template, slot) do
    req = template["requirements"] || %{}

    cond do
      slot not in equip_slots(template) ->
        {:error, "INVALID_SLOT"}

      c.class not in (template["classes"] || []) ->
        {:error, "REQUIREMENT_NOT_MET"}

      c.level < (req["level"] || 0) ->
        {:error, "REQUIREMENT_NOT_MET"}

      Enum.any?(@stats, &(Map.fetch!(c, String.to_existing_atom(&1)) < (req[&1] || 0))) ->
        {:error, "REQUIREMENT_NOT_MET"}

      true ->
        :ok
    end
  end

  @doc "Template của các món đang mặc (để `Engine.derived/2`)."
  def equipped_templates(items), do: Enum.map(equipment(items), &Data.item(&1.template_id))

  @doc "Tổng số potion theo `potionType` trong mọi stack của túi (`KB_GAME_DESIGN §19.6`)."
  def potion_counts(items) do
    Enum.reduce(inventory(items), %{"HP" => 0, "MP" => 0}, fn it, acc ->
      case Data.item(it.template_id)["potionType"] do
        nil -> acc
        type -> Map.update(acc, type, it.quantity, &(&1 + it.quantity))
      end
    end)
  end
end

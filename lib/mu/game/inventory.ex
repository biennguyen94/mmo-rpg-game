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
  - Sắp xếp túi (Phase 2, `KB_TECHNICAL §5` `move_item` / `split`): chỉ trong `INVENTORY`,
    mỗi item một ô (P2-8). Thả lên ô trống = chuyển, lên món khác = hoán đổi, lên stack cùng
    template còn chỗ = gộp (thừa ở lại ô cũ).
  - Kho (Phase 3, P3-M3): 120 ô dùng chung mọi nhân vật của tài khoản; chuyển túi ↔ kho bằng
    `move_item` theo cùng luật (`plan_transfer/4`).
  """

  alias Mu.Game.{Config, Data, Engine}

  @inventory_slots 64
  # kho tài khoản 15×8 (`KB_CONFIG §6`, CHECK của DB `slot BETWEEN 0 AND 119`)
  @warehouse_slots 120
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

  @doc """
  Kế hoạch `move_item` món `item_id` (trong túi) sang ô túi `to`:
  `{:ok, :noop | {:move, id, to} | {:swap, id, to, other_id, from} | {:merge, id, other_id, n}}`
  (`n` = số chuyển sang stack đích) hoặc `{:error, code}`.
  """
  def plan_move(items, item_id, to) do
    with %{} = it <- find_in_inventory(items, item_id),
         :ok <- valid_slot(to) do
      case in_slot(items, "INVENTORY", to) do
        nil ->
          {:ok, {:move, it.id, to}}

        %{id: id} when id == it.id ->
          {:ok, :noop}

        other ->
          t = Data.item(it.template_id)

          if t["stackable"] == true and other.template_id == it.template_id and
               other.quantity < t["maxStack"] do
            {:ok, {:merge, it.id, other.id, min(it.quantity, t["maxStack"] - other.quantity)}}
          else
            {:ok, {:swap, it.id, to, other.id, it.slot}}
          end
      end
    end
  end

  @doc """
  Kế hoạch `split`: tách `quantity` cái từ stack `item_id` sang ô túi trống `to`
  (`nil` = ô trống thấp nhất). Chỉ item `stackable`, `1 <= quantity < số đang có`.
  `{:ok, to}` hoặc `{:error, code}`.
  """
  def plan_split(items, item_id, quantity, to) do
    with %{} = it <- find_in_inventory(items, item_id),
         :ok <-
           if(
             Data.item(it.template_id)["stackable"] == true and is_integer(quantity) and
               quantity in 1..(it.quantity - 1)//1,
             do: :ok,
             else: {:error, "INVALID_TARGET"}
           ) do
      case to do
        nil ->
          if s = first_free_slot(items), do: {:ok, s}, else: {:error, "INVENTORY_FULL"}

        to ->
          with :ok <- valid_slot(to) do
            if in_slot(items, "INVENTORY", to), do: {:error, "INVALID_SLOT"}, else: {:ok, to}
          end
      end
    end
  end

  @doc """
  Kế hoạch chuyển giữa túi và kho (P3-M3; `move_item` có `WAREHOUSE` ở nguồn hoặc đích).
  `items`: đồ của nhân vật, `warehouse`: đồ trong kho của tài khoản (location `WAREHOUSE`).
  Nguồn phải ở túi hoặc kho (đồ đang mặc → `INVALID_SLOT`), đích `{location, slot}` với
  location `INVENTORY` | `WAREHOUSE`. Ô trống = chuyển, cùng ô = không làm gì, stack cùng
  template còn chỗ = gộp, món khác = hoán đổi (món kia về ô cũ của món chuyển).
  `{:ok, :noop | {:move, id, to} | {:swap, id, to, other_id, from} | {:merge, id, other_id, n}}`
  với `to` / `from` = `{location, slot}`, hoặc `{:error, code}`.
  """
  def plan_transfer(items, warehouse, item_id, {to_loc, to_slot} = to) do
    with %{} = it <- find_movable(items ++ warehouse, item_id),
         :ok <- valid_slot(to_loc, to_slot) do
      dest = if to_loc == "WAREHOUSE", do: warehouse, else: items

      case in_slot(dest, to_loc, to_slot) do
        nil ->
          {:ok, {:move, it.id, to}}

        %{id: id} when id == it.id ->
          {:ok, :noop}

        other ->
          t = Data.item(it.template_id)

          if t["stackable"] == true and other.template_id == it.template_id and
               other.quantity < t["maxStack"] do
            {:ok, {:merge, it.id, other.id, min(it.quantity, t["maxStack"] - other.quantity)}}
          else
            {:ok, {:swap, it.id, to, other.id, {it.location, it.slot}}}
          end
      end
    end
  end

  def warehouse_slots, do: @warehouse_slots

  defp find_movable(all, item_id) do
    case Enum.find(all, &(&1.id == item_id)) do
      %{location: loc} = it when loc in ~w(INVENTORY WAREHOUSE) -> it
      %{} -> {:error, "INVALID_SLOT"}
      nil -> {:error, "NOT_OWNER"}
    end
  end

  defp valid_slot("INVENTORY", s), do: valid_slot(s)

  defp valid_slot("WAREHOUSE", s) when is_integer(s) and s >= 0 and s < @warehouse_slots,
    do: :ok

  defp valid_slot(_, _), do: {:error, "INVALID_SLOT"}

  @doc "Món `item_id` trong túi (không phải đồ đang mặc) để `drop`: `{:ok, item}` hoặc lỗi."
  def droppable(items, item_id) do
    with %{} = it <- find_in_inventory(items, item_id), do: {:ok, it}
  end

  defp find_in_inventory(items, item_id) do
    case Enum.find(items, &(&1.id == item_id)) do
      %{location: "INVENTORY"} = it -> it
      %{} -> {:error, "INVALID_SLOT"}
      nil -> {:error, "NOT_OWNER"}
    end
  end

  defp valid_slot(s) when is_integer(s) and s >= 0 and s < @inventory_slots, do: :ok
  defp valid_slot(_), do: {:error, "INVALID_SLOT"}

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

      # MG không đội mũ (KB_CONFIG §6, `forbiddenSlots` trong classes.json, P3-M5)
      template["slot"] in (Data.class(c.class)["forbiddenSlots"] || []) ->
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

  @doc """
  Luật vũ khí hai tay (P2-5, `combat.twoHandedWeaponTypes`): mặc vũ khí hai tay khi ô SHIELD
  có đồ, hoặc mặc khiên khi đang cầm vũ khí hai tay → `{:error, "INVALID_SLOT"}`.
  Đồ đang ở chính ô `slot` sẽ bị thay nên không tính.
  """
  def two_hand_ok(items, template, slot) do
    weapon = in_slot(items, "EQUIPMENT", 5)
    shield = in_slot(items, "EQUIPMENT", 6)

    cond do
      slot == 5 and two_handed?(template) and shield != nil ->
        {:error, "INVALID_SLOT"}

      slot == 6 and weapon != nil and two_handed?(Data.item(weapon.template_id)) ->
        {:error, "INVALID_SLOT"}

      true ->
        :ok
    end
  end

  def two_handed?(template),
    do: template["weaponType"] in Config.get(["combat", "twoHandedWeaponTypes"])

  @doc "Template của các món đang mặc, đã cộng chỉ số theo +N (`Engine.leveled/2`), cho `Engine.derived/2`."
  def equipped_templates(items),
    do: Enum.map(equipment(items), &Engine.leveled(Data.item(&1.template_id), &1.item_level))

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

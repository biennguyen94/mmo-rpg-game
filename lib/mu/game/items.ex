defmodule Mu.Game.Items do
  @moduledoc """
  Đồ của nhân vật trong DB (`items` + `item_locations` + `item_audit_log`, `KB_TECHNICAL §9`).

  Mỗi thao tác là **một transaction**: khóa row `characters` của nhân vật (`FOR UPDATE`) để
  mọi thao tác đồ/Zen của cùng nhân vật chạy tuần tự kể cả khi đến từ hai tiến trình, đọc
  lại đồ từ DB (không tin bản trong bộ nhớ), kiểm tra bằng `Mu.Game.Inventory`, ghi thay đổi
  và audit. Zen đổi bằng `UPDATE ... SET zen = zen + Δ, version = version + 1` trong cùng
  transaction (CHECK `zen >= 0` của DB là chốt cuối).

  Trả `{:ok, %{items, zen, version}}` (`drop` thêm `dropped`) (đồ đọc lại sau khi commit, Zen/version mới của nhân
  vật) hoặc `{:error, code}` (mã `KB_TECHNICAL §5`).
  """

  import Ecto.Query

  alias Mu.Repo
  alias Mu.Ulid
  alias Mu.Game.{Character, Data, Inventory, Item, ItemAudit, ItemLocation}

  @doc "Đồ của nhân vật (túi + trang bị) dạng map phẳng."
  def load(character_id) do
    Repo.all(
      from i in Item,
        join: l in ItemLocation,
        on: l.item_id == i.id,
        where: l.character_id == ^character_id,
        order_by: [l.location, l.slot],
        select: %{
          id: i.id,
          serial: i.serial,
          template_id: i.template_id,
          quantity: i.quantity,
          item_level: i.item_level,
          durability: i.durability,
          luck: i.luck,
          skill: i.skill,
          excellent_options: i.excellent_options,
          location: l.location,
          slot: l.slot
        }
    )
  end

  # ---------- Thêm đồ (nhặt, mua) ----------

  @doc """
  Nhặt đồ dưới đất: `ground` có `serial`, `template_id`, tùy chọn `quantity` (mặc định 1) và
  `attrs` (thuộc tính của món người chơi đã `drop`); `from` là chủ cũ (vd `"ground:lorencia"`).
  Gộp vào stack có sẵn thì serial dưới đất biến mất (ghi audit `PICKUP_MERGE`).
  """
  def pickup(character_id, %{serial: serial, template_id: tid} = g, from) do
    tx(character_id, fn _c, items ->
      with {:ok, plan} <- Inventory.plan_add(items, tid, Map.get(g, :quantity, 1)) do
        apply_add(character_id, tid, plan, "PICKUP", from, [serial], %{}, Map.get(g, :attrs))
        {:ok, 0}
      end
    end)
  end

  @doc "Mua `quantity` cái `template_id` với giá `price_each`, trừ Zen (NPC `npc_id`)."
  def buy(character_id, template_id, quantity, price_each, npc_id) do
    tx(character_id, fn c, items ->
      cost = price_each * quantity

      with :ok <- if(c.zen >= cost, do: :ok, else: {:error, "NOT_ENOUGH_ZEN"}),
           {:ok, plan} <- Inventory.plan_add(items, template_id, quantity) do
        apply_add(
          character_id,
          template_id,
          plan,
          "BUY",
          "npc:" <> npc_id,
          [],
          %{
            price: price_each
          },
          nil
        )

        {:ok, -cost}
      end
    end)
  end

  defp apply_add(cid, tid, plan, action, from, serials, detail, attrs) do
    t = Data.item(tid)
    to = "char:" <> cid

    Enum.reduce(plan, serials, fn
      {:merge, item_id, n}, serials ->
        Repo.update_all(from(i in Item, where: i.id == ^item_id), inc: [quantity: n])

        audit(
          item_id,
          action <> "_MERGE",
          from,
          to,
          Map.merge(detail, %{quantity: n, serials: serials})
        )

        []

      {:new, slot, n}, serials ->
        # serial (và thuộc tính) của món dưới đất chỉ dùng cho stack mới đầu tiên
        {serial, rest, attrs} =
          case serials do
            [s | rest] -> {s, rest, attrs || %{}}
            [] -> {Ulid.generate(), [], %{}}
          end

        item =
          %Item{serial: serial, template_id: tid, quantity: n, durability: t["durability"]}
          |> Ecto.Changeset.change(attrs)
          |> Ecto.Changeset.unique_constraint(:serial, name: :items_serial_key)
          |> Repo.insert()
          # serial đã có trong DB (đã có người nhặt): không tạo bản thứ hai
          |> case do
            {:ok, item} -> item
            {:error, _} -> Repo.rollback("NOT_OWNER")
          end

        Repo.insert!(%ItemLocation{
          item_id: item.id,
          location: "INVENTORY",
          character_id: cid,
          slot: slot
        })

        audit(item.id, action, from, to, Map.merge(detail, %{quantity: n, slot: slot}))
        rest
    end)
  end

  # ---------- Trang bị ----------

  @doc """
  Mặc món `item_id` (đang ở túi) vào ô trang bị `slot`. Ô đã có đồ thì đổi chỗ: món cũ về
  đúng ô túi của món mới. `c` là nhân vật (class, level, stat) để kiểm yêu cầu.
  """
  def equip(%{id: cid} = c, item_id, slot) do
    tx(cid, fn _locked, items ->
      with %{location: "INVENTORY"} = it <- find(items, item_id) || {:error, "NOT_OWNER"},
           :ok <- (is_integer(slot) && :ok) || {:error, "INVALID_SLOT"},
           :ok <- Inventory.can_equip(c, Data.item(it.template_id), slot) do
        old = Inventory.in_slot(items, "EQUIPMENT", slot)
        if old, do: Repo.delete_all(from(l in ItemLocation, where: l.item_id == ^old.id))
        move(it.id, "EQUIPMENT", slot)
        audit(it.id, "EQUIP", "char:" <> cid, "char:" <> cid, %{from: it.slot, to: slot})

        if old do
          Repo.insert!(%ItemLocation{
            item_id: old.id,
            location: "INVENTORY",
            character_id: cid,
            slot: it.slot
          })

          audit(old.id, "UNEQUIP", "char:" <> cid, "char:" <> cid, %{from: slot, to: it.slot})
        end

        {:ok, 0}
      else
        %{location: _} -> {:error, "INVALID_SLOT"}
        error -> error
      end
    end)
  end

  @doc "Tháo đồ ở ô trang bị `slot` về ô túi `to_slot` (`nil` = ô trống thấp nhất)."
  def unequip(cid, slot, to_slot) do
    tx(cid, fn _c, items ->
      with %{} = it <-
             (is_integer(slot) && Inventory.in_slot(items, "EQUIPMENT", slot)) ||
               {:error, "INVALID_SLOT"},
           {:ok, to} <- target_slot(items, to_slot) do
        move(it.id, "INVENTORY", to)
        audit(it.id, "UNEQUIP", "char:" <> cid, "char:" <> cid, %{from: slot, to: to})
        {:ok, 0}
      end
    end)
  end

  defp target_slot(items, nil) do
    case Inventory.first_free_slot(items) do
      nil -> {:error, "INVENTORY_FULL"}
      s -> {:ok, s}
    end
  end

  defp target_slot(items, s) when is_integer(s) and s >= 0 do
    cond do
      Inventory.first_free_slot(items) == nil -> {:error, "INVENTORY_FULL"}
      s >= Inventory.inventory_slots() -> {:error, "INVALID_SLOT"}
      Inventory.in_slot(items, "INVENTORY", s) -> {:error, "INVALID_SLOT"}
      true -> {:ok, s}
    end
  end

  defp target_slot(_, _), do: {:error, "INVALID_SLOT"}

  # ---------- Sắp xếp túi, vứt đồ (Phase 2, P2-M1) ----------

  @doc """
  `move_item`: chuyển món `item_id` sang ô túi `to` — ô trống thì chuyển, có món khác thì hoán
  đổi, stack cùng template còn chỗ thì gộp (`Inventory.plan_move/3`).
  """
  def move_item(cid, item_id, to) do
    owner = "char:" <> cid

    tx(cid, fn _c, items ->
      with {:ok, plan} <- Inventory.plan_move(items, item_id, to) do
        case plan do
          :noop ->
            :ok

          {:move, id, to} ->
            from_slot = find(items, id).slot
            move(id, "INVENTORY", to)
            audit(id, "MOVE", owner, owner, %{from: from_slot, to: to})

          {:swap, id, to, other, from_slot} ->
            # chỉ mục duy nhất (character_id, location, slot) không hoãn được: gỡ một bên trước
            Repo.delete_all(from(l in ItemLocation, where: l.item_id == ^other))
            move(id, "INVENTORY", to)

            Repo.insert!(%ItemLocation{
              item_id: other,
              location: "INVENTORY",
              character_id: cid,
              slot: from_slot
            })

            audit(id, "MOVE", owner, owner, %{from: from_slot, to: to})
            audit(other, "MOVE", owner, owner, %{from: to, to: from_slot})

          {:merge, id, other, n} ->
            it = find(items, id)
            Repo.update_all(from(i in Item, where: i.id == ^other), inc: [quantity: n])
            take(it, n, "MERGE", owner, owner, %{quantity: n, into: other})
        end

        {:ok, 0}
      end
    end)
  end

  @doc "`split`: tách `quantity` cái từ stack `item_id` sang ô túi trống `to` (`nil` = thấp nhất)."
  def split(cid, item_id, quantity, to) do
    owner = "char:" <> cid

    tx(cid, fn _c, items ->
      with {:ok, to} <- Inventory.plan_split(items, item_id, quantity, to) do
        it = find(items, item_id)
        Repo.update_all(from(i in Item, where: i.id == ^it.id), inc: [quantity: -quantity])

        new =
          Repo.insert!(%Item{
            serial: Ulid.generate(),
            template_id: it.template_id,
            quantity: quantity,
            item_level: it.item_level,
            durability: it.durability,
            luck: it.luck,
            skill: it.skill,
            excellent_options: it.excellent_options
          })

        Repo.insert!(%ItemLocation{
          item_id: new.id,
          location: "INVENTORY",
          character_id: cid,
          slot: to
        })

        audit(it.id, "SPLIT", owner, owner, %{quantity: quantity, into: new.id})
        audit(new.id, "SPLIT", owner, owner, %{quantity: quantity, from: it.id, slot: to})
        {:ok, 0}
      end
    end)
  end

  @doc """
  `drop`: vứt cả stack `item_id` (trong túi) xuống đất `to` (vd `"ground:lorencia"`, P2-9).
  Item bị xóa khỏi DB (đồ dưới đất chỉ ở RAM, `KB_TECHNICAL §9`); `res.dropped` giữ serial,
  template, số lượng và thuộc tính để MapServer đặt lên mặt đất và người nhặt nhận lại y nguyên.
  """
  def drop(cid, item_id, to) do
    tx(cid, fn _c, items ->
      with {:ok, it} <- Inventory.droppable(items, item_id) do
        take(it, it.quantity, "DROP", "char:" <> cid, to, %{
          quantity: it.quantity,
          template_id: it.template_id
        })

        dropped = %{
          serial: it.serial,
          template_id: it.template_id,
          quantity: it.quantity,
          attrs: Map.take(it, [:item_level, :durability, :luck, :skill, :excellent_options])
        }

        {:ok, 0, %{dropped: dropped}}
      end
    end)
  end

  # ---------- Dùng, bán ----------

  @doc "Tiêu hao `n` cái từ stack `item_id` trong túi (dùng potion). Hết thì xóa stack."
  def consume(cid, item_id, n \\ 1) do
    tx(cid, fn _c, items ->
      with %{location: "INVENTORY"} = it <- find(items, item_id) || {:error, "NOT_OWNER"},
           :ok <- if(it.quantity >= n, do: :ok, else: {:error, "INVALID_TARGET"}) do
        take(it, n, "USE", "char:" <> cid, "consumed", %{quantity: n})
        {:ok, 0}
      else
        %{location: _} -> {:error, "INVALID_SLOT"}
        error -> error
      end
    end)
  end

  @doc "Bán `quantity` cái (`nil` = cả stack) từ `item_id` trong túi, nhận `price_each` Zen mỗi cái."
  def sell(cid, item_id, quantity, price_each, npc_id) do
    tx(cid, fn _c, items ->
      with %{location: "INVENTORY"} = it <- find(items, item_id) || {:error, "NOT_OWNER"},
           n = quantity || it.quantity,
           :ok <-
             if(is_integer(n) and n in 1..it.quantity, do: :ok, else: {:error, "INVALID_TARGET"}) do
        take(it, n, "SELL", "char:" <> cid, "npc:" <> npc_id, %{quantity: n, price: price_each})
        {:ok, n * price_each}
      else
        %{location: _} -> {:error, "INVALID_SLOT"}
        error -> error
      end
    end)
  end

  # bớt n cái; hết thì xóa row (location trước, rồi item)
  defp take(it, n, action, from, to, detail) do
    if it.quantity > n do
      Repo.update_all(from(i in Item, where: i.id == ^it.id), inc: [quantity: -n])
    else
      Repo.delete_all(from(l in ItemLocation, where: l.item_id == ^it.id))
      Repo.delete_all(from(i in Item, where: i.id == ^it.id))
    end

    audit(it.id, action, from, to, Map.put(detail, :serial, it.serial))
  end

  # ---------- Dọn dẹp ----------

  @doc """
  Xóa item không có `item_locations` (orphan, `KB_TECHNICAL §9`): ghi audit `ORPHAN_DELETE`
  rồi xóa. Trả số item đã xóa.
  """
  def delete_orphans do
    no_location = from(l in ItemLocation, select: l.item_id)

    Repo.transaction(fn ->
      orphans =
        Repo.all(
          from i in Item,
            where: i.id not in subquery(no_location),
            select: %{id: i.id, serial: i.serial, template_id: i.template_id}
        )

      for o <- orphans do
        audit(o.id, "ORPHAN_DELETE", nil, nil, %{serial: o.serial, template_id: o.template_id})
      end

      ids = Enum.map(orphans, & &1.id)

      # điều kiện lặp lại lúc xóa: item vừa có location (không xảy ra ở Phase 1) thì giữ
      {n, _} =
        Repo.delete_all(
          from(i in Item, where: i.id in ^ids and i.id not in subquery(no_location))
        )

      n
    end)
  end

  # ---------- Nội bộ ----------

  defp tx(cid, fun) do
    result =
      Repo.transaction(fn ->
        c = Repo.one!(from(c in Character, where: c.id == ^cid, lock: "FOR UPDATE"))

        case fun.(c, load(cid)) do
          {:ok, 0} ->
            {c.zen, c.version, %{}}

          {:ok, 0, extra} ->
            {c.zen, c.version, extra}

          {:ok, delta} ->
            {1, [{zen, version}]} =
              Repo.update_all(
                from(ch in Character, where: ch.id == ^cid, select: {ch.zen, ch.version}),
                inc: [zen: delta, version: 1]
              )

            {zen, version, %{}}

          {:error, code} ->
            Repo.rollback(code)
        end
      end)

    case result do
      {:ok, {zen, version, extra}} ->
        {:ok, Map.merge(extra, %{items: load(cid), zen: zen, version: version})}

      {:error, code} ->
        {:error, code}
    end
  end

  defp find(items, item_id), do: Enum.find(items, &(&1.id == item_id))

  defp move(item_id, location, slot) do
    {1, _} =
      Repo.update_all(from(l in ItemLocation, where: l.item_id == ^item_id),
        set: [location: location, slot: slot]
      )
  end

  defp audit(item_id, action, from, to, detail) do
    Repo.insert!(%ItemAudit{
      item_id: item_id,
      action: action,
      from_owner: from,
      to_owner: to,
      detail: detail
    })
  end
end

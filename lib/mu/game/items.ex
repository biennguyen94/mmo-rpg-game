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
  alias Mu.Game.{Character, Data, Inventory, Item, ItemAudit, ItemLocation, ZenAudit}

  @doc "Đồ của nhân vật (túi + trang bị) dạng map phẳng."
  def load(character_id), do: load_where(dynamic([loc: l], l.character_id == ^character_id))

  @doc "Đồ trong kho của tài khoản (location `WAREHOUSE`, P3-M3), cùng dạng với `load/1`."
  def load_warehouse(account_id), do: load_where(dynamic([loc: l], l.account_id == ^account_id))

  defp load_where(cond) do
    Repo.all(
      from i in Item,
        join: l in ItemLocation,
        as: :loc,
        on: l.item_id == i.id,
        where: ^cond,
        order_by: [l.location, l.slot],
        select: %{
          id: i.id,
          serial: i.serial,
          template_id: i.template_id,
          quantity: i.quantity,
          item_level: i.item_level,
          option_level: i.option_level,
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
    tx(
      character_id,
      fn c, items ->
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
      end,
      {"BUY", "npc:" <> npc_id}
    )
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

  @doc """
  Đồ khởi đầu của nhân vật mới (P2-3, `newCharacter.startingEquipment`): mặc sẵn vào ô trang
  bị đầu tiên của template, audit `STARTER`. Gọi trong transaction tạo nhân vật.
  """
  def give_starting_equipment(cid, template_ids) do
    for tid <- template_ids do
      t = Data.item(tid)
      [slot | _] = Inventory.equip_slots(t)

      item =
        Repo.insert!(%Item{
          serial: Ulid.generate(),
          template_id: tid,
          quantity: 1,
          durability: t["durability"]
        })

      Repo.insert!(%ItemLocation{
        item_id: item.id,
        location: "EQUIPMENT",
        character_id: cid,
        slot: slot
      })

      audit(item.id, "STARTER", nil, "char:" <> cid, %{slot: slot})
    end

    :ok
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
           :ok <- Inventory.can_equip(c, Data.item(it.template_id), slot),
           :ok <- Inventory.two_hand_ok(items, Data.item(it.template_id), slot) do
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

  # ---------- Kho tài khoản (P3-M3) ----------

  @doc """
  `move_item` có kho ở nguồn hoặc đích: chuyển món `item_id` (túi của `cid` hoặc kho của
  `account_id`) tới `{location, slot}` (`Inventory.plan_transfer/4`). Một transaction: khóa
  row nhân vật và row tài khoản (`FOR UPDATE`), đọc lại túi + kho từ DB. Audit `WAREHOUSE_IN`
  (túi → kho), `WAREHOUSE_OUT` (kho → túi), `MOVE` (cùng chỗ), `MERGE` khi gộp stack.
  Kết quả có thêm `warehouse` (đồ trong kho sau commit).
  """
  def transfer(cid, account_id, item_id, to) do
    result =
      tx(cid, fn _c, items ->
        Repo.one!(from(a in Mu.Accounts.Account, where: a.id == ^account_id, lock: "FOR UPDATE"))
        warehouse = load_warehouse(account_id)

        with {:ok, plan} <- Inventory.plan_transfer(items, warehouse, item_id, to) do
          apply_transfer(plan, items ++ warehouse, cid, account_id)
          {:ok, 0}
        end
      end)

    with {:ok, res} <- result, do: {:ok, Map.put(res, :warehouse, load_warehouse(account_id))}
  end

  defp apply_transfer(:noop, _all, _cid, _aid), do: :ok

  defp apply_transfer({:move, id, {loc, slot} = to}, all, cid, aid) do
    it = find(all, id)
    place(id, to, cid, aid)

    audit(
      id,
      transfer_action(it.location, loc),
      owner(it.location, cid, aid),
      owner(loc, cid, aid),
      %{
        from: it.slot,
        to: slot
      }
    )
  end

  defp apply_transfer(
         {:swap, id, {loc, slot} = to, other, {from_loc, from_slot} = from},
         all,
         cid,
         aid
       ) do
    it = find(all, id)

    # chỉ mục duy nhất (chủ, location, slot) không hoãn được: gỡ một bên trước
    Repo.delete_all(from(l in ItemLocation, where: l.item_id == ^other))
    place(id, to, cid, aid)
    Repo.insert!(location_row(other, from, cid, aid))

    audit(id, transfer_action(from_loc, loc), owner(from_loc, cid, aid), owner(loc, cid, aid), %{
      from: it.slot,
      to: slot
    })

    audit(
      other,
      transfer_action(loc, from_loc),
      owner(loc, cid, aid),
      owner(from_loc, cid, aid),
      %{
        from: slot,
        to: from_slot
      }
    )
  end

  defp apply_transfer({:merge, id, other, n}, all, cid, aid) do
    it = find(all, id)
    to_loc = find(all, other).location
    Repo.update_all(from(i in Item, where: i.id == ^other), inc: [quantity: n])

    take(it, n, "MERGE", owner(it.location, cid, aid), owner(to_loc, cid, aid), %{
      quantity: n,
      into: other
    })
  end

  defp transfer_action(same, same), do: "MOVE"
  defp transfer_action(_, "WAREHOUSE"), do: "WAREHOUSE_IN"
  defp transfer_action("WAREHOUSE", _), do: "WAREHOUSE_OUT"

  defp owner("WAREHOUSE", _cid, aid), do: "acc:" <> aid
  defp owner(_, cid, _aid), do: "char:" <> cid

  # đổi chỗ (cả chủ: túi thuộc nhân vật, kho thuộc tài khoản — CHECK của DB)
  defp place(item_id, to, cid, aid) do
    row = location_row(item_id, to, cid, aid)

    {1, _} =
      Repo.update_all(from(l in ItemLocation, where: l.item_id == ^item_id),
        set: [
          location: row.location,
          slot: row.slot,
          character_id: row.character_id,
          account_id: row.account_id
        ]
      )
  end

  defp location_row(item_id, {"WAREHOUSE", slot}, _cid, aid),
    do: %ItemLocation{item_id: item_id, location: "WAREHOUSE", account_id: aid, slot: slot}

  defp location_row(item_id, {loc, slot}, cid, _aid),
    do: %ItemLocation{item_id: item_id, location: loc, character_id: cid, slot: slot}

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
            option_level: it.option_level,
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
          attrs:
            Map.take(it, [
              :item_level,
              :option_level,
              :durability,
              :luck,
              :skill,
              :excellent_options
            ])
        }

        {:ok, 0, %{dropped: dropped}}
      end
    end)
  end

  # ---------- Hộp thư (P2-M6) ----------

  @doc """
  Nhận quà mail `mail_id` (Zen + item) — một transaction: khóa nhân vật + row mail (`FOR
  UPDATE`), còn hạn, chưa nhận, có quà; item vào túi theo luật gộp stack (túi đầy →
  `INVENTORY_FULL`, không nhận gì), audit `MAIL_CLAIM` (`from_owner` `"mail:<id>"`).
  """
  def claim_mail(cid, mail_id) do
    tx(
      cid,
      fn _c, items ->
        with {:ok, uuid} <- Ecto.UUID.cast(mail_id) |> ok_or("INVALID_TARGET"),
             %Mu.Mail.Message{} = m <- lock_mail(cid, uuid) || {:error, "INVALID_TARGET"},
             :ok <- if(Mu.Mail.reward?(m), do: :ok, else: {:error, "INVALID_TARGET"}),
             {:ok, plan} <-
               if(m.item_template_id,
                 do: Inventory.plan_add(items, m.item_template_id, m.item_quantity),
                 else: {:ok, []}
               ) do
          if m.item_template_id,
            do:
              apply_add(
                cid,
                m.item_template_id,
                plan,
                "MAIL_CLAIM",
                "mail:" <> m.id,
                [],
                %{},
                nil
              )

          now = DateTime.utc_now()

          Repo.update_all(from(x in Mu.Mail.Message, where: x.id == ^m.id),
            set: [claimed_at: now, read_at: m.read_at || now]
          )

          {:ok, m.zen}
        end
      end,
      {"MAIL", "mail:" <> to_string(mail_id)}
    )
  end

  # ---------- Quản trị (DEC-188) ----------

  @doc """
  Quản trị tặng `quantity` món `tid` vào túi (stack theo luật gộp; món mới mang `item_level` /
  `option_level` = `attrs`), audit `ADMIN` (`from_owner` `"admin"`). Túi đầy → `INVENTORY_FULL`.
  """
  def admin_grant(cid, tid, quantity, attrs, ref) do
    tx(cid, fn _c, items ->
      with {:ok, plan} <- Inventory.plan_add(items, tid, quantity) do
        apply_add(cid, tid, plan, "ADMIN", "admin", [Ulid.generate()], %{ref: ref}, attrs)
        {:ok, 0}
      end
    end)
  end

  @doc "Quản trị cộng (âm = trừ) Zen, audit Zen `ADMIN`. Không đủ để trừ → `NOT_ENOUGH_ZEN`."
  def admin_zen(cid, delta, ref) do
    tx(
      cid,
      fn c, _items ->
        if c.zen + delta >= 0, do: {:ok, delta}, else: {:error, "NOT_ENOUGH_ZEN"}
      end,
      {"ADMIN", ref}
    )
  end

  defp ok_or({:ok, v}, _), do: {:ok, v}
  defp ok_or(_, code), do: {:error, code}

  defp lock_mail(cid, id) do
    Repo.one(
      from m in Mu.Mail.Message,
        where:
          m.id == ^id and m.character_id == ^cid and is_nil(m.claimed_at) and
            m.expires_at > ^DateTime.utc_now(),
        lock: "FOR UPDATE"
    )
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

  # ---------- Giao dịch (P5-M4, KB_TECHNICAL §10) ----------

  @doc """
  Chốt giao dịch giữa hai nhân vật (`TradeSettlement` gọi khi cả hai đã đồng ý). `a`, `b`:
  `%{cid, items: [item_id], zen}` — đồ (cả stack, trong túi) và Zen mỗi bên đưa. **Một
  transaction**: khóa hai nhân vật rồi các `items` / `item_locations` liên quan, **sắp theo id**
  (tránh deadlock); kiểm lại từng món vẫn trong túi đúng chủ (`NOT_OWNER`), Zen đủ
  (`NOT_ENOUGH_ZEN`), túi bên nhận đủ ô sau khi bỏ đồ mình đưa (`INVENTORY_FULL`); chuyển đồ vào
  ô trống thấp nhất (audit `TRADE` `char:A → char:B`), đổi Zen + `version` hai bên (audit Zen
  `TRADE`, `ref` = bên kia). Sai bất kỳ điểm nào → rollback, không ghi gì.

  `{:ok, %{a_cid => %{items, zen, version}, b_cid => …}}` hoặc `{:error, code}`.
  """
  def trade(%{cid: ca} = a, %{cid: cb} = b, ref) do
    Repo.transaction(fn ->
      chars =
        Repo.all(
          from(c in Character,
            where: c.id in ^[ca, cb],
            order_by: c.id,
            lock: "FOR UPDATE"
          )
        )
        |> Map.new(&{&1.id, &1})

      ids = Enum.sort(a.items ++ b.items)
      Repo.all(from(i in Item, where: i.id in ^ids, order_by: i.id, lock: "FOR UPDATE"))

      locs =
        Repo.all(
          from(l in ItemLocation,
            where: l.item_id in ^ids,
            order_by: l.item_id,
            lock: "FOR UPDATE"
          )
        )
        |> Map.new(&{&1.item_id, &1})

      owned? = fn cid, item_ids ->
        Enum.all?(item_ids, fn id ->
          match?(%{location: "INVENTORY", character_id: ^cid}, locs[id])
        end)
      end

      cond do
        map_size(chars) != 2 or length(Enum.uniq(ids)) != length(ids) ->
          Repo.rollback("INVALID_TARGET")

        not (owned?.(ca, a.items) and owned?.(cb, b.items)) ->
          Repo.rollback("NOT_OWNER")

        chars[ca].zen < a.zen or chars[cb].zen < b.zen ->
          Repo.rollback("NOT_ENOUGH_ZEN")

        true ->
          to_b = free_slots(cb, b.items, length(a.items)) || Repo.rollback("INVENTORY_FULL")
          to_a = free_slots(ca, a.items, length(b.items)) || Repo.rollback("INVENTORY_FULL")

          # gỡ chỗ cũ trước rồi đặt chỗ mới: hai túi đầy vẫn đổi 1 lấy 1 được
          Repo.delete_all(from(l in ItemLocation, where: l.item_id in ^ids))
          place(a.items, to_b, ca, cb, locs, ref)
          place(b.items, to_a, cb, ca, locs, ref)

          for {cid, delta, other} <- [{ca, b.zen - a.zen, cb}, {cb, a.zen - b.zen, ca}] do
            {1, [balance]} =
              Repo.update_all(
                from(ch in Character, where: ch.id == ^cid, select: ch.zen),
                inc: [zen: delta, version: 1]
              )

            ZenAudit.log(cid, delta, balance, "TRADE", "char:" <> other)
          end

          :ok
      end
    end)
    |> case do
      {:ok, :ok} ->
        {:ok,
         Map.new([ca, cb], fn cid ->
           c = Repo.get!(Character, cid)
           {cid, %{items: load(cid), zen: c.zen, version: c.version}}
         end)}

      {:error, code} ->
        {:error, code}
    end
  end

  # `n` ô túi trống thấp nhất của `cid` khi đã bỏ các món `leaving`; không đủ → nil
  defp free_slots(cid, leaving, n) do
    used =
      for it <- load(cid),
          it.location == "INVENTORY",
          it.id not in leaving,
          into: MapSet.new(),
          do: it.slot

    free = Enum.reject(0..(Inventory.inventory_slots() - 1), &MapSet.member?(used, &1))
    if length(free) >= n, do: Enum.take(free, n), else: nil
  end

  defp place(item_ids, slots, from_cid, to_cid, locs, ref) do
    for {id, slot} <- Enum.zip(item_ids, slots) do
      Repo.insert!(%ItemLocation{
        item_id: id,
        location: "INVENTORY",
        character_id: to_cid,
        slot: slot
      })

      audit(id, "TRADE", "char:" <> from_cid, "char:" <> to_cid, %{
        trade: ref,
        from_slot: locs[id].slot,
        to: slot
      })
    end
  end

  # ---------- Ép jewel (P5-M2) ----------

  @doc """
  Ép jewel `jewel_id` lên đồ `item_id` (cả hai trong túi) theo `Mu.Game.Upgrade` với `rng`. Một
  transaction: trừ 1 jewel (audit `JEWEL_USE`), đổi `item_level` / `option_level` (audit
  `UPGRADE`, kèm cấp trước / sau và thành công hay không) hoặc mất đồ (`UPGRADE_DESTROY`, chưa
  dùng ở bảng hiện tại). Kết quả thêm `upgrade: %{item_id, template_id, jewel, ok, level, option,
  destroyed}`.
  """
  def upgrade(cid, item_id, jewel_id, rng) do
    tx(cid, fn _c, items ->
      with %{location: "INVENTORY"} = it <- find(items, item_id) || {:error, "NOT_OWNER"},
           %{location: "INVENTORY"} = j <- find(items, jewel_id) || {:error, "NOT_OWNER"},
           true <-
             (it.id != j.id and Data.item(j.template_id)["type"] == "JEWEL") ||
               {:error, "INVALID_TARGET"},
           {:ok, res, _rng} <-
             Mu.Game.Upgrade.apply(
               rng,
               Data.item(it.template_id),
               it.item_level,
               it.option_level,
               j.template_id
             ) do
        owner = "char:" <> cid
        take(j, 1, "JEWEL_USE", owner, "consumed", %{quantity: 1, target: it.id})

        detail = %{
          jewel: j.template_id,
          ok: res.ok,
          from_level: it.item_level,
          to_level: res.level,
          from_option: it.option_level,
          to_option: res.option,
          serial: it.serial
        }

        if res.destroyed do
          take(it, 1, "UPGRADE_DESTROY", owner, "destroyed", detail)
        else
          Repo.update_all(from(i in Item, where: i.id == ^it.id),
            set: [item_level: res.level, option_level: res.option]
          )

          audit(it.id, "UPGRADE", owner, owner, detail)
        end

        {:ok, 0,
         %{
           upgrade:
             Map.merge(res, %{item_id: it.id, template_id: it.template_id, jewel: j.template_id})
         }}
      else
        %{location: _} -> {:error, "INVALID_SLOT"}
        error -> error
      end
    end)
  end

  @doc "Bán `quantity` cái (`nil` = cả stack) từ `item_id` trong túi, nhận `price_each` Zen mỗi cái."
  def sell(cid, item_id, quantity, price_each, npc_id) do
    tx(
      cid,
      fn _c, items ->
        with %{location: "INVENTORY"} = it <- find(items, item_id) || {:error, "NOT_OWNER"},
             n = quantity || it.quantity,
             :ok <-
               if(is_integer(n) and n in 1..it.quantity,
                 do: :ok,
                 else: {:error, "INVALID_TARGET"}
               ) do
          take(it, n, "SELL", "char:" <> cid, "npc:" <> npc_id, %{quantity: n, price: price_each})
          {:ok, n * price_each}
        else
          %{location: _} -> {:error, "INVALID_SLOT"}
          error -> error
        end
      end,
      {"SELL", "npc:" <> npc_id}
    )
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

  # ---------- Chaos Machine (P6-M3, P6-3) ----------

  @doc """
  Kết hợp các món `item_ids` (trong túi) ở Chaos Machine — **một transaction**: đọc lại đồ, khớp
  công thức (`Mu.Game.Chaos.match/1`), đủ Zen, tiêu đầu vào (audit `CHAOS_IN`,
  `char:<id> → chaos:<công thức>`), trừ phí (Zen `CHAOS`), quay tỉ lệ bằng `rng`; thành công thì
  thêm món kết quả (audit `CHAOS_OUT`, `chaos:<công thức> → char:<id>`). Thất bại vẫn mất đầu vào
  + phí (P6-3).

  `{:ok, %{items, zen, version, chaos: %{recipe, ok, template_id, rate}}}` hoặc `{:error, code}`.
  """
  def chaos_combine(cid, item_ids, rng) do
    tx(
      cid,
      fn c, items ->
        with {:ok, picked} <- pick_inventory(items, item_ids),
             {:ok, m} <- Mu.Game.Chaos.match(picked),
             :ok <- if(c.zen >= m.zen, do: :ok, else: {:error, "NOT_ENOUGH_ZEN"}) do
          src = "chaos:" <> m.recipe["id"]

          for {id, n} <- m.consume,
              do: take(find(items, id), n, "CHAOS_IN", "char:" <> cid, src, %{quantity: n})

          {out, _rng} = Mu.Game.Chaos.roll(rng, m, c.class)

          added =
            case out do
              nil ->
                :ok

              tid ->
                with {:ok, plan} <- Inventory.plan_add(load(cid), tid, 1) do
                  apply_add(cid, tid, plan, "CHAOS_OUT", src, [], %{rate: m.rate}, nil)
                  :ok
                end
            end

          with :ok <- added do
            res = %{recipe: m.recipe["id"], ok: out != nil, template_id: out, rate: m.rate}
            {:ok, -m.zen, %{chaos: res}}
          end
        end
      end,
      {"CHAOS", "chaos"}
    )
  end

  # các món (cả stack) trong túi theo id: không có → NOT_OWNER, đang mặc / trong kho → INVALID_SLOT
  defp pick_inventory(items, ids) when is_list(ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case find(items, id) do
        %{location: "INVENTORY"} = it -> {:cont, {:ok, acc ++ [it]}}
        %{} -> {:halt, {:error, "INVALID_SLOT"}}
        nil -> {:halt, {:error, "NOT_OWNER"}}
      end
    end)
  end

  defp pick_inventory(_items, _ids), do: {:error, "INVALID_TARGET"}

  # ---------- Quest (P6-M2, P6-2) ----------

  @doc """
  Trả quest `q` (template `quests.json`) — **một transaction**: khóa nhân vật + row
  `character_quests` (phải `ACTIVE`, kill đủ theo `progress` trong DB, đủ cấp theo cấp trong DB),
  nộp vật phẩm `collect` từ túi (audit `QUEST_IN`, `char:<id> → quest:<id>`), thêm đồ thưởng
  (audit `QUEST`, `quest:<id> → char:<id>`), cộng Zen (audit Zen `QUEST`), đặt `DONE`. Thiếu
  điều kiện → `REQUIREMENT_NOT_MET`; quest không đang làm → `INVALID_TARGET`; túi không đủ chỗ cho
  đồ thưởng → `INVENTORY_FULL`. EXP thưởng do Session cộng sau khi transaction xong (EXP nằm ở
  Session, như EXP hạ quái).

  `{:ok, %{items, zen, version, quest: id}}` hoặc `{:error, code}`.
  """
  def quest_turnin(cid, q, complete?) do
    qid = q["id"]
    src = "quest:" <> qid

    tx(
      cid,
      fn c, items ->
        row =
          Repo.one(
            from(r in Mu.Game.CharacterQuest,
              where: r.character_id == ^cid and r.quest_id == ^qid,
              lock: "FOR UPDATE"
            )
          )

        with %{state: "ACTIVE", progress: pr} <- row || {:error, "INVALID_TARGET"},
             true <- complete?.(pr, c.level, items) || {:error, "REQUIREMENT_NOT_MET"},
             :ok <- take_collect(cid, src, items, Mu.Game.Quests.collect_needs(q)),
             :ok <- give_rewards(cid, src, q["rewards"]["items"]) do
          Repo.update_all(
            from(r in Mu.Game.CharacterQuest,
              where: r.character_id == ^cid and r.quest_id == ^qid
            ),
            set: [state: "DONE", completed_at: DateTime.utc_now()]
          )

          {:ok, q["rewards"]["zen"], %{quest: qid}}
        else
          %{state: _} -> {:error, "INVALID_TARGET"}
          error -> error
        end
      end,
      {"QUEST", src}
    )
  end

  # nộp `n` cái mỗi template: stack nhỏ trước (giữ stack lớn), thiếu → REQUIREMENT_NOT_MET
  defp take_collect(cid, src, items, needs) do
    Enum.reduce_while(needs, :ok, fn {tid, n}, :ok ->
      stacks =
        Inventory.inventory(items)
        |> Enum.filter(&(&1.template_id == tid))
        |> Enum.sort_by(& &1.quantity)

      if stacks |> Enum.map(& &1.quantity) |> Enum.sum() < n do
        {:halt, {:error, "REQUIREMENT_NOT_MET"}}
      else
        Enum.reduce_while(stacks, n, fn
          _, 0 ->
            {:halt, 0}

          it, left ->
            k = min(it.quantity, left)
            take(it, k, "QUEST_IN", "char:" <> cid, src, %{quantity: k})
            {:cont, left - k}
        end)

        {:cont, :ok}
      end
    end)
  end

  defp give_rewards(cid, src, rewards) do
    Enum.reduce_while(rewards, :ok, fn %{"templateId" => tid, "quantity" => n}, :ok ->
      case Inventory.plan_add(load(cid), tid, n) do
        {:ok, plan} ->
          apply_add(cid, tid, plan, "QUEST", src, [], %{}, nil)
          {:cont, :ok}

        error ->
          {:halt, error}
      end
    end)
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

  # `zen`: `{reason, ref}` cho `zen_audit_log` khi thao tác đổi Zen (P5-M3)
  defp tx(cid, fun, zen \\ nil) do
    result =
      Repo.transaction(fn ->
        c = Repo.one!(from(c in Character, where: c.id == ^cid, lock: "FOR UPDATE"))

        case fun.(c, load(cid)) do
          {:ok, 0} ->
            {c.zen, c.version, %{}}

          {:ok, 0, extra} ->
            {c.zen, c.version, extra}

          {:ok, delta} ->
            add_zen(cid, delta, zen, %{})

          {:ok, delta, extra} ->
            add_zen(cid, delta, zen, extra)

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

  defp add_zen(cid, delta, zen, extra) do
    {1, [{balance, version}]} =
      Repo.update_all(
        from(ch in Character, where: ch.id == ^cid, select: {ch.zen, ch.version}),
        inc: [zen: delta, version: 1]
      )

    {reason, ref} = zen || raise "Items.tx: đổi Zen mà không có lý do audit"
    ZenAudit.log(cid, delta, balance, reason, ref)
    {balance, version, extra}
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

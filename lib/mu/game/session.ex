defmodule Mu.Game.Session do
  @moduledoc """
  Một tiến trình / tài khoản đang online (`KB_TECH_STACK §4`), giữ trạng thái nhân vật.
  Mọi lệnh của tài khoản đi qua đúng tiến trình này nên được xử lý tuần tự.

  Khung lấy từ `HacLong.Game.Session` (Registry + DynamicSupervisor, `call` thử lại khi
  tiến trình vừa tự tắt, theo dõi tab bằng monitor, `trap_exit` + ghi nốt khi tắt).

  Sở hữu dữ liệu (PHASE1_PLAN R5):
  - Session giữ tiến độ (level, EXP, stat, điểm tự do, Zen) và là nơi **duy nhất** ghi DB.
  - `Mu.World.MapServer` giữ vị trí, HP/MP, cooldown khi đang online; gửi về
    `{:map_reward, ...}` (hạ quái) và `{:map_died, _}`.

  Ghi DB (`Characters.save/2`, optimistic lock `version`):
  - ngay khi lên cấp, nhận Zen (G12), cộng điểm, rời map;
  - còn lại (EXP, vị trí, HP/MP) mỗi `session.saveIntervalSeconds` nếu có đổi.

  Đồ (`Mu.Game.Items`): Session giữ bản đọc lại từ DB sau mỗi thao tác; act item/Zen
  (pickup, equip, unequip, move_item, split, drop, use_item, buy, sell) idempotent theo `rid`: gửi lại cùng `rid`
  trả kết quả cũ, không làm lại. Trang bị đổi → chỉ số mới gửi MapServer.

  Tab: `session.singleLoginPerAccount` — tab mới vào thì tab cũ nhận `{:session_kicked, _}`;
  nhân vật vẫn ở trên map. Tab cuối đóng: rời map ngay, hoặc ở lại
  `session.logoutInCombatSeconds` nếu đang combat (G21). Session đẩy `{:push, "player", view}`
  cho các tab khi tiến độ đổi.
  """
  use GenServer, restart: :transient
  require Logger

  alias Mu.Game.{Characters, Config, Data, Engine, Inventory, Items}
  alias Mu.World.{Maps, MapServer, Pathfinding}

  # không còn tab nào trong khoảng này thì tự tắt
  @idle_timeout :timer.minutes(1)

  # act tạo/đổi item hoặc Zen: idempotent theo `rid` (KB_TECHNICAL §5)
  @item_acts ~w(pickup equip unequip move_item split drop use_item buy sell)
  # số `rid` gần nhất được nhớ kết quả
  @rid_memory 200

  @doc """
  Tab `pid` vào game với nhân vật `character_id`.
  `{:ok, character, info}` (`info`: kết quả `MapServer.join/3` + `items`) hoặc
  `{:error, :not_found}`.
  """
  def attach(account_id, character_id, pid), do: call(account_id, {:attach, character_id, pid})

  @doc "Nhân vật đang được giữ (`nil` nếu chưa có tab nào vào)."
  def get(account_id), do: call(account_id, :get)

  @doc "Lệnh `act` đã qua kiểm tra phong bì/rate-limit: `:ok` hoặc `{:error, code}`."
  def command(account_id, act, payload), do: call(account_id, {:command, act, payload})

  @doc "Pid của Session nếu đang chạy."
  def whereis(account_id) do
    case Registry.lookup(Mu.Game.Registry, account_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp call(account_id, msg, retry \\ true) do
    pid =
      case DynamicSupervisor.start_child(Mu.Game.SessionSupervisor, {__MODULE__, account_id}) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    GenServer.call(pid, msg)
  catch
    # tiến trình vừa tự tắt vì rảnh đúng lúc gọi: khởi động lại và thử một lần nữa
    :exit, {reason, _} when retry and reason in [:noproc, :normal] ->
      call(account_id, msg, false)
  end

  def start_link(account_id) do
    GenServer.start_link(__MODULE__, account_id,
      name: {:via, Registry, {Mu.Game.Registry, account_id}}
    )
  end

  @impl true
  def init(account_id) do
    Process.flag(:trap_exit, true)

    s = %{
      account_id: account_id,
      # `character`: trạng thái hiện tại; `saved`: bản đã ghi DB (để biết cột nào đổi)
      character: nil,
      saved: nil,
      items: [],
      # rid → kết quả, kèm hàng đợi để bỏ rid cũ
      rids: %{},
      rid_order: :queue.new(),
      # buff hiện có (MapServer gửi `{:map_buffs, ...}`), đưa vào `player.view.buffs` (P2-M3)
      buffs: [],
      tabs: %{},
      on_map: false,
      save_timer: nil,
      leave_timer: nil
    }

    {:ok, s, @idle_timeout}
  end

  @impl true
  def handle_call({:attach, character_id, pid}, _from, s) do
    case load(s, character_id) do
      nil ->
        reply({:error, :not_found}, s)

      character ->
        s = cancel_leave(s)

        # nhân vật khác với nhân vật đang trên map (Phase 1 không xảy ra: 1 nhân vật/tài khoản)
        s = if s.character && s.character.id != character.id, do: leave_map(s), else: s

        s =
          if s.saved && s.saved.id == character.id,
            do: s,
            else: %{s | saved: character, items: Items.load(character.id)}

        s = kick_tabs(%{s | character: character}, pid)
        s = %{s | tabs: Map.put(s.tabs, Process.monitor(pid), pid)}

        {:ok, info} = MapServer.join(character.map_id, map_player(character, s.items), self())

        c = %{
          s.character
          | position_x: info.x,
            position_y: info.y,
            hp_current: info.hp,
            mana_current: info.mp
        }

        s = %{s | character: c, on_map: true} |> schedule_save()
        reply({:ok, c, Map.put(info, :items, s.items)}, s)
    end
  end

  def handle_call(:get, _from, s), do: reply(s.character && refresh(s).character, s)

  def handle_call({:command, act, %{"rid" => rid} = payload}, _from, %{on_map: true} = s)
      when act in @item_acts do
    case s.rids do
      %{^rid => result} ->
        reply(result, s)

      _ ->
        {result, s} = run(act, payload, s)
        reply(result, remember(s, rid, result))
    end
  end

  def handle_call({:command, act, payload}, _from, %{on_map: true} = s) do
    {result, s} = run(act, payload, s)
    reply(result, s)
  end

  def handle_call({:command, _act, _payload}, _from, s), do: reply({:error, "FORBIDDEN"}, s)

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, s) do
    s = %{s | tabs: Map.delete(s.tabs, ref)}
    s = if map_size(s.tabs) == 0, do: last_tab_closed(s), else: s
    {:noreply, s, timeout(s)}
  end

  def handle_info({:map_reward, %{exp: exp, zen: zen}}, %{character: c} = s) when c != nil do
    s = refresh(s)
    {c, levels} = Engine.add_exp(s.character, exp)
    s = %{s | character: %{c | zen: c.zen + zen}}

    s =
      if levels > 0 do
        # lên cấp: hồi đầy HP/MP (G10), báo MapServer chỉ số mới
        d = Engine.derived(s.character, Inventory.equipped_templates(s.items))
        c = %{s.character | hp_current: d.hp_max, mana_current: d.mp_max}
        sync_map(%{s | character: c}, %{hp: d.hp_max, mp: d.mp_max})
      else
        s
      end

    # Zen và lên cấp ghi ngay (G12, KB_TECH_STACK §4); EXP thường đi cùng lần ghi này
    s = if zen > 0 or levels > 0, do: persist(s), else: s
    push_player(s)
    {:noreply, s, timeout(s)}
  end

  def handle_info({:map_buffs, _cid, buffs}, s) do
    s = %{s | buffs: buffs}
    if s.character, do: push_player(s)
    {:noreply, s, timeout(s)}
  end

  def handle_info({:map_died, _}, s) do
    s = refresh(s)
    push_player(s)
    {:noreply, s, timeout(s)}
  end

  def handle_info(:save, %{on_map: true} = s) do
    s = %{s | save_timer: nil} |> refresh() |> persist()
    {:noreply, schedule_save(s), timeout(s)}
  end

  def handle_info(:delayed_leave, s) do
    s = %{s | leave_timer: nil}
    s = if map_size(s.tabs) == 0, do: leave_map(s), else: s
    {:noreply, s, timeout(s)}
  end

  def handle_info(:timeout, %{tabs: tabs, leave_timer: nil} = s) when map_size(tabs) == 0,
    do: {:stop, :normal, s}

  def handle_info(_msg, s), do: {:noreply, s, timeout(s)}

  @impl true
  def terminate(_reason, s) do
    leave_map(s)
    :ok
  end

  # ---------- Lệnh ----------

  defp run("move_to", %{"x" => x, "y" => y}, s),
    do: {MapServer.move_to(s.character.map_id, s.character.id, x, y), s}

  defp run("move_to", _, s), do: {{:error, "INVALID_TARGET"}, s}

  defp run("attack", %{"target" => target} = p, s),
    do: {skill(s, "basic_attack", target, p["rid"]), s}

  defp run("attack", _, s), do: {{:error, "INVALID_TARGET"}, s}

  defp run("skill", %{"id" => id} = p, s) when is_binary(id) do
    target =
      case p do
        %{"target" => t} when is_binary(t) -> t
        %{"x" => x, "y" => y} -> {x, y}
        _ -> nil
      end

    {skill(s, id, target, p["rid"]), s}
  end

  defp run("skill", _, s), do: {{:error, "INVALID_TARGET"}, s}

  defp run("alloc", %{"stat" => stat, "points" => points}, s) do
    case Engine.alloc(refresh(s).character, stat, points) do
      {:ok, c} ->
        s = %{s | character: c} |> sync_map(%{}) |> persist()
        push_player(s)
        {:ok, s}

      error ->
        {error, s}
    end
  end

  defp run("alloc", _, s), do: {{:error, "FORBIDDEN"}, s}

  # ---------- Đồ & NPC ----------

  defp run("pickup", %{"id" => gid}, s) when is_binary(gid) do
    c = s.character

    with {:ok, g} <- MapServer.take_ground(c.map_id, c.id, gid) do
      case Items.pickup(c.id, g, "ground:" <> c.map_id) do
        {:ok, res} ->
          {:ok, s |> apply_items(res) |> notify()}

        {:error, code} ->
          # ghi DB thất bại (vd. túi đầy): đồ về lại mặt đất
          MapServer.return_ground(c.map_id, g)
          {{:error, code}, s}
      end
    else
      error -> {error, s}
    end
  end

  defp run("equip", %{"itemId" => id, "slot" => slot}, s) when is_binary(id) do
    item_result(Items.equip(refresh(s).character, id, slot), s)
  end

  defp run("unequip", %{"slot" => slot} = p, s) do
    item_result(Items.unequip(s.character.id, slot, p["toSlot"]), s)
  end

  defp run("use_item", %{"itemId" => id}, s) when is_binary(id) do
    c = s.character

    with %{location: "INVENTORY"} = it <-
           Enum.find(s.items, &(&1.id == id)) || {:error, "NOT_OWNER"},
         %{"potionType" => type} = t when type != nil <- Data.item(it.template_id),
         :ok <- MapServer.use_potion(c.map_id, c.id, t["effect"]) do
      case Items.consume(c.id, id) do
        {:ok, res} ->
          {:ok, s |> apply_items(res) |> refresh() |> notify()}

        {:error, code} ->
          Logger.error("Đã hồi máu nhưng không trừ được potion #{id}: #{code}")
          {{:error, code}, s}
      end
    else
      {:error, code} -> {{:error, code}, s}
      %{location: _} -> {{:error, "INVALID_SLOT"}, s}
      _ -> {{:error, "INVALID_TARGET"}, s}
    end
  end

  # Sắp xếp túi (P2-M1): chỉ trong INVENTORY, mỗi item một ô (P2-8)
  defp run("move_item", %{"itemId" => id, "to" => %{"location" => "INVENTORY", "slot" => to}}, s)
       when is_binary(id) do
    item_result(Items.move_item(s.character.id, id, to), s)
  end

  defp run("move_item", %{"itemId" => id, "to" => %{"location" => _}}, s) when is_binary(id),
    do: {{:error, "INVALID_SLOT"}, s}

  defp run("split", %{"itemId" => id, "quantity" => q} = p, s) when is_binary(id) do
    item_result(Items.split(s.character.id, id, q, p["toSlot"]), s)
  end

  # Vứt cả stack xuống ô đang đứng (P2-9); đã chết thì không vứt được
  defp run("drop", %{"itemId" => id}, s) when is_binary(id) do
    c = s.character

    with %{dead?: false} <- MapServer.player_state(c.map_id, c.id) || {:error, "FORBIDDEN"},
         {:ok, res} <- Items.drop(c.id, id, "ground:" <> c.map_id) do
      {:ok, _} = MapServer.drop_ground(c.map_id, c.id, res.dropped)
      {:ok, s |> apply_items(res) |> notify()}
    else
      %{dead?: true} -> {{:error, "FORBIDDEN"}, s}
      error -> {error, s}
    end
  end

  defp run("npc_open", %{"npcId" => npc}, s) do
    case near_shop(s, npc) do
      {:ok, npc_id, shop} ->
        items =
          for tid <- shop["items"], do: %{templateId: tid, price: Data.item(tid)["buyPrice"]}

        push(s, "shop", %{npcId: npc_id, name: shop["name"], items: items})
        {:ok, s}

      error ->
        {error, s}
    end
  end

  defp run("buy", %{"npcId" => npc, "templateId" => tid} = p, s) do
    qty = Map.get(p, "quantity", 1)

    with {:ok, npc_id, shop} <- near_shop(s, npc),
         %{} = t <- (tid in shop["items"] && Data.item(tid)) || {:error, "INVALID_TARGET"},
         :ok <- valid_quantity(t, qty) do
      item_result(Items.buy(s.character.id, tid, qty, t["buyPrice"], npc_id), s)
    else
      error -> {error, s}
    end
  end

  defp run("sell", %{"npcId" => npc, "itemId" => id} = p, s) when is_binary(id) do
    qty = p["quantity"]

    with {:ok, npc_id, _shop} <- near_shop(s, npc),
         %{} = it <- Enum.find(s.items, &(&1.id == id)) || {:error, "NOT_OWNER"},
         :ok <- if(is_nil(qty) or is_integer(qty), do: :ok, else: {:error, "INVALID_TARGET"}) do
      price = Data.item(it.template_id)["sellPrice"]
      item_result(Items.sell(s.character.id, id, qty, price, npc_id), s)
    else
      error -> {error, s}
    end
  end

  defp run(act, _payload, s) when act in @item_acts or act == "npc_open",
    do: {{:error, "INVALID_TARGET"}, s}

  # act khác (chat): chưa làm — DEC-16
  defp run(_act, _payload, s), do: {{:error, "FORBIDDEN"}, s}

  defp valid_quantity(t, q) do
    max = if t["stackable"], do: t["maxStack"], else: 1
    if is_integer(q) and q in 1..max, do: :ok, else: {:error, "INVALID_TARGET"}
  end

  # NPC có cửa hàng, đứng trên map của mình, trong `interaction.npcRange` ô (G4).
  # Nhận cả id dữ liệu (`lorencia_potion_merchant`) lẫn id entity (`npc_...`).
  defp near_shop(s, npc) when is_binary(npc) do
    npc_id = String.replace_prefix(npc, "npc_", "")
    map = Maps.get(s.character.map_id)

    with %{} = shop <- Data.shop(npc_id) || {:error, "INVALID_TARGET"},
         %{} = n <- Enum.find(map.npcs, &(&1.id == npc_id)) || {:error, "INVALID_TARGET"},
         %{x: x, y: y, dead?: false} <-
           MapServer.player_state(map.id, s.character.id) || {:error, "FORBIDDEN"} do
      if Pathfinding.chebyshev({x, y}, {n.x, n.y}) <= Config.get(["interaction", "npcRange"]),
        do: {:ok, npc_id, shop},
        else: {:error, "OUT_OF_RANGE"}
    else
      %{dead?: true} -> {:error, "FORBIDDEN"}
      error -> error
    end
  end

  defp near_shop(_s, _), do: {:error, "INVALID_TARGET"}

  defp item_result({:ok, res}, s), do: {:ok, s |> apply_items(res) |> notify()}
  defp item_result({:error, code}, s), do: {{:error, code}, s}

  # Đồ đọc lại + Zen/version mới từ transaction; trang bị đổi thì báo MapServer.
  defp apply_items(s, %{items: items, zen: zen, version: version}) do
    equip_changed? = Inventory.equipment(items) != Inventory.equipment(s.items)
    c = %{s.character | zen: zen, version: version}
    s = %{s | items: items, character: c, saved: %{s.saved | zen: zen, version: version}}
    if equip_changed?, do: sync_map(s, %{}), else: s
  end

  defp notify(s) do
    push_player(s)
    s
  end

  defp remember(s, rid, result) do
    order = :queue.in(rid, s.rid_order)

    if :queue.len(order) > @rid_memory do
      {{:value, old}, order} = :queue.out(order)
      %{s | rids: s.rids |> Map.delete(old) |> Map.put(rid, result), rid_order: order}
    else
      %{s | rids: Map.put(s.rids, rid, result), rid_order: order}
    end
  end

  defp push(s, event, payload) do
    for {_, pid} <- s.tabs, do: send(pid, {:push, event, payload})
    :ok
  end

  defp skill(s, id, target, rid) do
    with :ok <- Engine.can_use_skill(s.character, id) do
      MapServer.use_skill(s.character.map_id, s.character.id, id, target, rid)
    end
  end

  # ---------- Map ----------

  # Nhân vật đang giữ trùng id thì dùng luôn (không đọc lại DB, tránh mất trạng thái chưa lưu)
  defp load(%{character: %{id: id} = c}, id), do: c
  defp load(s, character_id), do: Characters.get_owned(s.account_id, character_id)

  defp kick_tabs(s, pid) do
    if Config.get(["session", "singleLoginPerAccount"]) do
      for {ref, old} <- s.tabs, old != pid do
        Process.demonitor(ref, [:flush])
        send(old, {:session_kicked, :new_login})
      end

      %{s | tabs: %{}}
    else
      s
    end
  end

  defp map_player(c, items) do
    equipment = Inventory.equipped_templates(items)

    %{
      character_id: c.id,
      name: c.name,
      class: c.class,
      level: c.level,
      hp: c.hp_current,
      mp: c.mana_current,
      x: c.position_x,
      y: c.position_y,
      stats: Engine.derived(c, equipment),
      skills: Engine.skills(c)
    }
  end

  # Báo MapServer chỉ số mới (sau lên cấp/cộng điểm), kèm `extra` (hp/mp).
  defp sync_map(%{on_map: true, character: c} = s, extra) do
    stats = Engine.derived(c, Inventory.equipped_templates(s.items))
    changes = Map.merge(%{level: c.level, stats: stats, skills: Engine.skills(c)}, extra)

    :ok = MapServer.update_player(c.map_id, c.id, changes)
    s
  end

  defp sync_map(s, _), do: s

  # Lấy vị trí/HP/MP hiện tại từ MapServer vào `character`.
  defp refresh(%{on_map: true, character: c} = s) do
    case MapServer.player_state(c.map_id, c.id) do
      nil ->
        s

      p ->
        %{
          s
          | character: %{
              c
              | position_x: p.x,
                position_y: p.y,
                hp_current: p.hp,
                mana_current: p.mp
            }
        }
    end
  end

  defp refresh(s), do: s

  defp last_tab_closed(%{on_map: true, character: c} = s) do
    case MapServer.player_state(c.map_id, c.id) do
      %{combat_remaining_ms: ms} when ms > 0 ->
        # đang combat: ở lại logoutInCombatSeconds rồi mới rời (G21)
        stay = Config.get(["session", "logoutInCombatSeconds"]) * 1000
        %{s | leave_timer: Process.send_after(self(), :delayed_leave, stay)}

      _ ->
        leave_map(s)
    end
  end

  defp last_tab_closed(s), do: s

  defp cancel_leave(%{leave_timer: nil} = s), do: s

  defp cancel_leave(s) do
    Process.cancel_timer(s.leave_timer)
    %{s | leave_timer: nil}
  end

  defp leave_map(%{on_map: true, character: c} = s) do
    if s.save_timer, do: Process.cancel_timer(s.save_timer)
    s = %{s | on_map: false, save_timer: nil}

    s =
      case MapServer.leave(c.map_id, c.id) do
        {:ok, p} ->
          %{
            s
            | character: %{
                c
                | position_x: p.x,
                  position_y: p.y,
                  hp_current: p.hp,
                  mana_current: p.mp
              }
          }

        :error ->
          s
      end

    persist(s)
  end

  defp leave_map(s), do: s

  defp persist(s) do
    case Characters.save(s.saved, s.character) do
      {:ok, saved} ->
        # giữ version mới ở cả bản đang dùng
        %{s | saved: saved, character: %{s.character | version: saved.version}}

      {:error, reason} ->
        Logger.error("Không lưu được nhân vật #{s.character.id}: #{inspect(reason)}")
        s
    end
  end

  defp push_player(s) do
    push(s, "player", Characters.player_view(s.character, s.items, s.buffs))
  end

  defp schedule_save(%{save_timer: nil} = s) do
    ms = Config.get(["session", "saveIntervalSeconds"]) * 1000
    %{s | save_timer: Process.send_after(self(), :save, ms)}
  end

  defp schedule_save(s), do: s

  defp reply(result, s), do: {:reply, result, s, timeout(s)}

  defp timeout(%{tabs: tabs, leave_timer: nil}) when map_size(tabs) == 0, do: @idle_timeout
  defp timeout(_), do: :infinity
end

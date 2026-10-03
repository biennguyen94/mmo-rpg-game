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
  (pickup, equip, unequip, move_item, split, drop, use_item, upgrade, buy, sell) idempotent theo `rid`: gửi lại cùng `rid`
  trả kết quả cũ, không làm lại. Trang bị đổi → chỉ số mới gửi MapServer.

  Tab: `session.singleLoginPerAccount` — tab mới vào thì tab cũ nhận `{:session_kicked, _}`;
  nhân vật vẫn ở trên map. Tab cuối **rời kênh có chủ ý** (đăng xuất): rời map ngay, hoặc ở
  lại `session.logoutInCombatSeconds` nếu đang combat (G21). Tab cuối **mất kết nối** (socket
  đóng, kênh lỗi): nhân vật đứng yên trên map `session.reconnectGraceSeconds`, vẫn bị đánh; vào
  lại trong hạn thì giữ nguyên vị trí, HP/MP, buff (P3-M2). Session đẩy `{:push, "player", view}`
  cho các tab khi tiến độ đổi.
  """
  use GenServer, restart: :transient
  require Logger

  alias Mu.{Chat, Guild, Party, Trade}
  alias Mu.Game.{Characters, Config, Data, Engine, Inventory, Items, Pvp, QuestStore, Quests, Rng}
  alias Mu.World.{Maps, MapServer, Pathfinding}

  # không còn tab nào trong khoảng này thì tự tắt
  @idle_timeout :timer.minutes(1)

  # act tạo/đổi item hoặc Zen: idempotent theo `rid` (KB_TECHNICAL §5)
  @item_acts ~w(pickup equip unequip move_item split drop use_item upgrade buy sell mail_claim quest_turnin)
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
      # guild (P4-M3): `%{guild_id, name, role}` hoặc `nil` (Mu.Guild báo khi đổi)
      guild: nil,
      # quest (P6-M2): `%{quest_id => %{state, progress}}` (bản trong DB) + view đã đẩy gần nhất
      quests: %{},
      quest_view: nil,
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

        # đổi sang nhân vật khác của tài khoản (P3-M5, 4 nhân vật): nhân vật cũ rời map + nhóm
        s = if s.character && s.character.id != character.id, do: go_offline(s), else: s

        s =
          if s.saved && s.saved.id == character.id,
            do: s,
            else: %{
              s
              | saved: character,
                items: Items.load(character.id),
                quests: QuestStore.load(character.id),
                quest_view: nil
            }

        # PK giảm theo giờ thực khi vắng mặt (P4-3)
        s = kick_tabs(%{s | character: pk_decay(character)}, pid)
        register_name(character.name)
        # guild (P4-M3): báo online, lấy membership (tên guild trên đầu)
        s = %{s | guild: Guild.online(%{cid: character.id, name: character.name})}
        # nhóm: vào lại trong hạn reconnect → online (P3-M4)
        Party.update(character.id, %{
          online: true,
          level: character.level,
          map_id: character.map_id
        })

        s = %{s | tabs: Map.put(s.tabs, Process.monitor(pid), pid)}

        {:ok, info} =
          MapServer.join(character.map_id, map_player(s.character, s.items, s.guild), self())

        c = %{
          s.character
          | position_x: info.x,
            position_y: info.y,
            hp_current: info.hp,
            mana_current: info.mp
        }

        s = %{s | character: c, on_map: true} |> schedule_save()
        # buff còn trên map khi vào lại trong hạn reconnect (P3-M2)
        reply({:ok, c, Map.merge(info, %{items: s.items, buffs: s.buffs})}, s)
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
  def handle_info({:DOWN, ref, :process, _pid, reason}, s) do
    s = %{s | tabs: Map.delete(s.tabs, ref)}
    s = if map_size(s.tabs) == 0, do: last_tab_closed(s, reason), else: s
    {:noreply, s, timeout(s)}
  end

  def handle_info({:map_reward, %{exp: exp, zen: zen} = r}, %{character: c} = s) when c != nil do
    s = s |> quest_kill(r[:template]) |> gain(exp, zen)
    {:noreply, s, timeout(s)}
  end

  def handle_info({:map_buffs, _cid, buffs}, s) do
    s = %{s | buffs: buffs}
    if s.character, do: push_player(s)
    {:noreply, s, timeout(s)}
  end

  # có mail mới (quản trị gửi khi đang online): cập nhật badge (P2-M6)
  def handle_info({:mail_changed, cid}, %{character: %{id: cid}} = s) do
    push(s, "mail", %{unread: Mu.Mail.unread(cid)})
    {:noreply, s, timeout(s)}
  end

  def handle_info({:mail_changed, _}, s), do: {:noreply, s, timeout(s)}

  # MapServer đẩy riêng cho người chơi này (duel, P4-M2)
  def handle_info({:map_push, event, payload}, s) do
    push(s, event, payload)
    {:noreply, s, timeout(s)}
  end

  # Nhóm (P3-M4): `party`, `party_invite`, chat PARTY / thông báo nhóm
  def handle_info({:party_push, event, payload}, s) do
    push(s, event, payload)
    {:noreply, s, timeout(s)}
  end

  # Giao dịch (P5-M4): `trade`, `trade_invite`
  def handle_info({:trade_push, event, payload}, s) do
    push(s, event, payload)
    {:noreply, s, timeout(s)}
  end

  # giao dịch đã chốt (một transaction ở `Items.trade/3`): đồ + Zen mới
  def handle_info({:trade_done, res}, %{character: c} = s) when c != nil do
    {:noreply, s |> apply_items(res) |> notify(), timeout(s)}
  end

  # Guild (P4-M3): `guild`, `guild_invite`, chat GUILD / thông báo guild
  def handle_info({:guild_push, event, payload}, s) do
    push(s, event, payload)
    {:noreply, s, timeout(s)}
  end

  # vào / rời / bị đuổi / giải tán: tên guild trên đầu đổi (MapServer phát lại `spawn`)
  def handle_info({:guild_changed, m}, s) do
    s = %{s | guild: m}

    if s.on_map,
      do: MapServer.update_player(s.character.map_id, s.character.id, %{guild: m && m.name})

    {:noreply, s, timeout(s)}
  end

  # WHISPER từ người khác (P2-M5)
  def handle_info({:chat_whisper, msg}, s) do
    push(s, "chat", msg)
    {:noreply, s, timeout(s)}
  end

  # Bước vào cổng (P2-M4): đủ cấp thì chuyển map, thiếu thì báo lỗi và đứng lại
  def handle_info({:map_portal, _cid, portal}, %{on_map: true, character: c} = s) do
    if c.level < portal.level_required do
      push(s, "error", %{
        rid: nil,
        error: "REQUIREMENT_NOT_MET",
        reason: "portal",
        map: portal.to,
        levelRequired: portal.level_required
      })

      {:noreply, s, timeout(s)}
    else
      {:noreply, change_map(s, portal.to, {portal.to_x, portal.to_y}), timeout(s)}
    end
  end

  def handle_info({:map_portal, _, _}, s), do: {:noreply, s, timeout(s)}

  def handle_info({:map_died, _}, s) do
    # chết: hủy giao dịch đang mở (P5-M4)
    if s.character, do: Trade.close(s.character.id, "dead")
    s = refresh(s)
    push_player(s)
    {:noreply, s, timeout(s)}
  end

  def handle_info(:save, %{on_map: true} = s) do
    s = %{s | save_timer: nil} |> refresh() |> decay_online() |> persist()
    {:noreply, schedule_save(s), timeout(s)}
  end

  # Giết người NORMAL (P4-M1): +điểm PK, ghi DB ngay, báo MapServer (màu tên) và tab
  def handle_info({:map_pk, _cid, n}, %{on_map: true, character: c} = s) do
    c = %{c | pk_points: c.pk_points + n, last_pk_at: DateTime.utc_now()}
    s = %{s | character: c} |> refresh() |> persist()
    MapServer.update_player(c.map_id, c.id, %{pk_points: c.pk_points})
    push_player(s)
    {:noreply, s, timeout(s)}
  end

  # Bị người chơi giết, trúng tỉ lệ rơi đồ theo trạng thái PK (P4-3): 1 món ngẫu nhiên trong túi
  # rơi xuống chỗ chết, kẻ giết được loot protect (đường `drop`: một transaction, audit, giữ serial)
  def handle_info({:map_pk_drop, _cid, killer}, %{on_map: true, character: c} = s) do
    case Inventory.inventory(s.items) do
      [] ->
        {:noreply, s, timeout(s)}

      bag ->
        it = Enum.random(bag)

        s =
          case Items.drop(c.id, it.id, "pk:" <> c.map_id) do
            {:ok, res} ->
              {:ok, _} = MapServer.drop_ground(c.map_id, c.id, res.dropped, killer)
              name = (Data.item(it.template_id) || %{})["name"] || it.template_id
              push(s, "chat", Chat.message("SYSTEM", "Hệ thống", "Bạn bị rơi #{name} khi chết."))
              s |> apply_items(res) |> notify()

            {:error, code} ->
              Logger.warning("Không rơi được đồ PK #{it.id}: #{code}")
              s
          end

        {:noreply, s, timeout(s)}
    end
  end

  def handle_info(:delayed_leave, s) do
    s = %{s | leave_timer: nil}
    s = if map_size(s.tabs) == 0, do: go_offline(s), else: s
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

  # Ép jewel lên đồ trong túi (P5-M2, P5-3 / P5-4): RNG mới mỗi lần (server quyết định), kết quả
  # đẩy event `upgrade` + `player`; thành công lên ≥ `upgrade.announceFromLevel` → SYSTEM cả map
  defp run("upgrade", %{"itemId" => id, "jewelId" => jewel}, s)
       when is_binary(id) and is_binary(jewel) do
    case Items.upgrade(s.character.id, id, jewel, Rng.new()) do
      {:ok, %{upgrade: u} = res} ->
        s = s |> apply_items(res) |> notify()

        push(s, "upgrade", %{
          itemId: u.item_id,
          templateId: u.template_id,
          jewel: u.jewel,
          ok: u.ok,
          level: u.level,
          option: u.option,
          destroyed: u.destroyed
        })

        announce_upgrade(s, u)
        {:ok, s}

      error ->
        {error, s}
    end
  end

  defp run("upgrade", _p, s), do: {{:error, "INVALID_TARGET"}, s}

  # Sắp xếp túi (P2-M1): trong INVENTORY, mỗi item một ô (P2-8). Kho (P3-M3): nguồn hoặc đích
  # là WAREHOUSE → phải đứng cạnh Thủ kho (`npcRange`), `Items.transfer/4`, đẩy `warehouse`
  defp run("move_item", %{"itemId" => id, "to" => %{"location" => loc, "slot" => to}}, s)
       when is_binary(id) and loc in ~w(INVENTORY WAREHOUSE) do
    in_bag? = Enum.any?(s.items, &(&1.id == id))

    if loc == "INVENTORY" and in_bag? do
      item_result(Items.move_item(s.character.id, id, to), s)
    else
      with {:ok, npc_id} <- near_warehouse(s),
           {:ok, res} <- Items.transfer(s.character.id, s.account_id, id, {loc, to}) do
        s = s |> apply_items(res) |> notify()
        push_warehouse(s, npc_id, res.warehouse)
        {:ok, s}
      else
        error -> {error, s}
      end
    end
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

  defp run("npc_open", %{"npcId" => npc}, s) when is_binary(npc) do
    npc_id = String.replace_prefix(npc, "npc_", "")

    case Enum.find(Maps.get(s.character.map_id).npcs, &(&1.id == npc_id)) do
      %{role: "warehouse"} -> open_warehouse(s, npc_id)
      %{role: "quest"} -> open_quests(s, npc_id)
      _ -> open_shop(s, npc)
    end
  end

  defp run("npc_open", _payload, s), do: {{:error, "INVALID_TARGET"}, s}

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

  # ---------- Hộp thư (P2-M6) ----------

  # mở panel: danh sách + đánh dấu đã đọc (badge về 0)
  defp run("mail_list", _payload, s) do
    items = Mu.Mail.list(s.character.id)
    push(s, "mail", %{unread: 0, items: items})
    {:ok, s}
  end

  defp run("mail_claim", %{"mailId" => id}, s) when is_binary(id) do
    case Items.claim_mail(s.character.id, id) do
      {:ok, res} ->
        s = s |> apply_items(res) |> notify()

        push(s, "mail", %{
          unread: Mu.Mail.unread(s.character.id),
          items: Mu.Mail.list(s.character.id)
        })

        {:ok, s}

      error ->
        {error, s}
    end
  end

  defp run("mail_delete", p, s) do
    target = if p["read"] == true, do: :read, else: p["mailId"]

    case Mu.Mail.delete(s.character.id, target) do
      {:ok, _} ->
        push(s, "mail", %{
          unread: Mu.Mail.unread(s.character.id),
          items: Mu.Mail.list(s.character.id)
        })

        {:ok, s}

      error ->
        {error, s}
    end
  end

  defp run(act, _payload, s)
       when (act in @item_acts and act != "quest_turnin") or act == "npc_open",
       do: {{:error, "INVALID_TARGET"}, s}

  # ---------- Chat (P2-M5) ----------

  defp run("chat", %{"channel" => ch, "text" => text} = p, s) when is_binary(ch) do
    c = s.character

    with :ok <- chat_channel(ch),
         {:ok, text} <- Chat.clean(text),
         :ok <- not_muted(s, c.name) do
      text = Chat.filter(text)

      case ch do
        "NORMAL" ->
          Chat.say(c.map_id, c.name, text)
          {:ok, s}

        "WHISPER" ->
          whisper(s, p["to"], text)

        "PARTY" ->
          {Party.chat(c.id, Chat.message("PARTY", c.name, text)), s}

        "GUILD" ->
          {Guild.chat(c.id, Chat.message("GUILD", c.name, text)), s}
      end
    else
      error -> {error, s}
    end
  end

  defp run("chat", _payload, s), do: {{:error, "INVALID_TARGET"}, s}

  # ---------- Duel (P4-M2, P4-4): trạng thái ở MapServer (hai người cùng map) ----------

  defp run("duel_request", %{"to" => to}, s) when is_binary(to),
    do: {MapServer.duel(s.character.map_id, s.character.id, :request, to), s}

  defp run("duel_accept", %{"from" => from}, s) when is_binary(from),
    do: {MapServer.duel(s.character.map_id, s.character.id, :accept, from), s}

  defp run("duel_decline", %{"from" => from}, s) when is_binary(from),
    do: {MapServer.duel(s.character.map_id, s.character.id, :decline, from), s}

  defp run("duel_cancel", _p, s),
    do: {MapServer.duel(s.character.map_id, s.character.id, :cancel), s}

  defp run("duel_" <> _, _p, s), do: {{:error, "INVALID_TARGET"}, s}

  # ---------- Nhóm (P3-M4, P3-5) ----------

  defp run("party_invite", %{"to" => to}, s) when is_binary(to),
    do: {Party.invite(party_me(s), to), s}

  defp run("party_accept", %{"from" => from}, s) when is_binary(from),
    do: {Party.accept(party_me(s), from), s}

  defp run("party_decline", %{"from" => from}, s) when is_binary(from),
    do: {Party.decline(party_me(s), from), s}

  defp run("party_leave", _p, s), do: {Party.leave(s.character.id), s}

  defp run("party_kick", %{"name" => name}, s) when is_binary(name),
    do: {Party.kick(s.character.id, name), s}

  defp run("party_disband", _p, s), do: {Party.disband(s.character.id), s}

  defp run("party_" <> _, _p, s), do: {{:error, "INVALID_TARGET"}, s}

  # ---------- Guild (P4-M3, P4-5): DB `Mu.Guilds`, luật + lời mời ở `Mu.Guild` ----------

  defp run("guild_create", %{"name" => name}, s) when is_binary(name) do
    case Guild.create(s.character.id, name) do
      {:ok, %{zen: zen, version: version}} ->
        c = %{s.character | zen: zen, version: version}
        s = %{s | character: c, saved: %{s.saved | zen: zen, version: version}}
        push_player(s)
        {:ok, s}

      error ->
        {error, s}
    end
  end

  defp run("guild_invite", %{"to" => to}, s) when is_binary(to),
    do: {Guild.invite(s.character.id, to), s}

  defp run("guild_accept", %{"guild" => g}, s) when is_binary(g),
    do: {Guild.accept(s.character.id, g), s}

  defp run("guild_decline", %{"guild" => g}, s) when is_binary(g),
    do: {Guild.decline(s.character.id, g), s}

  defp run("guild_leave", _p, s), do: {Guild.leave(s.character.id), s}

  defp run("guild_kick", %{"name" => name}, s) when is_binary(name),
    do: {Guild.kick(s.character.id, name), s}

  defp run("guild_promote", %{"name" => name}, s) when is_binary(name),
    do: {Guild.promote(s.character.id, name), s}

  defp run("guild_demote", %{"name" => name}, s) when is_binary(name),
    do: {Guild.demote(s.character.id, name), s}

  defp run("guild_disband", _p, s), do: {Guild.disband(s.character.id), s}

  # ---------- Xếp hạng (P6-M1, P6-7) ----------

  defp run("ranking", %{"board" => board}, s) when is_binary(board) do
    case Mu.Leaderboard.get(board, s.character.id) do
      {:ok, view} ->
        push(s, "ranking", view)
        {:ok, s}

      error ->
        {error, s}
    end
  end

  defp run("ranking", _p, s), do: {{:error, "INVALID_TARGET"}, s}

  # ---------- Quest (P6-M2, P6-2): luật `Quests`, DB `QuestStore` / `Items.quest_turnin` ----------

  defp run("quest_" <> _ = act, p, s) do
    if quest_enabled?(), do: quest(act, p, s), else: {{:error, "FORBIDDEN"}, s}
  end

  # ---------- Giao dịch (P5-M4, P5-5): trạng thái trong `Mu.Trade.Settlement` ----------

  defp run("trade_request", %{"to" => to}, s) when is_binary(to) do
    c = s.character

    with {:ok, t} <- MapServer.near_player(c.map_id, c.id, to, Config.get(["trade", "range"])) do
      {Trade.request(
         trade_me(s),
         %{cid: t.character_id, name: t.name, session: t.session},
         c.map_id
       ), s}
    else
      error -> {error, s}
    end
  end

  defp run("trade_accept", %{"from" => from}, s) when is_binary(from) do
    c = s.character

    with {:ok, _} <- MapServer.near_player(c.map_id, c.id, from, Config.get(["trade", "range"])) do
      {Trade.accept(trade_me(s), from), s}
    else
      error -> {error, s}
    end
  end

  defp run("trade_decline", %{"from" => from}, s) when is_binary(from),
    do: {Trade.decline(s.character.id, from), s}

  # cả stack, đồ trong túi (không đồ đang mặc / trong kho)
  defp run("trade_put", %{"itemId" => id}, s) when is_binary(id) do
    case Enum.find(s.items, &(&1.id == id)) do
      %{location: "INVENTORY"} = it -> {Trade.put(s.character.id, Characters.item_view(it)), s}
      %{} -> {{:error, "INVALID_SLOT"}, s}
      nil -> {{:error, "NOT_OWNER"}, s}
    end
  end

  defp run("trade_take", %{"itemId" => id}, s) when is_binary(id),
    do: {Trade.take(s.character.id, id), s}

  defp run("trade_zen", %{"amount" => n}, s) when is_integer(n) and n >= 0 do
    if n <= s.character.zen,
      do: {Trade.zen(s.character.id, n), s},
      else: {{:error, "NOT_ENOUGH_ZEN"}, s}
  end

  defp run("trade_lock", _p, s), do: {Trade.lock(s.character.id), s}
  defp run("trade_confirm", _p, s), do: {Trade.confirm(s.character.id), s}
  defp run("trade_cancel", _p, s), do: {Trade.cancel(s.character.id), s}
  defp run("trade_" <> _, _p, s), do: {{:error, "INVALID_TARGET"}, s}

  # Guild war (P4-M4, P4-6): trạng thái trong `Mu.Guild` (RAM)
  defp run("guild_war_declare", %{"guild" => g}, s) when is_binary(g),
    do: {Guild.war(s.character.id, :declare, g), s}

  defp run("guild_war_accept", %{"guild" => g}, s) when is_binary(g),
    do: {Guild.war(s.character.id, :accept, g), s}

  defp run("guild_war_decline", %{"guild" => g}, s) when is_binary(g),
    do: {Guild.war(s.character.id, :decline, g), s}

  defp run("guild_war_surrender", _p, s), do: {Guild.war_surrender(s.character.id), s}

  defp run("guild_" <> _, _p, s), do: {{:error, "INVALID_TARGET"}, s}

  defp run(_act, _payload, s), do: {{:error, "FORBIDDEN"}, s}

  defp quest("quest_list", _p, s), do: {:ok, sync_quests(%{s | quest_view: nil})}

  # nhận / trả: đứng cạnh Quest Master (bất kỳ, Lorencia / Noria) trong `npcRange`
  defp quest("quest_accept", %{"questId" => qid, "npcId" => npc}, s)
       when is_binary(qid) and is_binary(npc) do
    c = s.character

    with {:ok, _} <- near_npc(s, npc, "quest"),
         :ok <- Quests.can_accept(qid, c.level, s.quests),
         :ok <- QuestStore.accept(c.id, qid) do
      s = %{s | quests: Map.put(s.quests, qid, %{state: "ACTIVE", progress: %{}})}
      {:ok, sync_quests(s)}
    else
      error -> {error, s}
    end
  end

  defp quest("quest_turnin", %{"questId" => qid, "npcId" => npc}, s)
       when is_binary(qid) and is_binary(npc) do
    with %{} = q <- Data.quest(qid) || {:error, "INVALID_TARGET"},
         {:ok, _} <- near_npc(s, npc, "quest"),
         {:ok, res} <-
           Items.quest_turnin(s.character.id, q, &Quests.complete?(q, &1, &2, &3)) do
      s = %{s | quests: Map.put(s.quests, qid, %{state: "DONE", progress: %{}})}
      s = s |> apply_items(res) |> gain(q["rewards"]["exp"], 0) |> persist()
      push(s, "quest_done", %{questId: qid, name: q["name"], rewards: q["rewards"]})
      {:ok, s}
    else
      error -> {error, s}
    end
  end

  defp quest("quest_abandon", %{"questId" => qid}, s) when is_binary(qid) do
    case QuestStore.abandon(s.character.id, qid) do
      :ok -> {:ok, sync_quests(%{s | quests: Map.delete(s.quests, qid)})}
      error -> {error, s}
    end
  end

  defp quest(_act, _p, s), do: {{:error, "INVALID_TARGET"}, s}

  # PARTY: từ P3-M4 (không có nhóm → INVALID_TARGET); GUILD: từ P4-M3 (không có guild →
  # INVALID_TARGET); SYSTEM: chỉ server
  defp chat_channel(ch) when ch in ~w(NORMAL WHISPER PARTY GUILD), do: :ok
  defp chat_channel("SYSTEM"), do: {:error, "FORBIDDEN"}
  defp chat_channel(_), do: {:error, "INVALID_TARGET"}

  # bị cấm chat: FORBIDDEN + một dòng SYSTEM cho chính người đó biết lý do
  defp not_muted(s, name) do
    case Chat.muted_until(name) do
      nil ->
        :ok

      until ->
        text =
          if until == :infinity,
            do: "Bạn đang bị cấm chat.",
            else:
              "Bạn đang bị cấm chat tới #{DateTime.from_unix!(until) |> Calendar.strftime("%H:%M %d/%m")} (UTC)."

        push(s, "chat", Chat.message("SYSTEM", Config.get(["chat", "systemName"]), text))
        {:error, "FORBIDDEN"}
    end
  end

  defp announce_upgrade(s, %{ok: true, jewel: jewel, level: level} = u) do
    if jewel != Config.get(["upgrade", "life", "jewel"]) and
         level >= Config.get(["upgrade", "announceFromLevel"]) do
      name = Data.item(u.template_id)["name"]
      Chat.system_map(s.character.map_id, "#{s.character.name} ép thành công #{name} +#{level}!")
    end
  end

  defp announce_upgrade(_s, _u), do: :ok

  defp quest_enabled?, do: Config.get(["features", "quest"]) == true

  # Hạ quái `template` (P6-M2): quest đang làm có mục tiêu kill quái này → +1, ghi DB
  defp quest_kill(s, nil), do: s

  defp quest_kill(s, template) do
    case Quests.on_kill(s.quests, template) do
      [] ->
        s

      changed ->
        Enum.reduce(changed, s, fn {qid, pr}, s ->
          :ok = QuestStore.save_progress(s.character.id, qid, pr)
          put_in(s.quests[qid].progress, pr)
        end)
    end
  end

  # Đẩy event `quests` khi view đổi (tiến độ kill, cấp, đồ trong túi cho collect)
  defp sync_quests(%{character: c} = s) when c != nil do
    if quest_enabled?() do
      view = Quests.view(s.quests, c.level, s.items)

      if view != s.quest_view do
        push(s, "quests", view)
        %{s | quest_view: view}
      else
        s
      end
    else
      s
    end
  end

  defp sync_quests(s), do: s

  # Mở Quest Master: event `quests` kèm `npcId` (client mở hộp thoại nhận / trả)
  defp open_quests(s, npc) do
    with true <- quest_enabled?() || {:error, "FORBIDDEN"},
         {:ok, npc_id} <- near_npc(s, npc, "quest") do
      view = Quests.view(s.quests, s.character.level, s.items)
      push(s, "quests", Map.put(view, :npcId, npc_id))
      {:ok, %{s | quest_view: view}}
    else
      error -> {error, s}
    end
  end

  defp trade_me(%{character: c}), do: %{cid: c.id, name: c.name, session: self()}

  defp party_me(%{character: c}),
    do: %{cid: c.id, name: c.name, class: c.class, level: c.level, map_id: c.map_id}

  defp whisper(s, to, text) when is_binary(to) do
    me = s.character.name

    case Registry.lookup(Mu.Game.NameRegistry, String.downcase(to)) do
      [{pid, target}] when pid != self() ->
        msg = Chat.message("WHISPER", me, text)
        send(pid, {:chat_whisper, msg})
        push(s, "chat", Map.put(msg, :to, target))
        {:ok, s}

      _ ->
        {{:error, "INVALID_TARGET"}, s}
    end
  end

  defp whisper(s, _to, _text), do: {{:error, "INVALID_TARGET"}, s}

  # tên nhân vật → Session này (giá trị: tên đúng hoa thường để hiện ở bản sao người gửi)
  defp register_name(name) do
    for key <- Registry.keys(Mu.Game.NameRegistry, self()),
        do: Registry.unregister(Mu.Game.NameRegistry, key)

    Registry.register(Mu.Game.NameRegistry, String.downcase(name), name)
  end

  defp valid_quantity(t, q) do
    max = if t["stackable"], do: t["maxStack"], else: 1
    if is_integer(q) and q in 1..max, do: :ok, else: {:error, "INVALID_TARGET"}
  end

  # ---------- Cửa hàng / Kho (NPC) ----------

  defp open_shop(s, npc) do
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

  # Mở kho (P3-M3): đứng cạnh Thủ kho → event `warehouse` (đồ trong kho của tài khoản)
  defp open_warehouse(s, npc) do
    with {:ok, npc_id} <- near_npc(s, npc, "warehouse") do
      push_warehouse(s, npc_id, Items.load_warehouse(s.account_id))
      {:ok, s}
    else
      error -> {error, s}
    end
  end

  defp push_warehouse(s, npc_id, items) do
    push(s, "warehouse", %{
      npcId: npc_id,
      slots: Inventory.warehouse_slots(),
      items: Enum.map(items, &Characters.item_view/1)
    })
  end

  # Thủ kho gần nhất trong `npcRange` trên map hiện tại
  defp near_warehouse(s) do
    map = Maps.get(s.character.map_id)

    case Enum.find(map.npcs, &(&1.role == "warehouse")) do
      nil -> {:error, "OUT_OF_RANGE"}
      n -> near_npc(s, n.id, "warehouse")
    end
  end

  # NPC `role` trên map của mình, trong `interaction.npcRange` ô (G4); nhận id dữ liệu hoặc id
  # entity (`npc_...`)
  defp near_npc(s, npc, role) do
    npc_id = String.replace_prefix(npc, "npc_", "")
    map = Maps.get(s.character.map_id)

    with :ok <- not_murderer(s),
         %{} = n <-
           Enum.find(map.npcs, &(&1.id == npc_id and &1.role == role)) ||
             {:error, "INVALID_TARGET"},
         %{x: x, y: y, dead?: false} <-
           MapServer.player_state(map.id, s.character.id) || {:error, "FORBIDDEN"} do
      if Pathfinding.chebyshev({x, y}, {n.x, n.y}) <= Config.get(["interaction", "npcRange"]),
        do: {:ok, npc_id},
        else: {:error, "OUT_OF_RANGE"}
    else
      %{dead?: true} -> {:error, "FORBIDDEN"}
      error -> error
    end
  end

  # NPC có cửa hàng, đứng trên map của mình, trong `interaction.npcRange` ô (G4).
  # Nhận cả id dữ liệu (`lorencia_potion_merchant`) lẫn id entity (`npc_...`).
  # MURDERER không dùng được NPC (shop, kho) — P4-3
  defp not_murderer(s) do
    if Pvp.state(s.character.pk_points) == "MURDERER", do: {:error, "FORBIDDEN"}, else: :ok
  end

  # Giảm PK theo giờ thực (`Pvp.decay/3`); đổi thì cột PK được ghi ở lần `persist` kế tiếp
  defp pk_decay(c) do
    {points, last} = Pvp.decay(c.pk_points, c.last_pk_at, DateTime.utc_now())
    %{c | pk_points: points, last_pk_at: last}
  end

  # khi đang online (mỗi lần lưu định kỳ): giảm, đổi thì báo MapServer + tab
  defp decay_online(%{character: c} = s) do
    c2 = pk_decay(c)

    if c2.pk_points != c.pk_points do
      MapServer.update_player(c2.map_id, c2.id, %{pk_points: c2.pk_points})
      s = %{s | character: c2}
      push_player(s)
      s
    else
      %{s | character: c2}
    end
  end

  defp near_shop(s, npc) when is_binary(npc) do
    npc_id = String.replace_prefix(npc, "npc_", "")
    map = Maps.get(s.character.map_id)

    with :ok <- not_murderer(s),
         %{} = shop <- Data.shop(npc_id) || {:error, "INVALID_TARGET"},
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
    # đồ trên bàn giao dịch không còn trong túi (bán, vứt, mặc, cất kho…) thì gỡ khỏi bàn
    Trade.sync(s.character.id, items)
    equip_changed? = Inventory.equipment(items) != Inventory.equipment(s.items)
    c = %{s.character | zen: zen, version: version}
    s = %{s | items: items, character: c, saved: %{s.saved | zen: zen, version: version}}
    if equip_changed?, do: sync_map(s, %{}), else: s
  end

  defp notify(s) do
    push_player(s)
    sync_quests(s)
  end

  # EXP + Zen (hạ quái, P6-M2 thưởng quest): lên cấp hồi đầy, ghi ngay khi có Zen / lên cấp
  defp gain(s, exp, zen) do
    s = refresh(s)
    {c, levels} = Engine.add_exp(s.character, exp)
    s = %{s | character: %{c | zen: c.zen + zen}}

    s =
      if levels > 0 do
        # lên cấp: hồi đầy HP/MP (G10), báo MapServer chỉ số mới
        d = Engine.derived(s.character, Inventory.equipped_templates(s.items))
        c = %{s.character | hp_current: d.hp_max, mana_current: d.mp_max}
        Party.update(c.id, %{level: c.level})
        sync_map(%{s | character: c}, %{hp: d.hp_max, mp: d.mp_max})
      else
        s
      end

    # Zen và lên cấp ghi ngay (G12, KB_TECH_STACK §4); EXP thường đi cùng lần ghi này
    s = if zen > 0 or levels > 0, do: persist(s), else: s
    push_player(s)
    sync_quests(s)
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

  defp map_player(c, items, guild) do
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
      skills: Engine.skills(c),
      pk_points: c.pk_points,
      guild: guild && guild.name
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

  # Rời có chủ ý (client `leave` kênh khi đăng xuất): ngay, hoặc sau logoutInCombatSeconds nếu
  # đang combat (G21)
  defp last_tab_closed(%{on_map: true, character: c} = s, {:shutdown, :left}) do
    case MapServer.player_state(c.map_id, c.id) do
      %{combat_remaining_ms: ms} when ms > 0 ->
        # đang combat: ở lại logoutInCombatSeconds rồi mới rời (G21)
        stay = Config.get(["session", "logoutInCombatSeconds"]) * 1000
        %{s | leave_timer: Process.send_after(self(), :delayed_leave, stay)}

      _ ->
        go_offline(s)
    end
  end

  # Mất kết nối (socket đóng: mạng rớt, đóng tab, kênh lỗi): nhân vật đứng yên trên map
  # `reconnectGraceSeconds`, vẫn bị đánh; vào lại trong hạn thì tiếp tục (KB_TECHNICAL §4, P3-M2)
  defp last_tab_closed(%{on_map: true, character: c} = s, _reason) do
    MapServer.halt(c.map_id, c.id)

    # KB_TECHNICAL §10: mất kết nối → hủy giao dịch ngay, không chờ reconnectGraceSeconds
    Trade.close(c.id, "disconnect")
    Party.update(c.id, %{online: false})
    grace = Config.get(["session", "reconnectGraceSeconds"]) * 1000
    %{s | leave_timer: Process.send_after(self(), :delayed_leave, grace)}
  end

  defp last_tab_closed(s, _reason), do: s

  # Nhân vật rời game hẳn (đăng xuất / hết hạn reconnect): rời map, rời nhóm (P3-5 (6))
  defp go_offline(%{character: %{id: cid}} = s) do
    Trade.close(cid, "disconnect")
    s = leave_map(s)
    Party.leave(cid)
    Guild.offline(cid)
    %{s | guild: nil}
  end

  defp go_offline(s), do: s

  defp cancel_leave(%{leave_timer: nil} = s), do: s

  defp cancel_leave(s) do
    Process.cancel_timer(s.leave_timer)
    %{s | leave_timer: nil}
  end

  defp leave_map(%{on_map: true, character: c} = s) do
    if s.save_timer, do: Process.cancel_timer(s.save_timer)
    # buff chỉ sống trên map (DEC-66)
    s = %{s | on_map: false, save_timer: nil, buffs: []}

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

  # Rời map cũ (lưu), vào map mới ở (x, y), lưu ngay `map_id`; các tab nhận `{:map_changed, ...}`
  # để kênh đổi topic PubSub và đẩy `map_change` (P2-M4). Buff mất khi đổi map.
  defp change_map(s, map_id, {x, y}) do
    old = s.character.map_id
    Trade.close(s.character.id, "map")
    s = leave_map(s)
    c = %{s.character | map_id: map_id, position_x: x, position_y: y}
    {:ok, info} = MapServer.join(map_id, map_player(c, s.items, s.guild), self())

    c = %{c | position_x: info.x, position_y: info.y, hp_current: info.hp, mana_current: info.mp}
    s = %{s | character: c, on_map: true, buffs: []} |> persist() |> schedule_save()

    payload = %{
      map: Maps.client_data(Maps.get(map_id)),
      entityId: info.entity_id,
      player: Characters.player_view(s.character, s.items, [])
    }

    for {_, pid} <- s.tabs, do: send(pid, {:map_changed, old, map_id, payload, info.entities})
    Party.update(c.id, %{map_id: map_id})
    s
  end

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

defmodule MuWeb.GameChannel do
  @moduledoc """
  Kênh `"game"` (`KB_TECHNICAL §5`). Khung join → gắn Session lấy từ
  `HacLongWeb.GameChannel`; bỏ mọi kênh phụ của repo nền.

  - `join("game", %{"clientVersion", "characterId"})`: `clientVersion` phải bằng
    `server.clientVersion` (P7), nhân vật phải thuộc tài khoản. Sai → `{error: "FORBIDDEN",
    reason}`. Đúng → `%{player, entityId, map, config, data: %{items}}` (`data.items`: template
    item để client hiển thị/tra icon).
  - `"cmd"` `{act, rid, ...}`: thành công trả reply `{:ok, %{rid}}`; lỗi trả reply
    `{:error, %{rid, error}}` **và** đẩy event `"error"` `{rid, error}` (P2).
  - Giới hạn tần suất theo nhóm `act` (P8): vượt → `RATE_LIMITED`; vượt liên tục
    `rateLimit.cmd.kickAfterMs` → đóng kênh.
  - Sau join, kênh đẩy `"spawn"` cho mọi entity **trong tầm nhìn** rồi chuyển tiếp `spawn` /
    `despawn` / `snapshot` / `combat` của MapServer (PubSub) qua bộ lọc AOI `MuWeb.Aoi`
    (P3-M1, `KB_TECHNICAL §3`): vào / ra tầm nhìn = `spawn` / `despawn`. Kênh đăng ký topic
    trước khi vào map nên có thể nhận `spawn` hai lần: client coi `spawn` là
    thêm-hoặc-cập-nhật.
  - `"player"` (trạng thái đầy đủ + `view`) do Session đẩy khi EXP/level/stat/Zen đổi;
    `"combat"` `{rid, attacker, target, dmg, crit, hp}` cho mọi đòn trên map (trượt: dmg 0).
  - Guild (P4-M3): Session đẩy `guild` (`{id, name, master, members}`; không có guild thì
    `id` null, `members` rỗng) và `guild_invite` `{from, guild}`; `spawn` người chơi có `guild`.
    Guild war (P4-M4): `guild_war` (`Mu.Guild`).
  - Tab khác của cùng tài khoản vào game → kênh này nhận `{:session_kicked, _}`, đẩy
    `"error"` `FORBIDDEN` rồi đóng (`session.singleLoginPerAccount`).
  - Kênh kết thúc vì client `leave` (đăng xuất) hay vì socket đóng (mất kết nối) quyết định
    Session cho nhân vật rời map ngay hay giữ `reconnectGraceSeconds` (P3-M2, `Mu.Game.Session`).
  """
  use MuWeb, :channel

  alias Mu.Game.{Characters, Commands, Config, Session}
  alias Mu.World.{Maps, MapServer}
  alias MuWeb.Aoi

  @impl true
  def join("game", %{"clientVersion" => version, "characterId" => character_id}, socket) do
    account_id = socket.assigns.account_id

    cond do
      version != Config.get(["server", "clientVersion"]) ->
        {:error, %{error: "FORBIDDEN", reason: "clientVersion"}}

      true ->
        # map của nhân vật chỉ biết sau khi Session nạp; Phase 1 chỉ có các map trong Maps
        for id <- Maps.ids(), do: Phoenix.PubSub.subscribe(Mu.PubSub, MapServer.topic(id))

        case Session.attach(account_id, character_id, self()) do
          {:ok, character, info} ->
            for id <- Maps.ids(),
                id != character.map_id,
                do: Phoenix.PubSub.unsubscribe(Mu.PubSub, MapServer.topic(id))

            send(self(), :after_join)

            reply = %{
              player: Characters.player_view(character, info.items, info.buffs),
              entityId: info.entity_id,
              map: Maps.client_data(Maps.get(character.map_id)),
              config: client_config(),
              data: %{items: client_items(), skills: client_skills()}
            }

            {:ok, reply,
             assign(socket,
               character_id: character.id,
               limit_streak: nil,
               aoi: Aoi.new(info.entity_id, info.entities)
             )}

          {:error, :not_found} ->
            {:error, %{error: "FORBIDDEN", reason: "character"}}
        end
    end
  end

  def join("game", _params, _socket), do: {:error, %{error: "FORBIDDEN", reason: "params"}}

  @impl true
  def handle_in("cmd", payload, socket) do
    case Commands.envelope(payload) do
      {:ok, act, rid} ->
        case Commands.rate_limit(socket.assigns.account_id, act) do
          :ok ->
            socket = assign(socket, :limit_streak, nil)

            case Session.command(socket.assigns.account_id, act, payload) do
              :ok -> {:reply, {:ok, %{rid: rid}}, socket}
              {:error, code} -> fail(socket, rid, code)
            end

          {:error, code, window_ms} ->
            now = System.monotonic_time(:millisecond)

            case Commands.violation(socket.assigns.limit_streak, now, window_ms) do
              {:ok, streak} ->
                fail(assign(socket, :limit_streak, streak), rid, code)

              {:kick, _} ->
                push(socket, "error", %{rid: rid, error: code})
                {:stop, {:shutdown, :rate_limited}, socket}
            end
        end

      {:error, rid, code} ->
        fail(socket, rid, code)
    end
  end

  def handle_in(_event, _payload, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:session_kicked, _reason}, socket) do
    push(socket, "error", %{rid: nil, error: "FORBIDDEN"})
    {:stop, {:shutdown, :kicked}, socket}
  end

  # Qua cổng (P2-M4): bỏ topic map cũ, xả sự kiện map cũ còn trong hộp thư (id quái hai map có
  # thể trùng), theo topic map mới, đẩy `map_change` rồi `spawn` mọi entity của map mới
  def handle_info({:map_changed, old, new, payload, entities}, socket) do
    Phoenix.PubSub.unsubscribe(Mu.PubSub, MapServer.topic(old))
    drain_map_events()
    Phoenix.PubSub.subscribe(Mu.PubSub, MapServer.topic(new))
    push(socket, "map_change", payload)
    aoi = Aoi.new(socket.assigns.aoi.self, entities)
    push_all(socket, Aoi.spawns(aoi))
    {:noreply, assign(socket, :aoi, aoi)}
  end

  # `spawn` cho mọi entity đang trong tầm nhìn, theo trạng thái mới nhất (kể cả sự kiện map
  # tới trước tin này)
  def handle_info(:after_join, socket) do
    push_all(socket, Aoi.spawns(socket.assigns.aoi))
    # badge Hộp thư (P2-M6)
    push(socket, "mail", %{unread: Mu.Mail.unread(socket.assigns.character_id)})
    {:noreply, socket}
  end

  # Session đẩy riêng cho tài khoản này (vd. `player` khi EXP/level/stat/Zen đổi)
  def handle_info({:push, event, payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  # sự kiện map qua bộ lọc tầm nhìn (P3-M1)
  def handle_info({:map_event, event, payload}, socket) do
    {aoi, pushes} = Aoi.event(socket.assigns.aoi, event, payload)
    push_all(socket, pushes)
    {:noreply, assign(socket, :aoi, aoi)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp push_all(socket, pushes), do: Enum.each(pushes, fn {ev, p} -> push(socket, ev, p) end)

  defp drain_map_events do
    receive do
      {:map_event, _, _} -> drain_map_events()
    after
      0 -> :ok
    end
  end

  defp fail(socket, rid, code) do
    push(socket, "error", %{rid: rid, error: code})
    {:reply, {:error, %{rid: rid, error: code}}, socket}
  end

  @client_item_keys ~w(templateId name type slot weaponType stackable maxStack potionType effect attackMin
                       attackMax defense defenseRate speed hpBonus durability classes requirements
                       iconRef iconPlaceholder buyPrice sellPrice damageIncrease absorb)

  # Template item cho client hiển thị (tên, chỉ số, yêu cầu, iconRef); không có công thức
  defp client_items do
    for {_, t} <- Mu.Game.Data.items(), do: Map.take(t, @client_item_keys)
  end

  # Skill: tên, tầm, mana, cooldown, loại mục tiêu để client hiện menu, tiến lại gần, lặp
  # skill (server vẫn kiểm mọi thứ); không gửi hệ số / công thức
  defp client_skills do
    for {_, s} <- Mu.Game.Data.skills() do
      %{
        id: s["id"],
        name: s["name"],
        classes: s["classes"],
        magic: s["magic"] == true,
        category: s["category"],
        targetType: s["targetType"],
        center: s["center"],
        range: s["range"],
        radius: s["radius"],
        manaCost: s["manaCost"],
        cooldownMs: s["cooldownMs"],
        requiredLevel: s["requiredLevel"]
      }
    end
  end

  # Phần config client cần (không chứa công thức gameplay: KB_TECH_STACK §6)
  defp client_config do
    %{
      clientVersion: Config.get(["server", "clientVersion"]),
      interpolationDelayMs: Config.get(["server", "interpolationDelayMs"]),
      maxLevel: Config.get(["game", "maxLevel"]),
      pickupRange: Config.get(["interaction", "pickupRange"]),
      npcRange: Config.get(["interaction", "npcRange"]),
      twoHandedWeaponTypes: Config.get(["combat", "twoHandedWeaponTypes"]),
      partyInviteSeconds: Config.get(["party", "inviteSeconds"]),
      pvp: %{
        enabled: Config.get(["features", "pvp"]) == true,
        minLevel: Config.get(["pvp", "minLevel"])
      },
      duelInviteSeconds: Config.get(["duel", "inviteSeconds"]),
      # P6-M4: slot 7 (cánh) mở; P6-M3: Chaos Machine (số món tối đa đặt vào máy)
      wings: Config.get(["features", "wings"]) == true,
      chaos: %{
        enabled: Config.get(["features", "chaosMachine"]) == true,
        maxItems: Config.get(["chaos", "maxItems"])
      },
      # P5-M1: chỉ số cộng mỗi cấp +N theo type item (tooltip hiện số đúng; server vẫn tính)
      items: %{
        levelBonus: Config.get(["items", "levelBonus"]),
        # P7-3: từ +10 chỉ số mỗi cấp nhân multiplier
        highLevel: Config.get(["items"])["highLevel"],
        # P5-M2: option Jewel of Life cộng mỗi cấp
        optionBonus: Config.get(["upgrade", "life", "perOption"])
      },
      # guild (P4-M3): để hiện điều kiện tạo / kiểm tên trước khi gửi (server vẫn kiểm)
      guild: %{
        enabled: Config.get(["features", "guild"]) == true,
        createLevel: Config.get(["guild", "createLevel"]),
        createZen: Config.get(["guild", "createZen"]),
        maxMembers: Config.get(["guild", "maxMembers"]),
        maxAssistants: Config.get(["guild", "maxAssistants"]),
        inviteSeconds: Config.get(["guild", "inviteSeconds"]),
        namePattern: Config.get(["guild", "namePattern"])
      }
    }
  end
end

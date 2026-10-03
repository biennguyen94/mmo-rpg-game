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
  - Sau join, kênh đẩy `"spawn"` cho mọi entity trên map rồi chuyển tiếp `spawn` /
    `despawn` / `snapshot` của MapServer (PubSub). Kênh đăng ký topic trước khi vào map nên
    có thể nhận `spawn` của chính mình hai lần: client coi `spawn` là thêm-hoặc-cập-nhật.
  - `"player"` (trạng thái đầy đủ + `view`) do Session đẩy khi EXP/level/stat/Zen đổi;
    `"combat"` `{rid, attacker, target, dmg, crit, hp}` cho mọi đòn trên map (trượt: dmg 0).
  - Tab khác của cùng tài khoản vào game → kênh này nhận `{:session_kicked, _}`, đẩy
    `"error"` `FORBIDDEN` rồi đóng (`session.singleLoginPerAccount`).
  """
  use MuWeb, :channel

  alias Mu.Game.{Characters, Commands, Config, Session}
  alias Mu.World.{Maps, MapServer}

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

            send(self(), {:after_join, info.entities})

            reply = %{
              player: Characters.player_view(character, info.items),
              entityId: info.entity_id,
              map: Maps.client_data(Maps.get(character.map_id)),
              config: client_config(),
              data: %{items: client_items()}
            }

            {:ok, reply, assign(socket, character_id: character.id, limit_streak: nil)}

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

  def handle_info({:after_join, entities}, socket) do
    Enum.each(entities, &push(socket, "spawn", &1))
    {:noreply, socket}
  end

  # Session đẩy riêng cho tài khoản này (vd. `player` khi EXP/level/stat/Zen đổi)
  def handle_info({:push, event, payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info({:map_event, event, payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp fail(socket, rid, code) do
    push(socket, "error", %{rid: rid, error: code})
    {:reply, {:error, %{rid: rid, error: code}}, socket}
  end

  @client_item_keys ~w(templateId name type slot stackable maxStack potionType effect attackMin
                       attackMax defense defenseRate speed hpBonus durability classes requirements
                       iconRef iconPlaceholder buyPrice sellPrice)

  # Template item cho client hiển thị (tên, chỉ số, yêu cầu, iconRef); không có công thức
  defp client_items do
    for {_, t} <- Mu.Game.Data.items(), do: Map.take(t, @client_item_keys)
  end

  # Phần config client cần (không chứa công thức gameplay: KB_TECH_STACK §6)
  defp client_config do
    %{
      clientVersion: Config.get(["server", "clientVersion"]),
      interpolationDelayMs: Config.get(["server", "interpolationDelayMs"]),
      maxLevel: Config.get(["game", "maxLevel"])
    }
  end
end

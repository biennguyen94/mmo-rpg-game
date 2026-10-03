defmodule MuWeb.GameChannel do
  @moduledoc """
  Kênh `"game"` (`KB_TECHNICAL §5`). Khung join → gắn Session lấy từ
  `HacLongWeb.GameChannel`; bỏ mọi kênh phụ của repo nền.

  - `join("game", %{"clientVersion", "characterId"})`: `clientVersion` phải bằng
    `server.clientVersion` (P7), nhân vật phải thuộc tài khoản. Sai → `{error: "FORBIDDEN",
    reason}`. Đúng → `%{player, config}`.
  - `"cmd"` `{act, rid, ...}`: thành công trả reply `{:ok, %{rid}}`; lỗi trả reply
    `{:error, %{rid, error}}` **và** đẩy event `"error"` `{rid, error}` (P2).
  - Giới hạn tần suất theo nhóm `act` (P8): vượt → `RATE_LIMITED`; vượt liên tục
    `rateLimit.cmd.kickAfterMs` → đóng kênh.
  - Tab khác của cùng tài khoản vào game → kênh này nhận `{:session_kicked, _}`, đẩy
    `"error"` `FORBIDDEN` rồi đóng (`session.singleLoginPerAccount`).
  """
  use MuWeb, :channel

  alias Mu.Game.{Characters, Commands, Config, Session}

  @impl true
  def join("game", %{"clientVersion" => version, "characterId" => character_id}, socket) do
    account_id = socket.assigns.account_id

    cond do
      version != Config.get(["server", "clientVersion"]) ->
        {:error, %{error: "FORBIDDEN", reason: "clientVersion"}}

      true ->
        case Session.attach(account_id, character_id, self()) do
          {:ok, character} ->
            reply = %{player: Characters.player_view(character), config: client_config()}
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

            # M1: chưa có act nào được xử lý (M2: move_to, M3: attack/skill/alloc, M4: item/shop)
            fail(socket, rid, "FORBIDDEN")

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

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp fail(socket, rid, code) do
    push(socket, "error", %{rid: rid, error: code})
    {:reply, {:error, %{rid: rid, error: code}}, socket}
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

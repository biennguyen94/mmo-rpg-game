defmodule HacLongWeb.TienLenHandler do
  @moduledoc """
  Bàn Tiến Lên qua kênh `game` (Phase 17; thay các LiveView `lobby_live` / `table_live` /
  `spectate_live` / `replay_live` của repo gốc). Client gửi `"tl"` với `op`:

  | op | tham số | việc |
  |---|---|---|
  | `lobby` | | danh sách phòng công khai + phòng đang ngồi; nghe cập nhật sảnh |
  | `create` | `stake`, `private` | mở phòng rồi ngồi vào (chủ phòng) |
  | `join` / `leave` / `view` | `id` | ngồi / rời / xem bàn (mỗi lúc một phòng) |
  | `start` / `pass` | | chủ phòng chia bài / bỏ lượt |
  | `play` / `chop` | `cards` (mã lá) | đánh / chặt bốn đôi thông ngoài lượt |
  | `hints` | | các nước đánh hợp lệ (gợi ý) |
  | `stake` / `private` / `add_bot` / `remove_bot` | | chủ phòng chỉnh phòng |
  | `chat` / `react` / `throw` / `blow` | | chat bàn, biểu cảm, ném đồ (tốn vàng), thổi bài |
  | `watch` / `unwatch` | `id` | xem trận (không thấy bài ai) |
  | `history` / `replay` | `id` | các ván đã chơi / xem lại một ván |

  Người chơi là `user_id`, tên là tên nhân vật. Kênh là tiến trình được `RoomServer` theo dõi:
  đóng hết tab thì sau 20 giây bị loại khỏi ván (luật T15 của repo gốc).

  Sự kiện đẩy xuống: `"tl"` (`%{view, events}` sau mỗi thay đổi), `"tl_chat"`, `"tl_fx"`
  (biểu cảm, ném, thổi, hiệu ứng âm thanh), `"tl_lobby"` (sảnh đổi, client tự hỏi lại).
  """
  import Phoenix.Channel
  import Phoenix.Socket, only: [assign: 3]

  alias HacLong.Accounts
  alias HacLong.Game.Session
  alias HacLong.TienLen.{Card, Chat, Lobby, Records, Replay, RoomServer, Text, Throws, Wire}

  @bot_levels %{"easy" => :easy, "normal" => :normal}

  # ---------- lệnh ----------

  def handle_in(%{"op" => op} = p, socket) do
    uid = socket.assigns.user_id

    case op(op, p, uid, socket) do
      {:ok, reply, socket} -> {:reply, {:ok, Wire.encode(reply)}, socket}
      {:error, reason, socket} -> {:reply, {:error, %{msg: message(reason)}}, socket}
    end
  end

  def handle_in(_p, socket), do: {:reply, {:error, %{msg: "Lệnh không hợp lệ."}}, socket}

  defp message(msg) when is_binary(msg), do: msg
  defp message(reason), do: Text.reason(reason)

  defp op("lobby", _p, _uid, socket) do
    socket = subscribe_once(socket, :tl_lobby, Lobby.topic())

    {:ok,
     %{
       rooms: Lobby.public_rooms(),
       room: socket.assigns[:tl_room],
       watching: socket.assigns[:tl_watch],
       phrases: Chat.phrases(),
       reactions: Chat.reactions(),
       throws: Throws.items(),
       types: Text.types(),
       instants: Text.instants(),
       stake_max: HacLong.Game.Data.rules().tienlen.stake_max
     }, socket}
  end

  defp op("create", p, uid, socket) do
    stake = int(p["stake"], 0)

    with {:ok, room_id} <- Lobby.open_room(stake: stake, private: p["private"] == true) do
      sit(room_id, uid, socket)
    else
      {:error, reason} -> {:error, reason, socket}
    end
  end

  defp op("join", %{"id" => id}, uid, socket) when is_binary(id), do: sit(id, uid, socket)

  defp op("leave", _p, uid, socket) do
    case socket.assigns[:tl_room] do
      nil ->
        {:ok, %{}, socket}

      id ->
        RoomServer.leave(id, uid)
        {:ok, %{}, drop_room(socket)}
    end
  end

  defp op("view", _p, uid, socket) do
    case socket.assigns[:tl_room] do
      nil -> {:error, :not_in_room, socket}
      id -> reply_view(RoomServer.view(id, uid), socket)
    end
  end

  defp op("start", _p, uid, socket), do: room_call(socket, &RoomServer.start_game(&1, uid))
  defp op("pass", _p, uid, socket), do: room_call(socket, &RoomServer.pass(&1, uid))

  defp op(play, %{"cards" => codes}, uid, socket) when play in ["play", "chop"] do
    case parse(codes) do
      {:ok, cards} when play == "play" -> room_call(socket, &RoomServer.play(&1, uid, cards))
      {:ok, cards} -> room_call(socket, &RoomServer.chop(&1, uid, cards))
      :error -> {:error, :not_your_cards, socket}
    end
  end

  # thử trước (không đổi gì) để nút Đánh / Bỏ lượt / Chặt hiện đúng lý do: luật chỉ ở server (D1)
  defp op("check", p, uid, socket) do
    with id when id != nil <- socket.assigns[:tl_room],
         {:ok, cards} <- parse(p["cards"] || []) |> ok_or_empty(p["cards"]) do
      res = fn
        :ok -> "ok"
        {:error, r} -> Text.reason(r)
      end

      play =
        if cards == [],
          do: Text.reason(:empty),
          else: res.(RoomServer.check(id, uid, {:play, cards}))

      chop =
        if length(cards) == 8,
          do: res.(RoomServer.check(id, uid, {:chop, cards})),
          else: Text.reason(:not_four_pair)

      {:ok, %{play: play, pass: res.(RoomServer.check(id, uid, :pass)), chop: chop}, socket}
    else
      nil -> {:error, :not_in_room, socket}
      :error -> {:error, :not_your_cards, socket}
    end
  end

  defp op("hints", _p, uid, socket) do
    case socket.assigns[:tl_room] do
      nil -> {:error, :not_in_room, socket}
      id -> {:ok, %{hints: RoomServer.hints(id, uid)}, socket}
    end
  end

  defp op("stake", p, uid, socket),
    do: room_call(socket, &RoomServer.set_stake(&1, uid, int(p["stake"], -1)))

  defp op("private", p, uid, socket),
    do: room_call(socket, &RoomServer.set_private(&1, uid, p["private"] == true))

  defp op("add_bot", p, uid, socket) do
    case @bot_levels[p["level"] || "normal"] do
      nil -> {:error, :unknown_command, socket}
      level -> room_call(socket, &RoomServer.add_bot(&1, uid, level))
    end
  end

  defp op("remove_bot", p, uid, socket),
    do: room_call(socket, &RoomServer.remove_bot(&1, uid, int(p["seat"], -1)))

  defp op("chat", p, uid, socket) do
    with id when is_binary(id) <- socket.assigns[:tl_room] || {:error, :not_in_room},
         :ok <- not_muted(uid),
         {:ok, msg} <- Chat.prepare(uid, name(uid), p["text"]),
         :ok <- RoomServer.chat(id, uid, msg) do
      {:ok, %{}, socket}
    else
      {:error, reason} -> {:error, reason, socket}
    end
  end

  defp op("chat_history", _p, uid, socket) do
    with id when is_binary(id) <- socket.assigns[:tl_room] || {:error, :not_in_room},
         {:ok, msgs} <- RoomServer.chat_history(id, uid) do
      {:ok, %{chat: msgs}, socket}
    else
      {:error, reason} -> {:error, reason, socket}
    end
  end

  defp op("react", p, uid, socket),
    do: room_call(socket, &RoomServer.react(&1, uid, p["emoji"]))

  defp op("throw", p, uid, socket),
    do: room_call(socket, &RoomServer.throw(&1, uid, int(p["to"], -1), p["item"]))

  defp op("blow", _p, uid, socket), do: room_call(socket, &RoomServer.blow(&1, uid))

  defp op("watch", %{"id" => id}, _uid, socket) when is_binary(id) do
    socket = drop_watch(socket)

    case RoomServer.watch(id) do
      {:ok, view} ->
        Phoenix.PubSub.subscribe(HacLong.PubSub, RoomServer.topic(id))
        {:ok, %{view: view}, assign(socket, :tl_watch, id)}

      {:error, reason} ->
        {:error, reason, socket}
    end
  end

  defp op("unwatch", _p, _uid, socket), do: {:ok, %{}, drop_watch(socket)}

  defp op("history", _p, uid, socket), do: {:ok, %{games: Records.list(uid)}, socket}

  defp op("replay", p, uid, socket) do
    case Records.get(int(p["id"], -1), uid) do
      %{replay: %{} = replay} = g ->
        {:ok,
         %{
           id: g.id,
           at: g.at,
           names: Replay.names(replay),
           players: g.players["list"],
           frames: Replay.frames(replay)
         }, socket}

      _ ->
        {:error, :not_found, socket}
    end
  end

  # Mời bạn vào bàn: danh sách bạn bè (ai đang online), gửi tin riêng có mã phòng; người nhận bấm
  # "Vào bàn" ở thông báo hoặc trong khung tin riêng (`invite_text/2`, client nhận ra `[mã]`).
  defp op("friends", _p, uid, socket) do
    friends =
      uid
      |> HacLong.Friends.list()
      |> Map.get(:friends, [])
      |> Enum.map(&Map.take(&1, [:id, :name, :level, :online]))
      |> Enum.sort_by(&{!&1.online, &1.name})

    {:ok, %{friends: friends}, socket}
  end

  defp op("invite", p, uid, socket) do
    with id when is_binary(id) <- socket.assigns[:tl_room] || {:error, :not_in_room},
         to when is_integer(to) <- p["uid"] || {:error, :not_found},
         :ok <- invite_rate(uid),
         %{} = v <- RoomServer.view(id, uid),
         {:ok, _msg} <- HacLong.Friends.send_message(uid, to, invite_text(id, v.stake)) do
      {:ok, %{}, socket}
    else
      {:error, reason} -> {:error, reason, socket}
    end
  end

  defp op(_op, _p, _uid, socket), do: {:error, :unknown_command, socket}

  @doc "Chữ của lời mời (client tìm `[mã phòng]` sau 🃏 để hiện nút Vào bàn)."
  def invite_text(room_id, stake) do
    bet = if stake > 0, do: "cược #{stake} vàng", else: "chơi vui"
    "🃏 Mời bạn vào bàn Tiến Lên [#{room_id}] · #{bet}"
  end

  defp invite_rate(uid) do
    case HacLong.RateLimit.hit({:tl_invite, uid}, 10, 60_000) do
      :ok -> :ok
      _ -> {:error, "Mời chậm thôi, chờ chút rồi mời tiếp."}
    end
  end

  # ---------- sự kiện từ phòng / sảnh ----------

  @doc "Tin PubSub của Tiến Lên: `{:noreply, socket}`, hoặc `:skip` nếu không phải."
  def handle_info({:room_updated, id, _version, events}, socket) do
    uid = socket.assigns.user_id

    view =
      cond do
        socket.assigns[:tl_room] == id -> RoomServer.view(id, uid)
        socket.assigns[:tl_watch] == id -> RoomServer.spectator_view(id)
        true -> nil
      end

    case view do
      %{} = v ->
        push(socket, "tl", Wire.encode(%{id: id, view: v, events: events}))
        {:noreply, socket}

      _ ->
        # phòng đóng hoặc mình đã rời
        if Enum.any?(events, &match?({:closed_by_admin}, &1)) and
             socket.assigns[:tl_room] == id,
           do: push(socket, "tl", %{id: id, view: nil, events: [["closed"]]})

        {:noreply, socket}
    end
  end

  def handle_info({:room_chat, _id, msg}, socket) do
    push(socket, "tl_chat", Wire.encode(msg))
    {:noreply, socket}
  end

  def handle_info({:room_chat_deleted, _id, msg_id}, socket) do
    push(socket, "tl_chat", %{deleted: msg_id})
    {:noreply, socket}
  end

  def handle_info({:reaction, _id, seat, emoji}, socket),
    do: fx(socket, %{kind: "reaction", seat: seat, emoji: emoji})

  def handle_info({:thrown, _id, from, to, item}, socket),
    do: fx(socket, %{kind: "throw", from: from, to: to, item: item})

  def handle_info({:blow, _id, seat}, socket), do: fx(socket, %{kind: "blow", seat: seat})

  def handle_info({:effects, _id, kinds}, socket),
    do: fx(socket, %{kind: "effects", effects: Wire.encode(kinds)})

  def handle_info({event, _id}, socket) when event in [:lobby_updated, :room_closed] do
    if socket.assigns[:tl_lobby], do: push(socket, "tl_lobby", %{})
    {:noreply, socket}
  end

  def handle_info(_msg, _socket), do: :skip

  # ---------- tiện ích ----------

  defp fx(socket, payload) do
    push(socket, "tl_fx", payload)
    {:noreply, socket}
  end

  # ngồi vào phòng `id` (rời phòng cũ nếu khác), nghe phòng, trả bàn
  defp sit(id, uid, socket) do
    socket =
      case socket.assigns[:tl_room] do
        nil ->
          socket

        ^id ->
          socket

        old ->
          RoomServer.leave(old, uid)
          drop_room(socket)
      end

    socket = drop_watch(socket)

    case RoomServer.join(id, uid, name(uid)) do
      {:ok, _seat} ->
        if socket.assigns[:tl_room] != id,
          do: Phoenix.PubSub.subscribe(HacLong.PubSub, RoomServer.topic(id))

        socket = assign(socket, :tl_room, id)
        reply_view(RoomServer.view(id, uid), socket)

      {:error, reason} ->
        {:error, reason, socket}
    end
  end

  defp reply_view({:error, reason}, socket), do: {:error, reason, socket}
  defp reply_view(view, socket), do: {:ok, %{id: socket.assigns[:tl_room], view: view}, socket}

  defp room_call(socket, fun) do
    case socket.assigns[:tl_room] do
      nil ->
        {:error, :not_in_room, socket}

      id ->
        case fun.(id) do
          :ok -> {:ok, %{}, socket}
          {:ok, _} -> {:ok, %{}, socket}
          {:error, :room_not_found} -> {:error, :room_not_found, drop_room(socket)}
          {:error, reason} -> {:error, reason, socket}
        end
    end
  end

  defp drop_room(socket) do
    case socket.assigns[:tl_room] do
      nil ->
        socket

      id ->
        if socket.assigns[:tl_watch] != id,
          do: Phoenix.PubSub.unsubscribe(HacLong.PubSub, RoomServer.topic(id))

        assign(socket, :tl_room, nil)
    end
  end

  defp drop_watch(socket) do
    case socket.assigns[:tl_watch] do
      nil ->
        socket

      id ->
        if socket.assigns[:tl_room] != id,
          do: Phoenix.PubSub.unsubscribe(HacLong.PubSub, RoomServer.topic(id))

        assign(socket, :tl_watch, nil)
    end
  end

  defp subscribe_once(socket, key, topic) do
    if socket.assigns[key] do
      socket
    else
      Phoenix.PubSub.subscribe(HacLong.PubSub, topic)
      assign(socket, key, true)
    end
  end

  defp parse(codes) when is_list(codes) and length(codes) in 1..13 do
    cards = Enum.map(codes, &(is_binary(&1) && Card.parse(&1)))

    if Enum.all?(cards, &match?({:ok, _}, &1)),
      do: {:ok, Enum.map(cards, &elem(&1, 1))},
      else: :error
  end

  defp parse(_), do: :error

  defp ok_or_empty(_res, []), do: {:ok, []}
  defp ok_or_empty(res, _), do: res

  defp name(uid) do
    case Session.get(uid) do
      %{name: name} -> name
      _ -> "Người chơi #{uid}"
    end
  end

  defp not_muted(uid) do
    if Accounts.muted?(Accounts.get_user(uid)), do: {:error, :muted}, else: :ok
  end

  defp int(v, _default) when is_integer(v), do: v

  defp int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp int(_, default), do: default
end

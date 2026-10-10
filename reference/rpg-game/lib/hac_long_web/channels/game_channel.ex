defmodule HacLongWeb.GameChannel do
  @moduledoc """
  Kênh chơi game.

  - Client gửi `"cmd"` với payload `%{"act" => ..., ...}` (xem `HacLong.Game.Commands`;
    bước đi là `%{"act" => "move", "dir" => "up" | "down" | "left" | "right"}`) và nhận lại
    kết quả kèm trạng thái nhân vật mới.
  - Khi nhân vật đổi từ tab khác, server đẩy `"player"`.
  - Server đẩy `"map"` với quái và người chơi trên bản đồ nhân vật đang đứng, mỗi khi
    bản đồ đó thay đổi. Kênh tự chuyển theo dõi khi nhân vật sang bản đồ khác.
  - Chat thế giới: client gửi `"chat"` với `%{"text" => ...}`; server đẩy `"chat"` (một tin)
    cho mọi người và `"chat_history"` (các tin gần nhất) lúc mới vào.
  - `"leaderboard"`: trả về các bảng xếp hạng và hạng của mình.
  - Server đẩy `"world_boss"` (trạng thái trùm thế giới: còn sống, máu, top sát thương) mỗi
    khi thay đổi, và `"notice"` (`%{msg}`) khi có thông báo riêng (vd. nhận thưởng trùm).
  - `"block"` / `"unblock"` `%{"uid"}`: ẩn/hiện chat của một người; `"report"` `%{"id"}`: báo
    cáo một tin nhắn chat.
  - `"guild"` `%{"op" => ...}`: bang hội (xem `guild/3`); chat bang là `"chat"` với
    `"to" => "guild"`, server đẩy `"chat"` kèm `guild: true`; đổi bang thì server đẩy `"guild"`.
  - `"party"` `%{"op" => ...}`: tổ đội (`invite {uid}`, `accept`, `decline`, `leave`,
    `kick {uid}`, `info`); server đẩy `"party"` (tổ đội đổi), `"party_invite"` (có lời mời),
    `"shared"` (máu chung của trận đánh cùng). Chat tổ đội: `"chat"` với `"to" => "party"`.
  - `"arena"`: điểm đấu trường của mình, đối thủ gợi ý, bảng xếp hạng; thách đấu là lệnh
    `"cmd"` `%{"act" => "pvp_challenge", "uid" => ...}`.
  - `"market"` `%{"q"}`: hàng đang bán ở chợ và hàng mình đang rao; rao bán, mua, rút về là
    lệnh `"cmd"` `market_sell {id, count, price}`, `market_buy {listing}`,
    `market_cancel {listing}` (đứng cạnh Chủ Chợ).
  - `"trade"` `%{"op" => ...}`: giao dịch trực tiếp (`request {uid}`, `accept`, `decline`,
    `cancel`, `offer {offer: {items, gear, gold}}`, `ready`, `info`); server đẩy `"trade"`
    (`%{trade: bảng | nil}`) và `"trade_request"` (`%{from, name}`). Xem `HacLong.Trade`.
  - `"friends"` `%{"op" => ...}`: bạn bè (`list`, `request {uid | name}`, `accept {uid}`,
    `decline {uid}`, `remove {uid}`); server đẩy `"friends"` (`%{msg}`) khi danh sách đổi.
    `"dm"`: tin riêng (`history {uid}`, `send {uid, text}`); server đẩy `"dm"` (một tin, cả
    cho người gửi để các tab khác thấy). Xem `HacLong.Friends`.
  - `"inspect"` `%{"uid"}`: xem hồ sơ người chơi (cả của mình; `profile` theo `HacLong.Profile`).
  - `"visit"` `%{"uid"}`: xem nhà đã trang trí của người khác; `"home_like"` `%{"uid"}`: khen nhà
    (mỗi nhà một lần, chủ nhà nhận `"notice"`). Xem `HacLong.Homes`.
  - `"mail"`: danh sách thư; server đẩy `"mail"` `%{unread}` khi có thư mới. Mở thư (nhận quà)
    là lệnh `"cmd"` `%{"act" => "mail_claim", "id" => ...}`.
  - `"admin"` `%{"op" => ...}` (chỉ tài khoản quản trị): xem/xử lý báo cáo, tra cứu, cấm chat,
    khóa tài khoản, thông báo, tặng quà qua hộp thư, gọi trùm thế giới. Xem `admin/3`.
  """
  require Logger
  use HacLongWeb, :channel

  alias HacLong.{
    Accounts,
    Arena,
    Chat,
    Friends,
    Guilds,
    Homes,
    Leaderboard,
    Mailbox,
    Market,
    Moderation,
    Party,
    PkBet,
    RateLimit,
    Trade,
    WorldBoss
  }

  alias HacLong.Game.{
    Achievements,
    Chests,
    Daily,
    Data,
    Engine,
    Quests,
    Session,
    TradeOffer,
    Tutorial
  }

  alias HacLong.World.{Maps, MapServer}

  # mod: xử lý báo cáo, tra cứu, cấm chat, thông báo (không khóa tài khoản, không sửa nhân vật)
  @mod_ops ~w(reports lookup resolve mute unmute announce online)
  # chỉ đọc: không ghi admin_log
  @read_ops ~w(reports lookup audit gold_log admin_log online)

  @impl true
  # Giao diện mở từ trước khi cập nhật server (mã phiên bản khác): từ chối, client tự tải lại trang.
  def join("game", params, socket) do
    if params["v"] == HacLongWeb.ClientVersion.current(),
      do: join_game(socket),
      else: {:error, %{reason: "version", msg: "Đã có bản cập nhật, đang tải lại trang..."}}
  end

  defp join_game(socket) do
    uid = socket.assigns.user_id
    Phoenix.PubSub.subscribe(HacLong.PubSub, Session.topic(uid))
    Phoenix.PubSub.subscribe(HacLong.PubSub, Chat.topic())
    Phoenix.PubSub.subscribe(HacLong.PubSub, WorldBoss.topic())
    player = Session.attach(uid, self())
    send(self(), :push_map)
    blocked = Moderation.blocked(uid)
    gid = player && player[:guild] && player.guild.id
    if gid, do: Phoenix.PubSub.subscribe(HacLong.PubSub, Guilds.topic(gid))

    reply = %{
      username: socket.assigns.username,
      user_id: uid,
      # thấy tab Quản trị (mod hoặc admin); `role` cho biết được dùng lệnh nào
      admin: socket.assigns[:role] in ~w(mod admin),
      role: socket.assigns[:role] || "player",
      blocked: blocked,
      mail: Mailbox.unread(uid),
      party: party_view(uid),
      trade: Trade.of(uid),
      dm: Friends.unread(uid),
      player: present(player)
    }

    {:ok, reply,
     socket
     |> assign(:map, nil)
     |> assign(:guild_id, gid)
     |> assign(:blocked, MapSet.new(blocked, & &1.id))}
  end

  @impl true
  def handle_in("cmd", %{} = cmd, socket) do
    {result, player} = Session.command(socket.assigns.user_id, cmd)
    socket = follow_map(socket, player)
    {:reply, {:ok, Map.put(result, :player, present(player))}, socket}
  end

  def handle_in("chat", %{"text" => text} = payload, socket) do
    uid = socket.assigns.user_id

    with :ok <- chat_limit(uid),
         :ok <- not_muted(uid),
         %{} = p <- Session.get(uid) || {:error, "Hãy tạo nhân vật trước."},
         from = %{
           uid: uid,
           name: p.name,
           map: p.pos.map,
           title: Achievements.title_name(p[:title]),
           tag: p[:guild] && p.guild.tag
         },
         {:ok, _msg} <- post_chat(payload["to"], p, from, text) do
      {:reply, :ok, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("leaderboard", _payload, socket) do
    uid = socket.assigns.user_id

    case RateLimit.hit({:leaderboard, uid}, 20, :timer.minutes(1)) do
      :ok ->
        me = Leaderboard.me(uid)

        # `me` cũ là hạng chung (số), client cũ vẫn đọc được; `me_rank` có thêm hạng trong lớp
        boards = Leaderboard.boards() |> Map.put(:me, me && me.level) |> Map.put(:me_rank, me)
        {:reply, {:ok, boards}, socket}

      {:error, _} ->
        {:reply, {:error, %{msg: "Thao tác quá nhanh."}}, socket}
    end
  end

  def handle_in("guild", %{"op" => op} = p, socket) do
    uid = socket.assigns.user_id

    with :ok <- limit({:guild, uid}, 40, :timer.minutes(1)),
         {:ok, data} <- guild(op, p, uid) do
      {:reply, {:ok, data}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("party", %{"op" => op} = p, socket) do
    uid = socket.assigns.user_id

    target = p["uid"]

    result =
      case op do
        "info" -> :ok
        "invite" when is_integer(target) -> invite(uid, target)
        "accept" -> Party.accept(uid)
        "decline" -> Party.decline(uid)
        "leave" -> Party.leave(uid)
        "kick" when is_integer(target) -> Party.kick(uid, target)
        _ -> {:error, "Thao tác không hợp lệ."}
      end

    with :ok <- limit({:party, uid}, 40, :timer.minutes(1)),
         :ok <- result do
      {:reply, {:ok, %{party: party_view(uid)}}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("friends", %{"op" => op} = p, socket) do
    uid = socket.assigns.user_id
    target = p["uid"]

    result =
      case op do
        "list" -> {:ok, nil}
        "request" when is_integer(target) -> Friends.request(uid, target)
        "request" -> Friends.request_by_name(uid, p["name"])
        "accept" when is_integer(target) -> Friends.accept(uid, target)
        "decline" when is_integer(target) -> Friends.decline(uid, target)
        "remove" when is_integer(target) -> Friends.remove(uid, target)
        _ -> {:error, "Thao tác không hợp lệ."}
      end

    with :ok <- limit({:friends, uid}, 40, :timer.minutes(1)),
         {:ok, msg} <- result do
      {:reply, {:ok, Map.put(Friends.list(uid), :msg, msg)}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("dm", %{"op" => "history", "uid" => other}, socket) when is_integer(other) do
    uid = socket.assigns.user_id

    with :ok <- limit({:dm_read, uid}, 60, :timer.minutes(1)) do
      {:reply, {:ok, Map.put(Friends.history(uid, other), :unread, Friends.unread(uid))}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("dm", %{"op" => "send", "uid" => to, "text" => text}, socket)
      when is_integer(to) do
    uid = socket.assigns.user_id

    with :ok <- chat_limit(uid),
         :ok <- not_muted(uid),
         {:ok, msg} <- Friends.send_message(uid, to, text) do
      {:reply, {:ok, %{message: msg}}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("trade", %{"op" => op} = p, socket) do
    uid = socket.assigns.user_id

    with :ok <- limit({:trade, uid}, 60, :timer.minutes(1)),
         :ok <- trade(op, p, uid) do
      {:reply, {:ok, %{trade: Trade.of(uid)}}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  # PK cược vàng (Phase 5, H7 + H8): mời / nhận / từ chối / hủy / xem
  def handle_in("pk", %{"op" => op} = p, socket) do
    uid = socket.assigns.user_id

    with :ok <- limit({:pk, uid}, 30, :timer.minutes(1)) do
      case pk(op, p, uid) do
        :ok -> {:reply, {:ok, pk_view(uid)}, socket}
        {:ok, result} -> {:reply, {:ok, Map.put(pk_view(uid), :result, result)}, socket}
        {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
      end
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  # Đồ sát (`HacLong.Slay`): đánh ngay người chơi cùng bản đồ, không cần đồng ý
  def handle_in("slay", %{"uid" => target}, socket) do
    uid = socket.assigns.user_id

    with :ok <- limit({:slay, uid}, 20, :timer.minutes(1)),
         {:ok, _f} <- HacLong.Slay.attack(uid, target) do
      {:reply, {:ok, %{}}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  # Tiến Lên (Phase 17): sảnh, bàn bài, xem trận, xem lại ván (`HacLongWeb.TienLenHandler`)
  def handle_in("tl", p, socket) do
    case limit({:tl, socket.assigns.user_id}, 300, :timer.minutes(1)) do
      :ok -> HacLongWeb.TienLenHandler.handle_in(p, socket)
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  # Quảng Trường Quỷ (Phase 18 M1): bảng xếp hạng hôm nay
  def handle_in("ds_top", _p, socket) do
    top = HacLong.DevilSquareBoard.top()
    {:reply, {:ok, %{top: Enum.map(top, &Map.take(&1, [:name, :score]))}}, socket}
  end

  def handle_in("market", p, socket) do
    uid = socket.assigns.user_id

    with :ok <- limit({:market, uid}, 40, :timer.minutes(1)) do
      {:reply,
       {:ok,
        %{
          listings: Market.listings(p["q"] || "", uid),
          fee: Market.fee_pct(),
          max: Market.max_active()
        }}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("arena", _payload, socket) do
    uid = socket.assigns.user_id

    with :ok <- limit({:arena, uid}, 30, :timer.minutes(1)) do
      me = Map.put(Arena.stats(uid), :per_day, Arena.per_day())
      {:reply, {:ok, %{me: me, suggestions: Arena.suggestions(uid), top: Arena.top()}}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("inspect", %{"uid" => target}, socket) when is_integer(target) do
    uid = socket.assigns.user_id

    with :ok <- limit({:inspect, uid}, 60, :timer.minutes(1)),
         %{} = p <- online_or_saved(target) || {:error, "Không tìm thấy người chơi."} do
      name = fn id -> (it = HacLong.Game.Gear.item(p, id)) && it.name end
      guild = Guilds.brief(target)
      party = Party.of(uid)

      {:reply,
       {:ok,
        %{
          id: target,
          name: p.name,
          cls: p.cls,
          level: p.level,
          rebirths: Map.get(p, :rebirths, 0),
          look: Engine.look(p),
          title: Achievements.title_name(p[:title]),
          guild: guild && %{name: guild.name, tag: guild.tag},
          gear: Map.new(p.equip, fn {slot, id} -> {slot, name.(id)} end),
          arena: Arena.stats(target),
          blocked: target in socket.assigns.blocked,
          party: party && target in party.members,
          me: target == uid,
          # Phase 13: hồ sơ đầy đủ (xem cả của mình)
          profile:
            HacLong.Profile.build(
              target,
              p,
              Registry.lookup(HacLong.Game.Registry, target) != []
            )
        }}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("visit", %{"uid" => target}, socket) when is_integer(target) do
    uid = socket.assigns.user_id

    with :ok <- limit({:inspect, uid}, 60, :timer.minutes(1)),
         %{} = p <- online_or_saved(target) || {:error, "Không tìm thấy người chơi."} do
      {:reply, {:ok, Homes.view(p, target, uid)}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("home_like", %{"uid" => target}, socket) when is_integer(target) do
    uid = socket.assigns.user_id

    with :ok <- limit({:home_like, uid}, 20, :timer.minutes(1)),
         %{} <- online_or_saved(target) || {:error, "Không tìm thấy người chơi."},
         %{name: name} <- Session.get(uid) || {:error, "Chưa có nhân vật."},
         {:ok, n} <- Homes.like(target, uid, name) do
      {:reply, {:ok, %{likes: n}}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("mail", payload, socket) do
    uid = socket.assigns.user_id

    with :ok <- limit({:mail, uid}, 30, :timer.minutes(1)) do
      # xóa thư đã đọc (Phase 5, H12)
      if payload["op"] == "delete_read", do: Mailbox.delete_read(uid)

      {:reply, {:ok, %{mails: Mailbox.list(uid), unread: Mailbox.unread(uid)}}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("block", %{"uid" => id}, socket) when is_integer(id) do
    uid = socket.assigns.user_id

    case Moderation.block(uid, id) do
      :ok ->
        {:reply, {:ok, %{blocked: Moderation.blocked(uid)}},
         assign(socket, :blocked, MapSet.put(socket.assigns.blocked, id))}

      {:error, msg} ->
        {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("unblock", %{"uid" => id}, socket) when is_integer(id) do
    uid = socket.assigns.user_id
    Moderation.unblock(uid, id)

    {:reply, {:ok, %{blocked: Moderation.blocked(uid)}},
     assign(socket, :blocked, MapSet.delete(socket.assigns.blocked, id))}
  end

  def handle_in("report", %{"id" => id}, socket) when is_integer(id) do
    uid = socket.assigns.user_id

    with :ok <- limit({:report, uid}, 10, :timer.minutes(10)),
         :ok <- Moderation.report(uid, id) do
      {:reply, :ok, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("admin", %{"op" => op} = p, %{assigns: %{role: role}} = socket)
      when role in ~w(mod admin) and is_binary(op) do
    Logger.info("quản trị #{socket.assigns.username}: #{op} #{inspect(Map.delete(p, "op"))}")

    result =
      cond do
        role == "mod" and (op not in @mod_ops or p["action"] == "ban") ->
          {:error, "Cần quyền quản trị viên."}

        # sửa nhân vật: HacLong.Admin tự ghi admin_log (kèm mã dòng vào nhật ký vàng/đồ)
        op in HacLong.Admin.char_ops() ->
          admin_char(op, p, socket)

        op in @read_ops ->
          admin(op, p, socket)

        true ->
          id = HacLong.Admin.log!(admin_of(socket), op, target(p), p, nil)
          result = admin(op, p, socket)
          HacLong.Admin.set_result(id, result)
          result
      end

    case result do
      {:ok, data} -> {:reply, {:ok, data}, socket}
      :ok -> {:reply, {:ok, %{}}, socket}
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("admin", _p, socket), do: {:reply, {:error, %{msg: "Không có quyền."}}, socket}

  def handle_in(_event, _payload, socket), do: {:reply, {:error, %{msg: "Sai cú pháp."}}, socket}

  # người đang online thì lấy trạng thái mới nhất, không thì đọc database
  defp online_or_saved(uid) do
    case Registry.lookup(HacLong.Game.Registry, uid) do
      [_] -> Session.get(uid)
      [] -> HacLong.Game.Characters.load(uid)
    end
  end

  # ---------- PK cược vàng ----------

  # PK cược vàng đã thay bằng đồ sát (`HacLong.Slay`); còn xem lịch sử, nhận / từ chối lời mời cũ
  defp pk("invite", _p, _uid),
    do: {:error, "PK cược đã thay bằng Đồ sát: chạm tên người chơi rồi bấm Đồ sát."}

  defp pk("accept", _p, uid) do
    with {:ok, inv} <- PkBet.take(uid), do: PkBet.execute(inv)
  end

  defp pk("decline", _p, uid), do: PkBet.decline(uid)
  defp pk("cancel", _p, uid), do: PkBet.cancel(uid)
  defp pk("info", _p, _uid), do: :ok
  defp pk(_op, _p, _uid), do: {:error, "Thao tác không hợp lệ."}

  defp pk_view(uid) do
    %{
      invite: PkBet.of(uid),
      history: PkBet.history(uid),
      today: PkBet.today_count(uid),
      rules: Map.take(PkBet.rules(), [:min, :max, :per_day, :invite_s])
    }
  end

  # ---------- Giao dịch ----------

  defp trade("request", %{"uid" => target}, uid) when is_integer(target) do
    with false <- HacLong.Bots.bot?(target) && {:error, "Người này không nhận giao dịch."},
         [_] <- Registry.lookup(HacLong.Game.Registry, target) || [],
         %{name: name} = me <- Session.get(uid),
         true <-
           Trade.near?(me, Session.get(target)) ||
             {:error, "Hãy đứng gần người kia (cùng bản đồ) để giao dịch."} do
      Trade.request(uid, name, target)
    else
      {:error, _} = err -> err
      _ -> {:error, "Người này không online."}
    end
  end

  defp trade("accept", _p, uid) do
    case Session.get(uid) do
      %{name: name} -> Trade.accept(uid, name)
      _ -> {:error, "Chưa có nhân vật."}
    end
  end

  defp trade("decline", _p, uid), do: Trade.decline(uid)
  defp trade("cancel", _p, uid), do: Trade.cancel(uid)
  defp trade("ready", _p, uid), do: Trade.ready(uid)
  defp trade("info", _p, _uid), do: :ok

  defp trade("offer", p, uid) do
    with %{} = player <- Session.get(uid) || {:error, "Chưa có nhân vật."},
         {:ok, offer} <- TradeOffer.parse(player, p["offer"]) do
      Trade.offer(uid, offer)
    end
  end

  defp trade(_op, _p, _uid), do: {:error, "Thao tác không hợp lệ."}

  # ---------- Tổ đội ----------

  # chỉ mời được người đang online
  defp invite(uid, target) do
    case Registry.lookup(HacLong.Game.Registry, target) do
      [_] -> Party.invite(uid, target)
      [] -> {:error, "Người này không online."}
    end
  end

  defp party_view(uid) do
    case Party.of(uid) do
      nil ->
        nil

      party ->
        members =
          for m <- party.members, p = Session.get(m) do
            %{
              id: m,
              name: p.name,
              cls: p.cls,
              level: p.level,
              hp: p.hp,
              maxHp: Engine.derived(p).maxHp,
              map: p.pos.map
            }
          end

        %{id: party.id, leader: party.leader, members: members, max: Party.max()}
    end
  end

  defp party_chat(from, text) do
    case Party.of(from.uid) do
      nil ->
        {:error, "Bạn chưa ở trong tổ đội nào."}

      party ->
        text = text |> String.replace(~r/\s+/u, " ") |> String.trim() |> String.slice(0, 120)

        if text == "" do
          {:error, "Tin nhắn trống."}
        else
          msg =
            Map.merge(from, %{
              id: nil,
              text: text,
              party: true,
              at: System.system_time(:millisecond)
            })

          for m <- party.members,
              do: Phoenix.PubSub.broadcast(HacLong.PubSub, Session.topic(m), {:party_chat, msg})

          {:ok, msg}
        end
    end
  end

  # Kênh chat: thế giới (mặc định), bang hội, tổ đội.
  defp post_chat("guild", p, from, text), do: guild_chat(p, from, text)
  defp post_chat("party", _p, from, text), do: party_chat(from, text)
  defp post_chat(_, _p, from, text), do: Chat.post(from, text)

  # ---------- Bang hội ----------

  defp guild_chat(%{guild: %{id: gid}}, from, text) do
    text =
      text
      |> String.replace(~r/[\p{Cc}\p{Cf}]/u, " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
      |> String.slice(0, 120)

    if text == "" do
      {:error, "Tin nhắn trống."}
    else
      msg =
        Map.merge(from, %{id: nil, text: text, guild: true, at: System.system_time(:millisecond)})

      Phoenix.PubSub.broadcast(HacLong.PubSub, Guilds.topic(gid), {:guild_chat, msg})
      {:ok, msg}
    end
  end

  defp guild_chat(_p, _from, _text), do: {:error, "Bạn chưa vào bang nào."}

  # Trả về {:ok, dữ_liệu} hoặc {:error, lý_do}. Sau mỗi thay đổi trả lại thông tin bang.
  defp guild("list", p, uid),
    do: {:ok, %{guilds: Guilds.list(p["q"] || ""), requested: Guilds.my_requests(uid)}}

  defp guild("info", _p, uid) do
    case Guilds.brief(uid) do
      nil ->
        {:ok, %{guild: nil}}

      b ->
        info =
          Guilds.info(b.id, uid)
          |> Map.merge(%{
            war: b.war,
            war_pending: b.war_pending,
            war_history: HacLong.GuildWars.history(b.id)
          })

        {:ok, %{guild: info}}
    end
  end

  defp guild(op, p, uid) do
    target = p["uid"]
    gid = p["id"]

    result =
      case op do
        "join" -> Guilds.join(uid, gid)
        "cancel" -> Guilds.cancel_request(uid, gid)
        "accept" -> Guilds.accept(uid, target)
        "reject" -> Guilds.reject(uid, target)
        "kick" -> Guilds.kick(uid, target)
        "promote" -> Guilds.set_role(uid, target, "officer")
        "demote" -> Guilds.set_role(uid, target, "member")
        "transfer" -> Guilds.transfer(uid, target)
        "leave" -> Guilds.leave(uid)
        "disband" -> Guilds.disband(uid)
        "settings" -> Guilds.settings(uid, p)
        "war_declare" -> HacLong.GuildWars.declare(uid, gid || Guilds.id_by_tag(p["tag"]))
        "war_accept" -> HacLong.GuildWars.answer(uid, true)
        "war_decline" -> HacLong.GuildWars.answer(uid, false)
        "war_surrender" -> HacLong.GuildWars.surrender(uid)
        _ -> {:error, "Thao tác không hợp lệ."}
      end

    with {:ok, msg} <- result do
      {:ok, info} = guild("info", p, uid)
      {:ok, Map.put(info, :msg, msg)}
    end
  end

  # ---------- Quản trị ----------

  defp admin_of(socket), do: %{id: socket.assigns.user_id, username: socket.assigns.username}

  defp target(%{"uid" => id}) when is_integer(id), do: id
  defp target(_), do: nil

  defp admin_char(op, %{"uid" => id} = p, socket) when is_integer(id) do
    with {:ok, msg} <- HacLong.Admin.run(admin_of(socket), op, id, p) do
      user = HacLong.Accounts.get_user(id)
      {:ok, %{msg: msg, user: user && Moderation.info(user)}}
    end
  end

  defp admin_char(_op, _p, _socket), do: {:error, "Chọn người chơi (tra cứu trước)."}

  defp admin("audit", p, _s) do
    days = if is_integer(p["days"]) and p["days"] in 1..90, do: p["days"], else: 1
    {:ok, %{audit: HacLong.Audit.run(days: days)}}
  end

  defp admin("gold_log", %{"uid" => id}, _s) when is_integer(id),
    do: {:ok, %{log: HacLong.Audit.gold_history(id)}}

  defp admin("admin_log", p, _s) do
    uid = if is_integer(p["uid"]), do: p["uid"]
    {:ok, %{log: HacLong.Admin.recent(50, uid)}}
  end

  defp admin("reports", _p, _s), do: {:ok, %{reports: Moderation.open_reports()}}

  # người đang online (Phase 5, K10)
  defp admin("online", _p, _s), do: {:ok, %{online: Session.online()}}

  defp admin("lookup", %{"name" => name}, _s) do
    case Moderation.find_user(name) do
      nil -> {:error, "Không tìm thấy \"#{name}\"."}
      u -> {:ok, %{user: Moderation.info(u)}}
    end
  end

  defp admin("resolve", %{"id" => id, "action" => action} = p, s)
       when action in ~w(dismiss mute ban) do
    report = Enum.find(Moderation.open_reports(), &(&1.id == id))

    cond do
      report == nil ->
        {:error, "Báo cáo không còn."}

      action == "dismiss" ->
        Moderation.resolve(id, s.assigns.user_id, action)

      true ->
        with :ok <- punish(action, report.target_id, p),
             do: Moderation.resolve(id, s.assigns.user_id, action)
    end
  end

  defp admin(op, %{"uid" => id} = p, _s)
       when op in ~w(mute unmute ban unban) and is_integer(id) do
    case op do
      "unmute" -> Moderation.unmute(id)
      "unban" -> Moderation.unban(id)
      _ -> punish(op, id, p)
    end
  end

  defp admin("announce", %{"text" => text}, _s) when is_binary(text) and text != "" do
    Chat.system("📢 " <> String.slice(String.trim(text), 0, 200))
    :ok
  end

  # Tặng quà qua hộp thư: cho một người (`uid`) hoặc mọi người (`all: true`).
  defp admin("gift", p, _s) do
    mail = %{
      subject: p["subject"] || "Quà từ Ban Quản Trị",
      body: p["body"] || "",
      gold: p["gold"] || 0,
      xp: p["xp"] || 0,
      items: p["items"] || %{}
    }

    # trần mỗi thư quản trị (`RULES.mail`), tránh gõ nhầm số; thư hệ thống (bán chợ, quà bang) không giới hạn
    cap = HacLong.Game.Data.rules().mail

    case p do
      _ when is_integer(mail.gold) and mail.gold > cap.max_gold ->
        {:error, "Mỗi thư tối đa #{cap.max_gold} vàng."}

      _ when is_integer(mail.xp) and mail.xp > cap.max_xp ->
        {:error, "Mỗi thư tối đa #{cap.max_xp} kinh nghiệm."}

      %{"all" => true} ->
        with {:ok, n} <- Mailbox.send_all(mail), do: {:ok, %{sent: n}}

      %{"uid" => id} when is_integer(id) ->
        with :ok <- Mailbox.send(id, mail), do: {:ok, %{sent: 1}}

      _ ->
        {:error, "Chọn người nhận."}
    end
  end

  defp admin("world_boss", _p, _s), do: {:ok, %{status: WorldBoss.spawn_now()}}

  # Golden Invasion ngay (Phase 7)
  defp admin("invasion", _p, _s), do: {:ok, %{invasion: HacLong.Invasion.start_now()}}

  defp admin(_op, _p, _s), do: {:error, "Lệnh quản trị không hợp lệ."}

  # `minutes`: số phút, hoặc nil/0 là vĩnh viễn
  defp punish("mute", id, p), do: Moderation.mute(id, minutes(p))

  defp punish("ban", id, p) do
    with :ok <- Moderation.ban(id, minutes(p), p["reason"]) do
      # đăng xuất ngay mọi thiết bị đang mở game
      HacLongWeb.Endpoint.broadcast("user_socket:#{id}", "disconnect", %{})
      :ok
    end
  end

  defp minutes(%{"minutes" => m}) when is_integer(m) and m > 0, do: m
  defp minutes(_), do: nil

  defp not_muted(uid) do
    user = Accounts.get_user(uid)

    if Accounts.muted?(user) do
      until =
        if user.muted_until.year >= 9999,
          do: "vĩnh viễn",
          else:
            "đến " <> Calendar.strftime(DateTime.add(user.muted_until, 7 * 3600), "%H:%M %d/%m")

      {:error, "Bạn đang bị cấm chat #{until}."}
    else
      :ok
    end
  end

  defp limit(key, n, window) do
    case RateLimit.hit(key, n, window) do
      :ok -> :ok
      {:error, _} -> {:error, "Thao tác quá nhanh."}
    end
  end

  # 5 tin mỗi 10 giây, chống spam.
  defp chat_limit(uid) do
    case RateLimit.hit({:chat, uid}, 5, 10_000) do
      :ok -> :ok
      {:error, secs} -> {:error, "Chat chậm lại chút, đợi #{secs} giây."}
    end
  end

  @impl true
  def handle_info(:push_map, socket) do
    push(socket, "chat_history", %{
      messages: Enum.reject(Chat.history(), &(&1.uid in socket.assigns.blocked))
    })

    push(socket, "world_boss", WorldBoss.status())
    push(socket, "invasion", HacLong.Invasion.status())
    {:noreply, follow_map(socket, Session.get(socket.assigns.user_id))}
  end

  def handle_info({:invasion, status}, socket) do
    push(socket, "invasion", status)
    {:noreply, socket}
  end

  def handle_info({:world_boss, status}, socket) do
    push(socket, "world_boss", status)
    {:noreply, socket}
  end

  # Bang của mình vừa đổi (vào, rời, bị đuổi, giải tán): đổi kênh chat bang.
  def handle_info({:guild, brief}, socket) do
    old = socket.assigns[:guild_id]
    new = brief && brief.id

    if old != new do
      if old, do: Phoenix.PubSub.unsubscribe(HacLong.PubSub, Guilds.topic(old))
      if new, do: Phoenix.PubSub.subscribe(HacLong.PubSub, Guilds.topic(new))
    end

    push(socket, "guild", %{guild: brief})
    {:noreply, assign(socket, :guild_id, new)}
  end

  def handle_info({:guild_chat, msg}, socket) do
    unless msg.uid in socket.assigns.blocked, do: push(socket, "chat", msg)
    {:noreply, socket}
  end

  def handle_info({:party, _pid}, socket) do
    push(socket, "party", %{party: party_view(socket.assigns.user_id)})
    {:noreply, socket}
  end

  def handle_info({:party_invite, nil}, socket) do
    push(socket, "party_invite", %{from: nil})
    {:noreply, socket}
  end

  def handle_info({:party_invite, from}, socket) do
    name = (p = Session.get(from)) && p.name
    push(socket, "party_invite", %{from: from, name: name})
    {:noreply, socket}
  end

  def handle_info({:friends, text}, socket) do
    push(socket, "friends", %{msg: text})
    {:noreply, socket}
  end

  # tin riêng: người đã chặn thì không nhận
  def handle_info({:dm, msg}, socket) do
    unless msg.from in socket.assigns.blocked, do: push(socket, "dm", msg)
    {:noreply, socket}
  end

  def handle_info({:pk_invite, inv}, socket) do
    push(socket, "pk_invite", %{invite: inv})
    {:noreply, socket}
  end

  def handle_info({:pk_result, view}, socket) do
    push(socket, "pk_result", view)
    {:noreply, socket}
  end

  def handle_info({:trade_request, req}, socket) do
    push(socket, "trade_request", req)
    {:noreply, socket}
  end

  def handle_info({:trade, view}, socket) do
    push(socket, "trade", %{trade: view})
    {:noreply, socket}
  end

  def handle_info({:party_chat, msg}, socket) do
    unless msg.uid in socket.assigns.blocked, do: push(socket, "chat", msg)
    {:noreply, socket}
  end

  def handle_info({:shared_hp, key, hp, n}, socket) do
    push(socket, "shared", %{key: key, hp: hp, n: n})
    {:noreply, socket}
  end

  def handle_info({:mail, unread}, socket) do
    push(socket, "mail", %{unread: unread})
    {:noreply, socket}
  end

  def handle_info({:notice, msg}, socket) do
    push(socket, "notice", %{msg: msg})
    {:noreply, socket}
  end

  def handle_info({:chat, msg}, socket) do
    unless msg.uid in socket.assigns.blocked, do: push(socket, "chat", msg)
    {:noreply, socket}
  end

  def handle_info({:player, player, origin}, socket) do
    if origin != self(), do: push(socket, "player", %{player: present(player)})
    {:noreply, follow_map(socket, player)}
  end

  def handle_info({:map_state, id, snap}, socket) do
    if id == socket.assigns.map, do: push(socket, "map", snap)
    {:noreply, socket}
  end

  # Tiến Lên (Phase 17): tin của phòng / sảnh; tin lạ khác thì bỏ qua
  def handle_info(msg, socket) do
    case HacLongWeb.TienLenHandler.handle_info(msg, socket) do
      :skip -> {:noreply, socket}
      other -> other
    end
  end

  # Nhân vật sang bản đồ khác: đổi kênh PubSub đang nghe và gửi ngay trạng thái bản đồ mới.
  defp follow_map(socket, player) do
    map_id = player && player.pos.map

    if map_id == socket.assigns.map do
      socket
    else
      if old = socket.assigns.map, do: unsubscribe(old)

      if map_id do
        if Maps.get(map_id).private do
          push(socket, "map", %{
            map: map_id,
            phase: HacLong.World.Clock.phase(),
            monsters: [],
            nodes: [],
            players: []
          })
        else
          Phoenix.PubSub.subscribe(HacLong.PubSub, MapServer.topic(map_id))
          push(socket, "map", MapServer.snapshot(map_id))
        end
      end

      assign(socket, :map, map_id)
    end
  end

  defp unsubscribe(map_id) do
    unless Maps.get(map_id).private,
      do: Phoenix.PubSub.unsubscribe(HacLong.PubSub, MapServer.topic(map_id))
  end

  # Kèm các chỉ số tính sẵn (máu tối đa, tấn công, giá nghỉ trọ...) cho client hiển thị.
  # sự kiện đang diễn ra (quà đổi được) hoặc sự kiện sắp tới
  defp event_view(player) do
    case HacLong.Game.Events.current() do
      nil ->
        {e, days} = HacLong.Game.Events.next(Daily.today())
        %{active: false, next: %{name: e.name, icon: e.icon, days: days}}

      e ->
        %{
          active: true,
          id: e.id,
          name: e.name,
          icon: e.icon,
          desc: e.desc,
          token: e.token,
          shop: HacLong.Game.Events.shop(e, player)
        }
    end
  end

  defp slay_left(%{battle: %{live: true, over: false, encounter: %{until: until}}})
       when is_integer(until),
       do: max(0, until - System.system_time(:millisecond))

  defp slay_left(_), do: nil

  defp present(nil), do: nil

  defp present(player) do
    # có việc mới hoặc việc đã xong chờ trả: hiện dấu "!" trên đầu Trưởng Làng
    ready =
      Quests.available(player) != [] or
        Enum.any?(Map.keys(player.quests.active), &Quests.complete?(player, Data.quest(&1)))

    view =
      player
      |> Engine.view()
      |> Map.merge(%{
        questReady: ready,
        dailyReady: Daily.ready?(player),
        dailyLeft: Daily.seconds_left(),
        # đồ sát: số mili giây còn lại của lượt (client tự đếm theo đồng hồ máy mình, không lệch giờ)
        slayLeft: slay_left(player),
        tutorial: Tutorial.view(player),
        achievements: Achievements.view(player),
        chestReady: player[:chest_day] != Daily.today(),
        event: event_view(player),
        crafting: %{
          cook: HacLong.Game.Crafting.level(player, :cook),
          smith: HacLong.Game.Crafting.level(player, :smith),
          smithGold: HacLong.Game.Crafting.smith_gold(player)
        },
        chests:
          Enum.map(Chests.tiers(), fn t ->
            %{
              id: t.id,
              name: t.name,
              price: Chests.price(t, player.level),
              odds: Map.new(t.weights, fn {r, w} -> {r, w} end)
            }
          end)
      })

    Map.put(player, :view, view)
  end

  # đóng tab thì hủy giao dịch đang dở (người kia khỏi phải chờ)
  @impl true
  def terminate(_reason, socket) do
    if uid = socket.assigns[:user_id], do: Trade.cancel(uid)
    :ok
  end
end

defmodule HacLong.Friends do
  @moduledoc """
  Bạn bè và nhắn tin riêng.

  - Kết bạn (`request/2`): gửi lời mời; người kia nhận (`accept/2`) thì thành bạn của nhau
    (mỗi chiều một dòng trong bảng `friends`). Hai người cùng mời nhau thì thành bạn luôn.
    Người đã chặn mình thì không mời được. Tối đa `@max` bạn.
  - Tin nhắn riêng (`send_message/3`) chỉ gửi cho bạn bè; lưu trong `private_messages`, người
    nhận đang online thì nhận ngay (`{:dm, tin}` trên kênh người chơi), không thì thấy số tin
    chưa đọc khi vào game. Mở cuộc trò chuyện (`history/2`) là đánh dấu đã đọc.
  - Thay đổi danh sách bạn thì cả hai nhận `{:friends, thông_báo | nil}`.
  """
  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Accounts.User
  alias HacLong.Game.{Character, Names, Session}

  @max 50
  @max_text 200
  @history 60

  def max, do: @max

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp online?(uid), do: Registry.lookup(HacLong.Game.Registry, uid) != []

  defp notify(uid, text),
    do: Phoenix.PubSub.broadcast(HacLong.PubSub, Session.topic(uid), {:friends, text})

  defp name_of(uid) do
    Repo.one(
      from u in User,
        left_join: c in Character,
        on: c.user_id == u.id,
        where: u.id == ^uid,
        select: coalesce(c.name, u.username)
    )
  end

  defp row(a, b), do: from(f in "friends", where: f.user_id == ^a and f.friend_id == ^b)

  def friends?(a, b),
    do: admin?(a) or admin?(b) or Repo.exists?(row(a, b) |> where([f], f.accepted))

  # ---------- Quản trị là bạn mặc định (DECISIONS "Quản trị là bạn mặc định") ----------

  @doc "Mã người (nhân vật) có vai trò quản trị: là bạn mặc định của mọi người, nhắn riêng được, không xóa được."
  def admin_ids,
    do: Repo.all(from(u in User, where: u.role == "admin", select: u.id))

  def admin?(uid), do: uid in admin_ids()

  defp people_ids([]), do: []

  defp people_ids(ids) do
    from(u in User,
      where: u.id in ^ids,
      left_join: c in Character,
      on: c.user_id == u.id,
      select: %{id: u.id, name: coalesce(c.name, u.username), level: c.level, cls: c.cls}
    )
    |> Repo.all()
  end

  # người đã nhắn tin với `uid` (cả hai chiều), trừ những người trong `except`
  defp talked_with(uid, except) do
    from(m in "private_messages",
      where: m.from_id == ^uid or m.to_id == ^uid,
      select: fragment("CASE WHEN ? = ? THEN ? ELSE ? END", m.from_id, ^uid, m.to_id, m.from_id),
      distinct: true
    )
    |> Repo.all()
    |> Enum.reject(&(&1 in except or &1 == uid))
  end

  # chặn theo tài khoản (DECISIONS "Nhiều nhân vật")
  defp blocked_by?(target, uid), do: HacLong.Moderation.blocked_by?(target, uid)

  defp count(uid),
    do: Repo.aggregate(from(f in "friends", where: f.user_id == ^uid and f.accepted), :count)

  # ---------- Danh sách ----------

  @doc """
  Bạn bè, lời mời đến và lời mời đã gửi của `uid`:
  `%{friends: [%{id, name, level, cls, online, unread}], incoming: [..], outgoing: [..], unread}`.
  """
  def list(uid) do
    people = fn q ->
      from(f in q,
        join: u in User,
        on: u.id == f.other,
        left_join: c in Character,
        on: c.user_id == u.id,
        select: %{id: u.id, name: coalesce(c.name, u.username), level: c.level, cls: c.cls}
      )
      |> Repo.all()
    end

    mine =
      from(f in "friends",
        where: f.user_id == ^uid,
        select: %{other: f.friend_id, accepted: f.accepted}
      )

    theirs =
      from(f in "friends",
        where: f.friend_id == ^uid and not f.accepted,
        select: %{other: f.user_id}
      )

    friends_q = from(f in subquery(mine), where: f.accepted)
    outgoing_q = from(f in subquery(mine), where: not f.accepted)
    incoming_q = subquery(theirs)

    unread = unread_by_sender(uid)

    deco = fn l, extra ->
      Enum.map(
        l,
        &Map.merge(
          &1,
          Map.merge(%{online: online?(&1.id), unread: Map.get(unread, &1.id, 0)}, extra)
        )
      )
    end

    real = people.(friends_q)
    admins = admin_ids()
    me_admin? = uid in admins

    # người chơi thường: Quản trị luôn đứng đầu danh sách bạn (không xóa được)
    pinned =
      if me_admin?,
        do: [],
        else: people_ids((admins -- [uid]) -- Enum.map(real, & &1.id)) |> deco.(%{admin: true})

    friends =
      pinned ++
        (real
         |> deco.(%{admin: false})
         |> Enum.map(&Map.put(&1, :admin, &1.id in admins))
         |> Enum.sort_by(&{!&1.online, -&1.unread, &1.name}))

    # Quản trị: tab riêng những người chơi đã nhắn tin (không phải bạn thật)
    others =
      if me_admin?,
        do:
          people_ids(talked_with(uid, Enum.map(real, & &1.id)))
          |> deco.(%{})
          |> Enum.sort_by(&{-&1.unread, !&1.online, &1.name}),
        else: []

    %{
      friends: friends,
      others: others,
      admin: me_admin?,
      incoming: people.(incoming_q),
      outgoing: people.(outgoing_q),
      unread: (friends ++ others) |> Enum.map(& &1.unread) |> Enum.sum(),
      max: @max
    }
  end

  defp unread_by_sender(uid) do
    from(m in "private_messages",
      where: m.to_id == ^uid and is_nil(m.read_at),
      group_by: m.from_id,
      select: {m.from_id, count()}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Tổng số tin riêng chưa đọc (chỉ tính tin từ bạn bè)."
  def unread(uid) do
    admins = admin_ids()

    q =
      from m in "private_messages",
        left_join: f in "friends",
        on: f.user_id == m.to_id and f.friend_id == m.from_id and f.accepted,
        where: m.to_id == ^uid and is_nil(m.read_at),
        select: count()

    # Quản trị đọc tin của mọi người; người chơi thường đếm tin từ bạn và từ Quản trị
    q =
      if uid in admins,
        do: q,
        else: where(q, [m, f], not is_nil(f.user_id) or m.from_id in ^admins)

    Repo.one(q) || 0
  end

  # ---------- Kết bạn ----------

  @doc "Tìm người chơi theo tên nhân vật rồi mời kết bạn."
  def request_by_name(uid, name) when is_binary(name) do
    key = Names.key(name)

    case Repo.one(from c in Character, where: c.name_key == ^key, select: c.user_id) do
      nil -> {:error, "Không có nhân vật tên này."}
      target -> request(uid, target)
    end
  end

  def request_by_name(_uid, _), do: {:error, "Tên không hợp lệ."}

  def request(uid, target) do
    cond do
      uid == target ->
        {:error, "Không tự kết bạn với mình được."}

      not Repo.exists?(from c in Character, where: c.user_id == ^target) ->
        {:error, "Không tìm thấy người chơi."}

      friends?(uid, target) ->
        {:error, "Hai người đã là bạn."}

      Repo.exists?(row(uid, target)) ->
        {:error, "Đã gửi lời mời rồi, chờ người kia nhận."}

      count(uid) >= @max ->
        {:error, "Bạn đã có đủ #{@max} bạn."}

      blocked_by?(target, uid) ->
        {:error, "Không gửi được lời mời."}

      # người kia đã mời mình trước: thành bạn luôn
      Repo.exists?(row(target, uid)) ->
        accept(uid, target)

      true ->
        Repo.insert_all("friends", [%{user_id: uid, friend_id: target, inserted_at: now()}])
        notify(target, "👋 #{name_of(uid)} muốn kết bạn với bạn.")
        notify(uid, nil)
        {:ok, "Đã gửi lời mời kết bạn."}
    end
  end

  @doc "`uid` nhận lời mời kết bạn của `from`."
  def accept(uid, from) do
    cond do
      not Repo.exists?(row(from, uid) |> where([f], not f.accepted)) ->
        {:error, "Lời mời không còn nữa."}

      count(uid) >= @max ->
        {:error, "Bạn đã có đủ #{@max} bạn."}

      true ->
        Repo.transaction(fn ->
          Repo.update_all(row(from, uid), set: [accepted: true])

          Repo.insert_all(
            "friends",
            [%{user_id: uid, friend_id: from, accepted: true, inserted_at: now()}],
            on_conflict: {:replace, [:accepted]},
            conflict_target: [:user_id, :friend_id]
          )
        end)

        notify(from, "🤝 #{name_of(uid)} đã nhận lời kết bạn.")
        notify(uid, nil)
        {:ok, "Đã kết bạn với #{name_of(from)}."}
    end
  end

  @doc "`uid` từ chối lời mời của `from` (hoặc rút lời mời mình đã gửi cho `from`)."
  def decline(uid, from) do
    Repo.delete_all(row(from, uid) |> where([f], not f.accepted))
    Repo.delete_all(row(uid, from) |> where([f], not f.accepted))
    notify(uid, nil)
    notify(from, nil)
    {:ok, "Đã bỏ lời mời."}
  end

  def remove(uid, other) do
    if admin?(other) and not admin?(uid),
      do: {:error, "Không xóa được Quản trị khỏi danh sách bạn."},
      else: do_remove(uid, other)
  end

  defp do_remove(uid, other) do
    Repo.delete_all(row(uid, other))
    Repo.delete_all(row(other, uid))
    notify(uid, nil)
    notify(other, nil)
    {:ok, "Đã xóa khỏi danh sách bạn."}
  end

  # ---------- Tin nhắn riêng ----------

  defp clean(text) do
    text
    |> String.replace(~r/[\p{Cc}\p{Cf}]/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, @max_text)
  end

  @doc "Gửi tin riêng cho bạn `to`. Trả về `{:ok, tin}` hoặc `{:error, lý_do}`."
  def send_message(uid, to, text) when is_binary(text) do
    text = clean(text)

    cond do
      text == "" ->
        {:error, "Tin nhắn trống."}

      not friends?(uid, to) ->
        {:error, "Chỉ nhắn riêng được cho bạn bè."}

      true ->
        at = now()

        {1, [%{id: id}]} =
          Repo.insert_all(
            "private_messages",
            [%{from_id: uid, to_id: to, text: text, inserted_at: at}],
            returning: [:id]
          )

        msg = %{id: id, from: uid, to: to, name: name_of(uid), text: text, at: at, read: false}

        for u <- [to, uid],
            do: Phoenix.PubSub.broadcast(HacLong.PubSub, Session.topic(u), {:dm, msg})

        {:ok, msg}
    end
  end

  def send_message(_uid, _to, _text), do: {:error, "Tin nhắn không hợp lệ."}

  @doc "Cuộc trò chuyện giữa `uid` và `other` (mới nhất ở cuối); đánh dấu tin đến là đã đọc."
  def history(uid, other) do
    msgs =
      from(m in "private_messages",
        where:
          (m.from_id == ^uid and m.to_id == ^other) or (m.from_id == ^other and m.to_id == ^uid),
        order_by: [desc: m.id],
        limit: @history,
        select: %{
          id: m.id,
          from: m.from_id,
          to: m.to_id,
          text: m.text,
          at: m.inserted_at,
          read: not is_nil(m.read_at)
        }
      )
      |> Repo.all()
      |> Enum.reverse()

    from(m in "private_messages",
      where: m.to_id == ^uid and m.from_id == ^other and is_nil(m.read_at)
    )
    |> Repo.update_all(set: [read_at: now()])

    %{with: %{id: other, name: name_of(other), online: online?(other)}, messages: msgs}
  end

  @doc "Xóa một tin (người gửi hoặc người nhận đều xóa được, xóa cho cả hai)."
  def delete_message(uid, id) when is_integer(id) do
    {n, _} =
      from(m in "private_messages",
        where: m.id == ^id and (m.from_id == ^uid or m.to_id == ^uid)
      )
      |> Repo.delete_all()

    if n > 0, do: {:ok, "Đã xóa tin."}, else: {:error, "Không có tin này."}
  end

  def delete_message(_uid, _id), do: {:error, "Tin không hợp lệ."}

  @doc "Xóa cả cuộc trò chuyện giữa `uid` và `other`."
  def clear(uid, other) when is_integer(other) do
    from(m in "private_messages",
      where:
        (m.from_id == ^uid and m.to_id == ^other) or (m.from_id == ^other and m.to_id == ^uid)
    )
    |> Repo.delete_all()

    {:ok, "Đã xóa cuộc trò chuyện."}
  end
end

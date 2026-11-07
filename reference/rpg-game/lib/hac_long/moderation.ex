defmodule HacLong.Moderation do
  @moduledoc """
  Giữ trật tự: người chơi chặn và báo cáo nhau; quản trị viên xử lý báo cáo, cấm chat,
  khóa tài khoản.

  - Chặn: chỉ ẩn chat của người bị chặn với người chặn (lọc ở `HacLongWeb.GameChannel`).
  - Báo cáo: chọn một tin nhắn còn trong lịch sử chat; nội dung lấy từ server nên không
    giả được. Mỗi người báo cáo một tin một lần.
  - Cấm chat / khóa tài khoản có thời hạn (`nil` phút/giờ là vĩnh viễn). Khóa thì mọi token
    bị thu hồi; kênh game bị ngắt ở `HacLongWeb.GameChannel`.
  - Người chơi được tra theo tên nhân vật (không phân biệt hoa thường) hoặc tên đăng nhập.
  """
  import Ecto.Query

  alias HacLong.{Accounts, Chat, Repo}
  alias HacLong.Accounts.User
  alias HacLong.Game.{Character, Names}

  @forever ~U[9999-12-31 00:00:00Z]

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  # ---------- Chặn ----------

  # Chặn theo tài khoản (DECISIONS "Nhiều nhân vật"): nhân vật nào của tài khoản chặn thì cả tài khoản không thấy
  # chat của mọi nhân vật thuộc tài khoản bị chặn.
  def block(user_id, blocked_id) when is_integer(user_id) and is_integer(blocked_id) do
    if blocked_id in Accounts.account_rows(user_id) do
      {:error, "Không tự chặn mình được."}
    else
      Repo.insert_all(
        "user_blocks",
        [%{user_id: user_id, blocked_id: blocked_id, inserted_at: now()}],
        on_conflict: :nothing
      )

      :ok
    end
  end

  def block(_, _), do: {:error, "Không tự chặn mình được."}

  def unblock(user_id, blocked_id) do
    mine = Accounts.account_rows(user_id)
    theirs = Accounts.account_rows(blocked_id)

    Repo.delete_all(
      from b in "user_blocks", where: b.user_id in ^mine and b.blocked_id in ^theirs
    )

    :ok
  end

  @doc "Những người tài khoản của `user_id` đã chặn: `[%{id, name}]` (để hiện danh sách)."
  def blocked(user_id) do
    Repo.all(
      from b in "user_blocks",
        join: u in User,
        on: u.id == b.blocked_id,
        left_join: c in Character,
        on: c.user_id == u.id,
        where: b.user_id in ^Accounts.account_rows(user_id),
        distinct: u.id,
        select: %{id: u.id, name: coalesce(c.name, u.username)}
    )
  end

  @doc "Mọi mã người chơi bị tài khoản của `user_id` chặn (cả các nhân vật khác của tài khoản bị chặn): để lọc chat."
  def blocked_ids(user_id) do
    user_id
    |> blocked()
    |> Enum.flat_map(&Accounts.account_rows(&1.id))
    |> MapSet.new()
  end

  @doc "Tài khoản của `target` có chặn tài khoản của `uid` không."
  def blocked_by?(target, uid) do
    Repo.exists?(
      from b in "user_blocks",
        where:
          b.user_id in ^Accounts.account_rows(target) and
            b.blocked_id in ^Accounts.account_rows(uid)
    )
  end

  # ---------- Báo cáo ----------

  def report(reporter_id, msg_id) do
    case Chat.find(msg_id) do
      nil ->
        {:error, "Tin nhắn đã quá cũ để báo cáo."}

      %{uid: 0} ->
        {:error, "Không báo cáo thông báo hệ thống."}

      %{uid: ^reporter_id} ->
        {:error, "Không tự báo cáo mình được."}

      msg ->
        Repo.insert_all(
          "chat_reports",
          [%{reporter_id: reporter_id, target_id: msg.uid, text: msg.text, inserted_at: now()}],
          on_conflict: :nothing
        )

        :ok
    end
  end

  @doc "Báo cáo chưa xử lý, cũ trước mới sau."
  def open_reports do
    Repo.all(
      from r in "chat_reports",
        join: t in User,
        on: t.id == r.target_id,
        left_join: tc in Character,
        on: tc.user_id == t.id,
        join: rp in User,
        on: rp.id == r.reporter_id,
        left_join: rc in Character,
        on: rc.user_id == rp.id,
        where: is_nil(r.resolved_at),
        order_by: [asc: r.id],
        select: %{
          id: r.id,
          text: r.text,
          target_id: t.id,
          target: coalesce(tc.name, t.username),
          reporter: coalesce(rc.name, rp.username),
          at: r.inserted_at
        }
    )
  end

  @doc "Đánh dấu báo cáo đã xử lý với `action` (\"dismiss\", \"mute\", \"ban\")."
  def resolve(report_id, admin_id, action) do
    {n, _} =
      Repo.update_all(
        from(r in "chat_reports", where: r.id == ^report_id and is_nil(r.resolved_at)),
        set: [resolved_at: now(), resolved_by_id: admin_id, action: action]
      )

    if n == 1, do: :ok, else: {:error, "Báo cáo không còn."}
  end

  # ---------- Cấm chat, khóa tài khoản ----------

  defp until(nil), do: @forever
  defp until(minutes), do: DateTime.add(now(), minutes * 60, :second)

  def mute(user_id, minutes), do: set(user_id, muted_until: until(minutes))
  def unmute(user_id), do: set(user_id, muted_until: nil)

  def ban(user_id, minutes, reason) do
    with :ok <- set(user_id, banned_until: until(minutes), ban_reason: reason) do
      Accounts.revoke_all(%User{id: Accounts.account_id(user_id)})
    end
  end

  def unban(user_id), do: set(user_id, banned_until: nil, ban_reason: nil)

  # cấm chat / khóa áp dụng cả tài khoản: mọi dòng (tài khoản và các nhân vật thêm)
  defp set(user_id, fields) do
    ids = Accounts.account_rows(user_id)
    {n, _} = Repo.update_all(from(u in User, where: u.id in ^ids), set: fields)
    if n >= 1, do: :ok, else: {:error, "Không tìm thấy người chơi."}
  end

  # ---------- Tra cứu ----------

  @doc "Tìm tài khoản theo tên nhân vật hoặc tên đăng nhập."
  def find_user(name) when is_binary(name) do
    key = Names.key(name)

    Repo.one(
      from u in User,
        left_join: c in Character,
        on: c.user_id == u.id,
        where: c.name_key == ^key or u.username == ^String.downcase(String.trim(name)),
        limit: 1
    )
  end

  def find_user(_), do: nil

  @doc "Thông tin cho quản trị viên."
  def info(%User{} = u) do
    c =
      Repo.one(
        from c in Character,
          where: c.user_id == ^u.id,
          select: map(c, [:name, :cls, :level, :gold, :kills])
      )

    # tài khoản và mọi nhân vật của nó (DECISIONS "Nhiều nhân vật"); lệnh sửa nhân vật dùng `id` (nhân vật này)
    acct = Accounts.account(u)

    %{
      id: u.id,
      username: acct.username,
      account_id: acct.id,
      characters: Accounts.characters(acct.id),
      role: acct.role,
      character: c,
      banned_until: Accounts.banned?(u) && u.banned_until,
      ban_reason: u.ban_reason,
      muted_until: Accounts.muted?(u) && u.muted_until,
      reports: Repo.one(from r in "chat_reports", where: r.target_id == ^u.id, select: count())
    }
  end

  @doc "Đổi vai trò tài khoản: `\"player\"`, `\"mod\"` hoặc `\"admin\"`."
  def set_role(username, role) do
    cond do
      role not in User.roles() ->
        roles = Enum.join(User.roles(), " / ")
        {:error, "Vai trò phải là #{roles}."}

      u = Repo.get_by(User, username: String.downcase(username)) ->
        u |> Ecto.Changeset.change(role: role) |> Repo.update()

      true ->
        {:error, "Không có tài khoản #{username}."}
    end
  end

  @doc "Cấp (vai trò `admin`) / thu (về `player`) quyền quản trị."
  def set_admin(username, admin?), do: set_role(username, if(admin?, do: "admin", else: "player"))
end

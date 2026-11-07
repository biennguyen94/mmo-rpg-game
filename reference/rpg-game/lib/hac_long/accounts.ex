defmodule HacLong.Accounts do
  @moduledoc "Tài khoản người chơi: đăng ký, đăng nhập, token đăng nhập, đổi mật khẩu."

  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Accounts.{Password, User, UserToken}

  # token đăng nhập có hạn 30 ngày
  @token_max_age 30 * 24 * 3600

  def get_user(id), do: Repo.get(User, id)

  def register(attrs) do
    %User{} |> User.registration_changeset(attrs) |> Repo.insert()
  end

  def authenticate(username, password) when is_binary(username) and is_binary(password) do
    # dòng nhân vật thêm (`account_id`) không phải tài khoản: không đăng nhập được
    user =
      Repo.one(
        from u in User,
          where:
            u.username == ^(username |> String.trim() |> String.downcase()) and
              is_nil(u.account_id)
      )

    cond do
      user && Password.verify(password, user.password_hash) ->
        if banned?(user), do: {:error, {:banned, user}}, else: {:ok, user}

      user ->
        {:error, :invalid}

      true ->
        # chạy hash giả để thời gian phản hồi không lộ tên đăng nhập có tồn tại hay không
        Password.no_user_verify()
        {:error, :invalid}
    end
  end

  def authenticate(_, _), do: {:error, :invalid}

  @doc "Tài khoản đang bị khóa?"
  def banned?(%User{banned_until: nil}), do: false
  def banned?(%User{banned_until: t}), do: DateTime.compare(t, DateTime.utc_now()) == :gt

  @doc "Đang bị cấm chat?"
  def muted?(%User{muted_until: nil}), do: false
  def muted?(%User{muted_until: t}), do: DateTime.compare(t, DateTime.utc_now()) == :gt

  # ---------- Token đăng nhập ----------
  # Token là chuỗi ngẫu nhiên 32 byte; database chỉ giữ mã băm của nó. Mỗi lần đăng nhập
  # một token mới (mỗi thiết bị một token), xóa token là đăng xuất thiết bị đó.

  @doc "Tạo token đăng nhập mới cho `user`."
  def sign_token(%User{id: id}) do
    token = :crypto.strong_rand_bytes(32)
    Repo.insert!(%UserToken{user_id: id, token_hash: hash(token)})
    Base.url_encode64(token, padding: false)
  end

  def verify_token(token) when is_binary(token) do
    cutoff = DateTime.add(DateTime.utc_now(), -@token_max_age, :second)

    with {:ok, raw} <- Base.url_decode64(token, padding: false),
         %User{} = user <-
           Repo.one(
             from t in UserToken,
               join: u in assoc(t, :user),
               where: t.token_hash == ^hash(raw) and t.inserted_at > ^cutoff,
               select: u
           ),
         false <- banned?(user) do
      {:ok, user}
    else
      _ -> {:error, :invalid}
    end
  end

  def verify_token(_), do: {:error, :invalid}

  @doc """
  Vé WebSocket dùng một lần cho tài khoản `user`, vào nhân vật `cid` (mã người chơi của nhân vật, mặc định chính tài
  khoản; xem `HacLong.Accounts.WsTicket`). `cid` không thuộc tài khoản thì nil.
  """
  def issue_ws_ticket(user, cid \\ nil)

  def issue_ws_ticket(%User{id: id}, nil), do: HacLong.Accounts.WsTicket.issue(id)

  def issue_ws_ticket(%User{id: id}, cid) when is_integer(cid) do
    if cid in account_rows(id), do: HacLong.Accounts.WsTicket.issue(cid)
  end

  def issue_ws_ticket(_, _), do: nil

  @doc """
  Dùng vé WebSocket: `{:ok, player, account}` (vé bị xóa; `player` là dòng của nhân vật, `account` là tài khoản đăng
  nhập — có thể là cùng một dòng) hoặc `:error` (sai / đã dùng / hết hạn / bị khóa).
  """
  def consume_ws_ticket(ticket) do
    with {:ok, id} <- HacLong.Accounts.WsTicket.consume(ticket),
         %User{} = user <- get_user(id),
         %User{} = acct <- account(user),
         false <- banned?(acct) do
      {:ok, user, acct}
    else
      _ -> :error
    end
  end

  # ---------- Nhiều nhân vật (DECISIONS "Nhiều nhân vật") ----------

  @max_characters HacLong.Game.Data.rules().account.max_characters

  def max_characters, do: @max_characters

  @doc "Mã tài khoản của dòng / mã người chơi (nhân vật thêm trỏ về tài khoản; tài khoản là chính nó)."
  def account_id(%User{account_id: nil, id: id}), do: id
  def account_id(%User{account_id: a}), do: a

  def account_id(uid) when is_integer(uid) do
    Repo.one(from u in User, where: u.id == ^uid, select: coalesce(u.account_id, u.id))
  end

  def account_id(_), do: nil

  @doc "Tài khoản (dòng đăng nhập) của `user`."
  def account(%User{account_id: nil} = u), do: u
  def account(%User{account_id: a}), do: get_user(a)

  @doc "Mọi mã người chơi của tài khoản chứa `uid` (tài khoản trước, rồi nhân vật thêm theo thứ tự tạo)."
  def account_rows(uid) when is_integer(uid) do
    case account_id(uid) do
      nil ->
        []

      a ->
        Repo.all(
          from u in User,
            where: u.id == ^a or u.account_id == ^a,
            order_by: [asc: u.id],
            select: u.id
        )
    end
  end

  @doc "Nhân vật khác cùng tài khoản với `uid` đã mở Rương Gia Truyền ngày `day` chưa."
  def sibling_chest?(uid, day) do
    case siblings(uid) do
      [] ->
        false

      ids ->
        Repo.exists?(
          from c in HacLong.Game.Character, where: c.user_id in ^ids and c.chest_day == ^day
        )
    end
  end

  @doc "Các mã người chơi khác cùng tài khoản với `uid`."
  def siblings(uid), do: account_rows(uid) -- [uid]

  @doc """
  Nhân vật của tài khoản `acct` (mã tài khoản), cũ trước: `[%{id, name, cls, level, rebirths, map, played_at}]`
  (`id`: mã người chơi để vào game).
  """
  def characters(acct) when is_integer(acct) do
    Repo.all(
      from u in User,
        join: c in HacLong.Game.Character,
        on: c.user_id == u.id,
        where: u.id == ^acct or u.account_id == ^acct,
        order_by: [asc: c.inserted_at, asc: u.id],
        select: %{
          id: u.id,
          name: c.name,
          cls: c.cls,
          level: c.level,
          rebirths: c.rebirths,
          map: c.map_id,
          played_at: c.updated_at
        }
    )
  end

  @doc """
  Chỗ để tạo nhân vật mới của tài khoản `acct`: mã người chơi chưa có nhân vật (dòng tài khoản, dòng thêm bỏ dở) hoặc
  dòng thêm mới tạo. `{:ok, uid}` / `{:error, msg}` khi đã đủ #{@max_characters} nhân vật.
  """
  def character_slot(%User{account_id: nil} = acct) do
    free =
      Repo.one(
        from u in User,
          left_join: c in HacLong.Game.Character,
          on: c.user_id == u.id,
          where: (u.id == ^acct.id or u.account_id == ^acct.id) and is_nil(c.id),
          order_by: [asc: u.id],
          limit: 1,
          select: u.id
      )

    cond do
      free ->
        {:ok, free}

      length(characters(acct.id)) >= @max_characters ->
        {:error, "Mỗi tài khoản tối đa #{@max_characters} nhân vật."}

      true ->
        # tên đăng nhập nội bộ (không đăng nhập được: có `account_id`, mật khẩu ngẫu nhiên)
        suffix = Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        row =
          Repo.insert!(%User{
            username: "~#{acct.id}~#{suffix}",
            password_hash: Password.hash(Base.encode64(:crypto.strong_rand_bytes(24))),
            role: "player",
            account_id: acct.id,
            inserted_at: now,
            updated_at: now
          })

        {:ok, row.id}
    end
  end

  def character_slot(_), do: {:error, "Không có tài khoản."}

  @doc """
  Xóa nhân vật `cid` của tài khoản `acct`: phải gõ đúng tên nhân vật và mật khẩu tài khoản. Đồ, vàng, bạn bè, bang, thư,
  hàng trên chợ của nhân vật đó mất hẳn (anh duyệt: không chuyển vào thùng chung). Chủ bang phải nhường trước.
  """
  def delete_character(%User{account_id: nil} = acct, cid, name, password) do
    c = cid in account_rows(acct.id) && Repo.get_by(HacLong.Game.Character, user_id: cid)

    cond do
      !c ->
        {:error, "Không có nhân vật này."}

      HacLong.Game.Names.key(to_string(name)) != c.name_key ->
        {:error, "Tên nhân vật không đúng."}

      not match?({:ok, _}, authenticate(acct.username, to_string(password))) ->
        {:error, "Mật khẩu không đúng."}

      Repo.exists?(from g in "guilds", where: g.leader_id == ^cid) ->
        {:error, "#{c.name} đang là chủ bang: nhường chủ bang hoặc giải tán bang trước."}

      true ->
        HacLong.Game.Session.stop(cid)
        HacLongWeb.Endpoint.broadcast("user_socket:#{cid}", "disconnect", %{})
        wipe_character(acct.id, cid)
        {:ok, c.name}
    end
  end

  def delete_character(_, _, _, _), do: {:error, "Không có tài khoản."}

  # Nhân vật thêm: xóa dòng `users` (mọi bảng gắn theo xóa kèm). Nhân vật trên dòng tài khoản: xóa nhân vật và dữ liệu
  # người chơi gắn theo mã đó, giữ những gì của tài khoản (token, câu hỏi bảo mật, chặn chat, báo cáo, yêu cầu mật khẩu).
  defp wipe_character(acct, cid) do
    Repo.transaction(fn ->
      HacLong.Game.Characters.delete!(cid)

      if cid == acct do
        for {table, cols} <- [
              {"friends", [:user_id, :friend_id]},
              {"private_messages", [:from_id, :to_id]},
              {"guild_members", [:user_id]},
              {"guild_requests", [:user_id]},
              {"mails", [:user_id]},
              {"market_listings", [:seller_id]},
              {"pk_matches", [:a_id, :b_id]},
              {"pvp", [:user_id]},
              {"rare_pets", [:user_id]},
              {"home_likes", [:owner_id, :liker_id]}
            ],
            col <- cols do
          Repo.delete_all(from t in table, where: field(t, ^col) == ^cid)
        end
      else
        Repo.delete_all(from u in User, where: u.id == ^cid and u.account_id == ^acct)
      end
    end)

    :ok
  end

  @doc "Đăng xuất thiết bị đang dùng `token`."
  def revoke_token(token) when is_binary(token) do
    with {:ok, raw} <- Base.url_decode64(token, padding: false) do
      Repo.delete_all(from t in UserToken, where: t.token_hash == ^hash(raw))
    end

    :ok
  end

  def revoke_token(_), do: :ok

  @doc "Đăng xuất mọi thiết bị của `user`."
  def revoke_all(%User{id: id}) do
    Repo.delete_all(from t in UserToken, where: t.user_id == ^id)
    :ok
  end

  @doc "Đổi mật khẩu: kiểm tra mật khẩu cũ, rồi thu hồi mọi token cũ."
  def change_password(%User{} = user, current, new) do
    with {:ok, _} <- authenticate(user.username, current) do
      cs = User.password_changeset(user, %{"password" => new})

      case Repo.update(cs) do
        {:ok, user} ->
          revoke_all(user)
          {:ok, user}

        error ->
          error
      end
    end
  end

  # ---------- Câu hỏi bảo mật (DECISIONS "Câu hỏi bảo mật") ----------

  @doc "Câu trả lời chuẩn hóa trước khi băm / so: bỏ khoảng trắng thừa, không phân biệt hoa thường."
  def normalize_answer(a) when is_binary(a),
    do:
      a
      |> :unicode.characters_to_nfc_binary()
      |> String.downcase()
      |> String.split()
      |> Enum.join(" ")

  def normalize_answer(_), do: nil

  @doc "Câu hỏi bảo mật của tài khoản `username` (id), nil nếu không có tài khoản / chưa đặt (tài khoản bot: nil)."
  def security_question(username) when is_binary(username) do
    case Repo.get_by(User, username: username |> String.trim() |> String.downcase()) do
      %User{role: role, security_question: q} when role != "bot" -> q
      _ -> nil
    end
  end

  def security_question(_), do: nil

  @doc """
  Quên mật khẩu: câu trả lời đúng thì đặt mật khẩu mới và đăng xuất mọi thiết bị. `{:ok, user}`,
  `{:error, :invalid}` (sai / không có tài khoản / chưa đặt câu hỏi) hoặc `{:error, changeset}` (mật khẩu mới không hợp lệ).
  """
  def recover(username, answer, new_password) when is_binary(username) do
    u = Repo.get_by(User, username: username |> String.trim() |> String.downcase())
    a = normalize_answer(answer)

    cond do
      u == nil or u.role == "bot" or u.security_answer_hash == nil or a == nil ->
        Password.no_user_verify()
        {:error, :invalid}

      not Password.verify(a, u.security_answer_hash) ->
        {:error, :invalid}

      true ->
        case Repo.update(User.password_changeset(u, %{"password" => new_password})) do
          {:ok, u} ->
            revoke_all(u)
            {:ok, u}

          error ->
            error
        end
    end
  end

  def recover(_, _, _), do: {:error, :invalid}

  @doc "Đặt / đổi câu hỏi bảo mật: cần mật khẩu hiện tại."
  def set_security(%User{} = user, current, question, answer) do
    with {:ok, _} <- authenticate(user.username, current) do
      user
      |> User.security_changeset(%{"question" => question, "answer" => answer})
      |> Repo.update()
    end
  end

  defp hash(raw), do: :crypto.hash(:sha256, raw)
end

defmodule Mu.Mail do
  @moduledoc """
  Hộp thư hệ thống (`KB_GAME_DESIGN §19.10`, P2-13). Mail theo nhân vật, do hệ thống gửi
  (`WELCOME` khi tạo nhân vật, `SYSTEM` thông báo, `GIFT` có Zen / item). Hết hạn sau
  `mail.expireDays` ngày: không hiện, không nhận được.

  - `list/1`: mail còn hạn, mới trước (tối đa `mail.maxPerCharacter`), rồi đánh dấu đã đọc (mở
    panel thì tắt badge). Cờ `read` trả về là trạng thái **trước** khi mở.
  - Nhận quà: `Mu.Game.Items.claim_mail/2` (một transaction, audit `MAIL_CLAIM`).
  - Xóa: chỉ mail đã đọc và không còn quà chưa nhận.
  """
  import Ecto.Query

  alias Mu.Repo
  alias Mu.Game.{Character, Config, Data}

  defmodule Message do
    @moduledoc "Bảng `mail` (migration 20261004000000, CHANGE_REASON P2-13)."
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "mail" do
      field :character_id, :binary_id
      field :kind, :string
      field :title, :string
      field :body, :string, default: ""
      field :zen, :integer, default: 0
      field :item_template_id, :string
      field :item_quantity, :integer
      field :read_at, :utc_datetime_usec
      field :claimed_at, :utc_datetime_usec
      field :created_at, :utc_datetime_usec
      field :expires_at, :utc_datetime_usec
    end
  end

  @kinds ~w(WELCOME SYSTEM GIFT)

  @doc """
  Gửi mail cho nhân vật. `attrs`: `kind`, `title`, tùy chọn `body`, `zen`, `item` (templateId),
  `quantity`. Báo Session đang online (badge). `{:ok, mail}` hoặc `{:error, lý_do}`.
  """
  def deliver(character_id, attrs) do
    with :ok <- validate(attrs) do
      now = DateTime.utc_now()

      mail =
        Repo.insert!(%Message{
          character_id: character_id,
          kind: attrs.kind,
          title: attrs.title,
          body: Map.get(attrs, :body, ""),
          zen: Map.get(attrs, :zen, 0),
          item_template_id: attrs[:item],
          item_quantity: if(attrs[:item], do: Map.get(attrs, :quantity, 1)),
          # giờ app (không dùng DEFAULT now(): cùng transaction thì trùng giờ, mất thứ tự)
          created_at: now,
          expires_at: DateTime.add(now, Config.get(["mail", "expireDays"]) * 86_400, :second)
        })

      notify(character_id)
      {:ok, mail}
    end
  end

  defp validate(%{kind: k, title: t} = a) when k in @kinds and is_binary(t) and t != "" do
    cond do
      String.length(t) > 80 ->
        {:error, :title_too_long}

      not (is_integer(Map.get(a, :zen, 0)) and Map.get(a, :zen, 0) >= 0) ->
        {:error, :bad_zen}

      a[:item] != nil and Data.item(a[:item]) == nil ->
        {:error, :unknown_item}

      a[:item] != nil and
          not (is_integer(Map.get(a, :quantity, 1)) and Map.get(a, :quantity, 1) >= 1) ->
        {:error, :bad_quantity}

      true ->
        :ok
    end
  end

  defp validate(_), do: {:error, :bad_mail}

  @doc "Gửi theo tên nhân vật (quản trị: `mix mu.mail`)."
  def deliver_to_name(name, attrs) do
    case Repo.one(
           from c in Character,
             where: fragment("lower(?)", c.name) == ^String.downcase(name),
             select: c.id
         ) do
      nil -> {:error, :no_character}
      id -> deliver(id, attrs)
    end
  end

  @doc "Mail chào mừng (gọi trong transaction tạo nhân vật)."
  def welcome(character_id) do
    w = Config.get(["mail", "welcome"])
    {:ok, _} = deliver(character_id, %{kind: "WELCOME", title: w["title"], body: w["body"]})
    :ok
  end

  defp live(character_id) do
    from m in Message,
      where: m.character_id == ^character_id and m.expires_at > ^DateTime.utc_now()
  end

  @doc "Số mail còn hạn chưa đọc."
  def unread(character_id),
    do: Repo.aggregate(from(m in live(character_id), where: is_nil(m.read_at)), :count)

  @doc "Danh sách mail còn hạn (mới trước), rồi đánh dấu đã đọc. Trả dạng gửi client."
  def list(character_id) do
    mails =
      Repo.all(
        from m in live(character_id),
          order_by: [desc: m.created_at, desc: m.id],
          limit: ^Config.get(["mail", "maxPerCharacter"])
      )

    ids = for m <- mails, is_nil(m.read_at), do: m.id

    if ids != [],
      do:
        Repo.update_all(from(m in Message, where: m.id in ^ids),
          set: [read_at: DateTime.utc_now()]
        )

    Enum.map(mails, &view/1)
  end

  @doc "Xóa mail đã đọc, không còn quà chưa nhận: `mail_id` hoặc `:read` (mọi mail như vậy)."
  def delete(character_id, :read) do
    {n, _} = Repo.delete_all(deletable(character_id))
    {:ok, n}
  end

  def delete(character_id, mail_id) when is_binary(mail_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(mail_id),
         {1, _} <- Repo.delete_all(from(m in deletable(character_id), where: m.id == ^uuid)) do
      {:ok, 1}
    else
      _ -> {:error, "INVALID_TARGET"}
    end
  end

  def delete(_, _), do: {:error, "INVALID_TARGET"}

  defp deletable(character_id) do
    from m in Message,
      where:
        m.character_id == ^character_id and not is_nil(m.read_at) and
          (not is_nil(m.claimed_at) or (m.zen == 0 and is_nil(m.item_template_id)))
  end

  @doc "Có quà (Zen hoặc item)."
  def reward?(m), do: m.zen > 0 or m.item_template_id != nil

  @doc "Dạng gửi client."
  def view(m) do
    %{
      id: m.id,
      kind: m.kind,
      title: m.title,
      body: m.body,
      zen: m.zen,
      item:
        if(m.item_template_id, do: %{templateId: m.item_template_id, quantity: m.item_quantity}),
      read: m.read_at != nil,
      claimed: m.claimed_at != nil,
      createdAt: DateTime.to_unix(m.created_at, :millisecond),
      expiresAt: DateTime.to_unix(m.expires_at, :millisecond)
    }
  end

  # Session đang giữ nhân vật này (nếu online) cập nhật badge
  defp notify(character_id) do
    with %{account_id: aid} <- Repo.get(Character, character_id),
         pid when is_pid(pid) <- Mu.Game.Session.whereis(aid) do
      send(pid, {:mail_changed, character_id})
    end

    :ok
  end
end

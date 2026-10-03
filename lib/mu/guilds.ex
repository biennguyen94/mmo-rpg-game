defmodule Mu.Guilds do
  @moduledoc """
  Guild trong DB (`KB_GAME_DESIGN §14`, P4-5; bảng `guilds`, `guild_members` — migration
  `20261005000000_create_guilds.exs`, có CHANGE_REASON). Chỉ truy cập DB; luật "ai được làm gì"
  và lời mời nằm ở `Mu.Guild` (một tiến trình, gọi các hàm này tuần tự).

  - Tạo: một transaction — khóa row nhân vật (`FOR UPDATE`), kiểm cấp ≥ `guild.createLevel`, đủ
    `guild.createZen`, chưa có guild, tên hợp lệ / chưa ai dùng; ghi guild + master; trừ Zen
    (`zen = zen − cost, version = version + 1`, CHECK `zen >= 0` là chốt cuối; audit Zen
    `GUILD_CREATE`). Trả Zen / version
    mới cho Session (như `Mu.Game.Items`).
  - Thêm thành viên / đổi vai trò: khóa row guild (`FOR UPDATE`) để đếm sĩ số / số assistant đúng.
  - Lỗi trả mã `KB_TECHNICAL §5`: `INVALID_TARGET` (tên sai), `FORBIDDEN` (tên đã có, đã có guild,
    đầy), `REQUIREMENT_NOT_MET` (cấp), `NOT_ENOUGH_ZEN`.
  """

  import Ecto.Query

  alias Mu.Repo
  alias Mu.Game.{Character, Config}

  defmodule Guild do
    @moduledoc false
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "guilds" do
      field :name, :string
      field :master_id, :binary_id
      field :created_at, :utc_datetime_usec, read_after_writes: true
    end
  end

  defmodule Member do
    @moduledoc false
    use Ecto.Schema
    @primary_key {:character_id, :binary_id, autogenerate: false}
    @foreign_key_type :binary_id
    schema "guild_members" do
      field :guild_id, :binary_id
      field :role, :string
      field :joined_at, :utc_datetime_usec
    end
  end

  @doc "Guild của nhân vật: `%{guild_id, name, role}` hoặc `nil`."
  def membership(cid) do
    Repo.one(
      from m in Member,
        join: g in Guild,
        on: g.id == m.guild_id,
        where: m.character_id == ^cid,
        select: %{guild_id: g.id, name: g.name, role: m.role}
    )
  end

  @doc "Guild theo tên (không phân biệt hoa thường) hoặc `nil`."
  def by_name(name) when is_binary(name),
    do: Repo.one(from g in Guild, where: fragment("lower(?)", g.name) == ^String.downcase(name))

  def by_name(_), do: nil

  def get(id), do: Repo.get(Guild, id)

  @doc "Thành viên (master → assistant → member, rồi theo thời gian vào)."
  def members(guild_id) do
    Repo.all(
      from m in Member,
        join: c in Character,
        on: c.id == m.character_id,
        where: m.guild_id == ^guild_id,
        order_by: [
          fragment("CASE ? WHEN 'master' THEN 0 WHEN 'assistant' THEN 1 ELSE 2 END", m.role),
          m.joined_at
        ],
        select: %{character_id: c.id, name: c.name, class: c.class, level: c.level, role: m.role}
    )
  end

  @doc """
  Tạo guild `name` cho nhân vật `cid` (master): `{:ok, %{guild_id, name, role}, %{zen, version}}`
  hoặc `{:error, code}`.
  """
  def create(cid, name) do
    cfg = Config.get(["guild"])
    name = if is_binary(name), do: String.trim(name), else: name

    Repo.transaction(fn ->
      c = Repo.one!(from(c in Character, where: c.id == ^cid, lock: "FOR UPDATE"))

      cond do
        not (is_binary(name) and Regex.match?(Regex.compile!(cfg["namePattern"]), name)) ->
          Repo.rollback("INVALID_TARGET")

        Repo.exists?(from m in Member, where: m.character_id == ^cid) ->
          Repo.rollback("FORBIDDEN")

        c.level < cfg["createLevel"] ->
          Repo.rollback("REQUIREMENT_NOT_MET")

        c.zen < cfg["createZen"] ->
          Repo.rollback("NOT_ENOUGH_ZEN")

        by_name(name) != nil ->
          Repo.rollback("FORBIDDEN")

        true ->
          g = Repo.insert!(%Guild{name: name, master_id: cid})

          Repo.insert!(%Member{
            character_id: cid,
            guild_id: g.id,
            role: "master",
            joined_at: now()
          })

          {1, [{zen, version}]} =
            Repo.update_all(
              from(ch in Character, where: ch.id == ^cid, select: {ch.zen, ch.version}),
              inc: [zen: -cfg["createZen"], version: 1]
            )

          # P5-M3: audit Zen trong cùng transaction (thay cho dòng log của P4M3-1)
          Mu.Game.ZenAudit.log(cid, -cfg["createZen"], zen, "GUILD_CREATE", g.id)

          {%{guild_id: g.id, name: g.name, role: "master"}, %{zen: zen, version: version}}
      end
    end)
    |> case do
      {:ok, {m, z}} -> {:ok, m, z}
      {:error, code} -> {:error, code}
    end
  rescue
    # hai người tạo cùng tên một lúc: index unique bắt
    Ecto.ConstraintError -> {:error, "FORBIDDEN"}
  end

  @doc "Thêm `cid` vào guild (vai trò member): kiểm còn chỗ, chưa có guild."
  def add_member(guild_id, cid) do
    max = Config.get(["guild", "maxMembers"])

    Repo.transaction(fn ->
      lock_guild!(guild_id)

      cond do
        Repo.exists?(from m in Member, where: m.character_id == ^cid) ->
          Repo.rollback("FORBIDDEN")

        count(guild_id) >= max ->
          Repo.rollback("FORBIDDEN")

        true ->
          Repo.insert!(%Member{
            character_id: cid,
            guild_id: guild_id,
            role: "member",
            joined_at: now()
          })
      end
    end)
    |> ok_or_error()
  end

  @doc "Bỏ `cid` khỏi guild (rời / bị đuổi)."
  def remove_member(cid) do
    {n, _} =
      Repo.delete_all(from m in Member, where: m.character_id == ^cid and m.role != "master")

    if n == 1, do: :ok, else: {:error, "INVALID_TARGET"}
  end

  @doc "Đổi vai trò `cid` sang `assistant` / `member` (tối đa `guild.maxAssistants` assistant)."
  def set_role(guild_id, cid, role) when role in ~w(assistant member) do
    max = Config.get(["guild", "maxAssistants"])

    Repo.transaction(fn ->
      lock_guild!(guild_id)

      assistants =
        Repo.aggregate(
          from(m in Member, where: m.guild_id == ^guild_id and m.role == "assistant"),
          :count
        )

      if role == "assistant" and assistants >= max, do: Repo.rollback("FORBIDDEN")

      {n, _} =
        Repo.update_all(
          from(m in Member,
            where: m.character_id == ^cid and m.guild_id == ^guild_id and m.role != "master"
          ),
          set: [role: role]
        )

      if n != 1, do: Repo.rollback("INVALID_TARGET")
    end)
    |> ok_or_error()
  end

  @doc "Giải tán guild (xóa guild, thành viên đi theo CASCADE)."
  def disband(guild_id) do
    {n, _} = Repo.delete_all(from g in Guild, where: g.id == ^guild_id)
    if n == 1, do: :ok, else: {:error, "INVALID_TARGET"}
  end

  def count(guild_id),
    do: Repo.aggregate(from(m in Member, where: m.guild_id == ^guild_id), :count)

  defp lock_guild!(guild_id),
    do: Repo.one!(from(g in Guild, where: g.id == ^guild_id, lock: "FOR UPDATE"))

  defp ok_or_error({:ok, _}), do: :ok
  defp ok_or_error({:error, code}), do: {:error, code}

  defp now, do: DateTime.utc_now()
end

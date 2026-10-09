defmodule HacLong.Leaderboard do
  @moduledoc """
  Bảng xếp hạng, đọc thẳng từ bảng `characters` (có chỉ mục cho từng kiểu xếp).

  - `:level`: nhiều lần chuyển sinh nhất, rồi cấp cao nhất (bằng cấp thì ai nhiều kinh nghiệm
    hơn xếp trên).
  - `:kills`: hạ nhiều quái nhất.
  - `:dragon`: những người đã hạ Hắc Long, ai hạ trước xếp trên.
  - `:tower`: tầng cao nhất đã vượt ở Tháp Vô Tận.
  - `{:class, lớp}` (Phase 5, H14): như `:level` nhưng chỉ một lớp, top `RULES.leaderboard.class_top`.

  `boards/0` gom mọi bảng (cả bang, đấu trường) và giữ trong ETS `RULES.leaderboard.refresh_s` giây
  (tắt khi `config :hac_long, :leaderboard_cache, false`, như trong test): đông người mở bảng thì
  database vẫn chỉ bị hỏi một lần mỗi chu kỳ. Hạng của mình (`me/1`) không cache.
  """
  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Game.{Achievements, Character, Data}

  @kinds [:level, :kills, :dragon, :tower]
  @rules Data.rules().leaderboard
  @classes Map.keys(Data.classes())
  @table __MODULE__

  def kinds, do: @kinds

  @doc "Tạo bảng ETS giữ cache (gọi một lần lúc khởi động, từ `HacLong.Application`)."
  def init_cache do
    if :ets.whereis(@table) == :undefined,
      do: :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

    :ok
  end

  @doc "Xóa cache (test)."
  def clear, do: :ets.whereis(@table) != :undefined && :ets.delete_all_objects(@table)

  @doc """
  Mọi bảng: `level`, `kills`, `dragon`, `tower`, `class` (`%{"dk" => [...], ...}`), `guild`,
  `guild_boss`, `arena`. Lấy từ cache nếu còn mới.
  """
  def boards(now \\ System.monotonic_time(:second)) do
    cache? = Application.get_env(:hac_long, :leaderboard_cache, true)

    case cache? && :ets.whereis(@table) != :undefined && :ets.lookup(@table, :boards) do
      [{:boards, at, data}] when now - at < @rules.refresh_s ->
        data

      _ ->
        data = build()

        if cache? && :ets.whereis(@table) != :undefined,
          do: :ets.insert(@table, {:boards, now, data})

        data
    end
  end

  defp build do
    @kinds
    |> Map.new(&{&1, top(&1, @rules.top)})
    |> Map.put(:class, Map.new(@classes, &{&1, top({:class, &1}, @rules.class_top)}))
    |> Map.put(:guild, HacLong.Guilds.top())
    |> Map.put(:guild_boss, HacLong.GuildQuests.boss_top())
    |> Map.put(:arena, HacLong.Arena.top())
  end

  @doc "Hạng của mình: `%{level: hạng chung, class: hạng trong lớp, cls}` (nil nếu chưa có nhân vật)."
  def me(user_id) do
    case Repo.one(from c in Character, where: c.user_id == ^user_id, select: c.cls) do
      nil -> nil
      cls -> %{level: level_rank(user_id), class: level_rank(user_id, cls), cls: cls}
    end
  end

  def top(kind, n \\ 10) when kind in @kinds or (is_tuple(kind) and elem(kind, 1) in @classes) do
    kind
    |> query()
    |> limit(^n)
    |> select([c], %{
      user_id: c.user_id,
      name: c.name,
      cls: c.cls,
      level: c.level,
      kills: c.kills,
      victory_at: c.victory_at,
      tower_best: c.tower_best,
      rebirths: c.rebirths,
      title: c.title
    })
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {row, i} ->
      %{row | title: Achievements.title_name(row.title)} |> Map.put(:rank, i)
    end)
  end

  defp query(:level),
    do:
      from(c in humans(),
        order_by: [desc: c.rebirths, desc: c.level, desc: c.xp, asc: c.id]
      )

  defp query({:class, cls}),
    do:
      from(c in humans(),
        where: c.cls == ^cls,
        order_by: [desc: c.rebirths, desc: c.level, desc: c.xp, asc: c.id]
      )

  defp query(:kills), do: from(c in humans(), order_by: [desc: c.kills, asc: c.id])

  defp query(:tower),
    do: from(c in humans(), where: c.tower_best > 0, order_by: [desc: c.tower_best, asc: c.id])

  defp query(:dragon),
    do:
      from(c in humans(),
        where: not is_nil(c.victory_at),
        order_by: [asc: c.victory_at, asc: c.id]
      )

  # Phase 16: người chơi AI không lên bảng xếp hạng
  defp humans,
    do:
      from(c in Character,
        join: u in HacLong.Accounts.User,
        on: u.id == c.user_id,
        where: u.role != "bot"
      )

  @doc "Hạng theo cấp của nhân vật thuộc `user_id` (nil nếu chưa có nhân vật); `cls`: chỉ tính trong lớp đó."
  def level_rank(user_id, cls \\ nil) do
    case Repo.one(
           from c in Character,
             where: c.user_id == ^user_id,
             select: {c.rebirths, c.level, c.xp, c.id}
         ) do
      nil ->
        nil

      {rb, lv, xp, id} ->
        base = if cls, do: from(c in humans(), where: c.cls == ^cls), else: humans()

        Repo.one(
          from c in base,
            where:
              c.rebirths > ^rb or
                (c.rebirths == ^rb and
                   (c.level > ^lv or (c.level == ^lv and c.xp > ^xp) or
                      (c.level == ^lv and c.xp == ^xp and c.id < ^id))),
            select: count()
        ) + 1
    end
  end
end

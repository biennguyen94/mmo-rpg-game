defmodule Mu.Leaderboard do
  @moduledoc """
  Bảng xếp hạng (P6-M1, P6-7; `KB_TECH_STACK §4` có `Leaderboard`). Một tiến trình giữ các bảng
  trong RAM, đọc lại DB khi có người xem mà bảng đã cũ hơn `ranking.refreshSeconds` (không đọc DB
  lúc khởi động, không timer).

  Bảng (`ranking.boards`):
  - `level`, `level_<class>` — cấp giảm dần, cùng cấp theo EXP giảm dần, rồi nhân vật tạo trước;
  - `guild` — tổng cấp thành viên giảm dần, rồi số thành viên, rồi guild lập trước.

  `get(board, cid)` → `%{board, rows, me, updatedAt}`: `rows` là top `ranking.top`; `me` là hạng của
  nhân vật `cid` (bảng guild: hạng guild của nhân vật) — tính thẳng bằng SQL, kể cả ngoài top.
  """
  use GenServer

  alias Mu.Game.Config
  alias Mu.Repo

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Bảng `board` kèm hạng của `cid`; bảng không có → `{:error, \"INVALID_TARGET\"}`."
  def get(board, cid), do: GenServer.call(__MODULE__, {:get, board, cid})

  @doc "Bỏ cache (test / quản trị)."
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(_), do: {:ok, %{boards: %{}, at: nil, mono: nil}}

  @impl true
  def handle_call({:get, board, cid}, _from, s) do
    if board in Config.get(["ranking", "boards"]) do
      s = if stale?(s), do: refresh(s), else: s

      {:reply,
       {:ok,
        %{
          board: board,
          rows: s.boards[board],
          me: me(board, cid),
          updatedAt: DateTime.to_unix(s.at, :millisecond)
        }}, s}
    else
      {:reply, {:error, "INVALID_TARGET"}, s}
    end
  end

  def handle_call(:reset, _from, _s), do: {:reply, :ok, %{boards: %{}, at: nil, mono: nil}}

  defp stale?(%{mono: nil}), do: true

  defp stale?(%{mono: m}),
    do: System.monotonic_time(:second) - m >= Config.get(["ranking", "refreshSeconds"])

  defp refresh(_s) do
    top = Config.get(["ranking", "top"])

    boards =
      for b <- Config.get(["ranking", "boards"]), into: %{} do
        {b, if(b == "guild", do: guild_rows(top), else: level_rows(class_of(b), top))}
      end

    %{boards: boards, at: DateTime.utc_now(), mono: System.monotonic_time(:second)}
  end

  defp class_of("level_" <> class), do: class
  defp class_of(_), do: nil

  defp level_rows(class, top) do
    sql = """
    SELECT c.name, c.class, c.level, g.name
    FROM characters c
    LEFT JOIN guild_members m ON m.character_id = c.id
    LEFT JOIN guilds g ON g.id = m.guild_id
    WHERE ($1::text IS NULL OR c.class = $1)
    ORDER BY c.level DESC, c.experience DESC, c.created_at ASC
    LIMIT $2
    """

    Repo.query!(sql, [class, top]).rows
    |> Enum.with_index(1)
    |> Enum.map(fn {[name, cls, level, guild], rank} ->
      %{rank: rank, name: name, class: cls, level: level, guild: guild}
    end)
  end

  @guild_totals """
  SELECT g.id, g.name, g.created_at, sum(c.level)::bigint AS total, count(*)::bigint AS members,
         max(CASE WHEN m.role = 'master' THEN c.name END) AS master
  FROM guilds g
  JOIN guild_members m ON m.guild_id = g.id
  JOIN characters c ON c.id = m.character_id
  GROUP BY g.id, g.name, g.created_at
  """

  defp guild_rows(top) do
    sql = """
    #{@guild_totals}
    ORDER BY total DESC, members DESC, g.created_at ASC
    LIMIT $1
    """

    Repo.query!(sql, [top]).rows
    |> Enum.with_index(1)
    |> Enum.map(fn {[_id, name, _at, total, members, master], rank} ->
      %{rank: rank, name: name, master: master, totalLevel: total, members: members}
    end)
  end

  # hạng của nhân vật `cid` (bảng cấp) hoặc guild của nó (bảng guild); không có → nil
  defp me("guild", cid) do
    sql = """
    WITH t AS (#{@guild_totals}),
         mine AS (SELECT t.* FROM t JOIN guild_members m ON m.guild_id = t.id
                  WHERE m.character_id = $1::uuid)
    SELECT (SELECT count(*) FROM t
            WHERE (t.total, t.members, mine.created_at) > (mine.total, mine.members, t.created_at)) + 1,
           mine.name, mine.total
    FROM mine
    """

    case Repo.query!(sql, [dump(cid)]).rows do
      [[rank, name, total]] -> %{rank: rank, name: name, totalLevel: total}
      [] -> nil
    end
  end

  defp me(board, cid) do
    class = class_of(board)

    sql = """
    WITH mine AS (SELECT * FROM characters WHERE id = $1::uuid)
    SELECT (SELECT count(*) FROM characters c
            WHERE ($2::text IS NULL OR c.class = $2)
              AND (c.level, c.experience, mine.created_at) > (mine.level, mine.experience, c.created_at)) + 1,
           mine.name, mine.class, mine.level
    FROM mine
    WHERE $2::text IS NULL OR mine.class = $2
    """

    case Repo.query!(sql, [dump(cid), class]).rows do
      [[rank, name, cls, level]] -> %{rank: rank, name: name, class: cls, level: level}
      [] -> nil
    end
  end

  defp dump(cid), do: Ecto.UUID.dump!(cid)
end

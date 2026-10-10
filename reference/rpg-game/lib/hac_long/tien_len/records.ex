defmodule HacLong.TienLen.Records do
  @moduledoc """
  Lưu ván Tiến Lên đã xong để xem lại (V5; thay `TienLen.Stats` của repo gốc, không có bảng
  xếp hạng). `record/1` do `HacLong.TienLen.RoomServer` gọi lúc hết ván: chỉ lưu khi có ít nhất
  một người thật; `player_ids` là người thật, `players` giữ cả bot (để hiện tên, hạng).

  Chỉ người đã ngồi trong ván xem được ván đó (`get/2`), như quyết định V6 của repo gốc.
  """
  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.TienLen.Room

  @doc "Lưu một ván. `{:ok, id}` hoặc `:skipped`."
  def record(%{players: players} = result) do
    ids = for %{user_id: id} <- players, is_integer(id), do: id

    if ids == [] do
      :skipped
    else
      now = DateTime.truncate(DateTime.utc_now(), :second)

      row = %{
        room_id: result.room_id,
        ref: result.ref,
        player_ids: Enum.uniq(ids),
        players: %{"list" => Enum.map(players, &player_row/1)},
        replay: result[:replay],
        inserted_at: now
      }

      case Repo.insert_all("tienlen_games", [row], on_conflict: :nothing, returning: [:id]) do
        {1, [%{id: id}]} -> {:ok, id}
        _ -> :skipped
      end
    end
  end

  defp player_row(p) do
    %{
      "user_id" => if(is_integer(p.user_id), do: p.user_id),
      "bot" => Room.bot_id?(p.user_id),
      "seat" => p.seat,
      "place" => p.place,
      "coins" => Map.get(p, :coins, 0),
      "instant" => Map.get(p, :instant, false)
    }
  end

  @doc "Các ván gần nhất của `uid` (mới trước): `%{id, at, players, place, coins}`."
  def list(uid, n \\ 20) do
    from(g in "tienlen_games",
      where: ^uid in g.player_ids,
      order_by: [desc: g.id],
      limit: ^n,
      select: %{id: g.id, at: g.inserted_at, players: g.players, replay: g.replay}
    )
    |> Repo.all()
    |> Enum.map(fn g ->
      me = Enum.find(g.players["list"], &(&1["user_id"] == uid)) || %{}
      names = names(g.replay)

      %{
        id: g.id,
        at: g.at,
        place: me["place"],
        coins: me["coins"] || 0,
        players: Enum.map(g.players["list"], &Map.put(&1, "name", names[&1["seat"]]))
      }
    end)
  end

  @doc "Ván `id` (kèm replay) nếu `uid` đã ngồi trong đó, không thì nil."
  def get(id, uid) when is_integer(id) do
    from(g in "tienlen_games",
      where: g.id == ^id and ^uid in g.player_ids,
      select: %{id: g.id, at: g.inserted_at, players: g.players, replay: g.replay}
    )
    |> Repo.one()
  end

  def get(_id, _uid), do: nil

  defp names(%{"seats" => seats}), do: Map.new(seats, &{&1["seat"], &1["name"]})
  defp names(_), do: %{}
end

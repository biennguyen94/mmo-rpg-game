defmodule MuWeb.Aoi do
  @moduledoc """
  Tầm nhìn (AOI) của một người chơi (`KB_TECHNICAL §3`, P3-M1). Hàm thuần: kênh giữ struct
  này và đưa vào mọi sự kiện map (`{:map_event, event, payload}`); kết quả là danh sách
  `{event, payload}` cần đẩy cho client.

  - Lưới ô `server.aoiCellSize` (16); thấy ô của mình + `server.aoiViewCells` (1) ô xung
    quanh (3×3 ô).
  - `entities`: bản sao mọi entity của map (payload `spawn`, cập nhật theo snapshot) để khi
    một entity vào tầm nhìn có ngay trạng thái hiện tại; `known`: các id client đang có.
  - Vào tầm nhìn → `spawn`; ra → `despawn`; snapshot chỉ còn entity client đang có,
    `removed` chỉ còn id client đang có; snapshot rỗng thì bỏ.
  - `combat` đẩy khi người đánh hoặc mục tiêu client đang thấy; `chat` và sự kiện khác
    đi thẳng (NORMAL vẫn cả map, P3-7).
  - Chính mình luôn trong tầm nhìn. Chưa biết vị trí mình thì thấy hết.
  """

  alias Mu.Game.Config

  defstruct self: nil, cell: nil, entities: %{}, known: MapSet.new(), size: 16, view: 1

  @type push :: {String.t(), map()}

  @doc "Tầm nhìn mới cho `self_id` từ danh sách payload `spawn` của map."
  @spec new(String.t(), [map()]) :: %__MODULE__{}
  def new(self_id, entities) do
    aoi = %__MODULE__{
      self: self_id,
      entities: Map.new(entities, &{&1.id, &1}),
      size: Config.get(["server", "aoiCellSize"]),
      view: Config.get(["server", "aoiViewCells"])
    }

    aoi = %{aoi | cell: self_cell(aoi)}
    %{aoi | known: MapSet.new(for {id, e} <- aoi.entities, visible?(aoi, id, e), do: id)}
  end

  @doc "`spawn` (trạng thái hiện tại) cho mọi entity client đang thấy: dùng khi vào map."
  @spec spawns(%__MODULE__{}) :: [push()]
  def spawns(aoi), do: for(id <- aoi.known, e = aoi.entities[id], do: {"spawn", e})

  @doc "Ô lưới chứa toạ độ (x, y)."
  @spec cell(integer(), integer(), pos_integer()) :: {integer(), integer()}
  def cell(x, y, size), do: {div(x, size), div(y, size)}

  @doc "Hai ô có nằm trong tầm `view` ô của nhau không."
  @spec near?({integer(), integer()}, {integer(), integer()}, non_neg_integer()) :: boolean()
  def near?({cx, cy}, {ox, oy}, view), do: abs(cx - ox) <= view and abs(cy - oy) <= view

  @doc "Xử lý một sự kiện map; trả struct mới và các sự kiện cần đẩy cho client."
  @spec event(%__MODULE__{}, String.t(), map()) :: {%__MODULE__{}, [push()]}
  def event(aoi, "spawn", %{id: id} = p) do
    aoi = %{aoi | entities: Map.put(aoi.entities, id, p)}

    if id == aoi.self do
      # mình xuất hiện lại (hồi sinh, lên cấp): tính lại cả tầm nhìn
      aoi = %{aoi | cell: self_cell(aoi), known: MapSet.put(aoi.known, id)}
      {aoi, rest} = refresh(aoi, Map.keys(aoi.entities))
      {aoi, [{"spawn", p} | rest]}
    else
      if visible?(aoi, id, p),
        do: {%{aoi | known: MapSet.put(aoi.known, id)}, [{"spawn", p}]},
        else: {%{aoi | known: MapSet.delete(aoi.known, id)}, []}
    end
  end

  def event(aoi, "despawn", %{id: id} = p) do
    known? = MapSet.member?(aoi.known, id)
    aoi = %{aoi | entities: Map.delete(aoi.entities, id), known: MapSet.delete(aoi.known, id)}
    {aoi, if(known?, do: [{"despawn", p}], else: [])}
  end

  def event(aoi, "snapshot", %{entities: deltas, removed: removed} = snap) do
    entities =
      Enum.reduce(deltas, aoi.entities, fn d, acc ->
        case Map.fetch(acc, d.id) do
          {:ok, e} -> Map.put(acc, d.id, Map.merge(e, d))
          :error -> acc
        end
      end)

    removed_known = Enum.filter(removed, &MapSet.member?(aoi.known, &1))

    aoi = %{
      aoi
      | entities: Map.drop(entities, removed),
        known: MapSet.difference(aoi.known, MapSet.new(removed))
    }

    old_cell = aoi.cell
    aoi = %{aoi | cell: self_cell(aoi)}
    # mình đổi ô → xét lại mọi entity; không thì chỉ các entity vừa đổi
    ids = if aoi.cell != old_cell, do: Map.keys(aoi.entities), else: Enum.map(deltas, & &1.id)
    known_before = aoi.known
    {aoi, changes} = refresh(aoi, ids)

    visible_deltas =
      Enum.filter(deltas, &(MapSet.member?(known_before, &1.id) and known?(aoi, &1.id)))

    snap_push =
      if visible_deltas == [] and removed_known == [],
        do: [],
        else: [{"snapshot", %{snap | entities: visible_deltas, removed: removed_known}}]

    {aoi, changes ++ snap_push}
  end

  def event(aoi, "combat", %{attacker: a, target: t} = p) do
    if known?(aoi, a) or known?(aoi, t), do: {aoi, [{"combat", p}]}, else: {aoi, []}
  end

  def event(aoi, event, payload), do: {aoi, [{event, payload}]}

  @doc "Client đang có entity `id` không (luôn đúng với chính mình)."
  @spec known?(%__MODULE__{}, String.t() | nil) :: boolean()
  def known?(aoi, id), do: id == aoi.self or MapSet.member?(aoi.known, id)

  # Xét lại `ids`: vào tầm nhìn → spawn (trạng thái hiện tại), ra → despawn
  defp refresh(aoi, ids) do
    Enum.reduce(ids, {aoi, []}, fn id, {aoi, pushes} ->
      e = aoi.entities[id]
      was = MapSet.member?(aoi.known, id)
      now = e != nil and visible?(aoi, id, e)

      cond do
        now and not was ->
          {%{aoi | known: MapSet.put(aoi.known, id)}, [{"spawn", e} | pushes]}

        was and not now ->
          {%{aoi | known: MapSet.delete(aoi.known, id)}, [{"despawn", %{id: id}} | pushes]}

        true ->
          {aoi, pushes}
      end
    end)
    |> then(fn {aoi, pushes} -> {aoi, Enum.reverse(pushes)} end)
  end

  defp visible?(aoi, id, _e) when id == aoi.self, do: true
  defp visible?(%{cell: nil}, _id, _e), do: true
  defp visible?(aoi, _id, e), do: near?(aoi.cell, cell(e.x, e.y, aoi.size), aoi.view)

  defp self_cell(aoi) do
    case aoi.entities[aoi.self] do
      %{x: x, y: y} -> cell(x, y, aoi.size)
      _ -> nil
    end
  end
end

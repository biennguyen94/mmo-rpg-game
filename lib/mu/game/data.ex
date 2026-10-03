defmodule Mu.Game.Data do
  @moduledoc """
  Dữ liệu gameplay tĩnh, đọc lúc biên dịch từ `priv/game_data/*.json` (học từ
  `HacLong.Game.Data` của repo nền, tách file theo loại như KB_TECH_STACK §7).

  Mỗi bản ghi phải có `sourceType`, `version`, `verified` (`KB_00_RULES §2`); thiếu thì
  biên dịch lỗi. Khóa giữ nguyên dạng chuỗi như trong JSON.
  """

  @dir Path.expand("../../../priv/game_data", __DIR__)
  @required ~w(sourceType version verified)

  load = fn file, key, id_key ->
    path = Path.join(@dir, file)
    records = path |> File.read!() |> Jason.decode!() |> Map.fetch!(key)

    for r <- records, k <- @required, not Map.has_key?(r, k) do
      raise "#{path}: bản ghi #{inspect(r[id_key])} thiếu trường #{k} (KB_00_RULES §2)"
    end

    {path, Map.new(records, &{&1[id_key], &1})}
  end

  {p1, classes} = load.("classes.json", "classes", "id")
  {p2, monsters} = load.("monsters.json", "monsters", "id")
  {p3, skills} = load.("skills.json", "skills", "id")
  {p4, drops} = load.("drops.json", "drops", "monsterId")
  for p <- [p1, p2, p3, p4], do: @external_resource(p)

  @classes classes
  @monsters monsters
  @skills skills
  @drops drops

  for {id, c} <- @classes, d = c["derived"], k <- @required, not Map.has_key?(d, k) do
    raise "classes.json: derived của #{id} thiếu #{k}"
  end

  @doc "Các class đang có dữ liệu (Phase 1: chỉ DK)."
  def classes, do: @classes

  @doc "Class theo id (`\"DK\"`), `nil` nếu không có."
  def class(id), do: Map.get(@classes, id)

  def monsters, do: @monsters
  def monster(id), do: Map.get(@monsters, id)

  def skills, do: @skills
  def skill(id), do: Map.get(@skills, id)

  @doc "Bảng rơi đồ của quái (`nil` nếu không có)."
  def drops(monster_id), do: Map.get(@drops, monster_id)
end

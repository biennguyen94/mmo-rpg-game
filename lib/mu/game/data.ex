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
  {p5, items} = load.("items.json", "items", "templateId")
  {p6, shops} = load.("shop.json", "shops", "npcId")
  for p <- [p1, p2, p3, p4, p5, p6], do: @external_resource(p)

  @classes classes
  @monsters monsters
  @skills skills
  @drops drops
  @items items
  @shops shops

  for {npc, shop} <- @shops, t <- shop["items"], not Map.has_key?(@items, t) do
    raise "shop.json: #{npc} bán #{t} không có trong items.json"
  end

  for {_, d} <- @drops,
      g <- d["groups"],
      e <- g["entries"],
      not Map.has_key?(@items, e["item"]) do
    raise "drops.json: #{e["item"]} không có trong items.json"
  end

  # skill (P2-M3): targetType hợp lệ, AOE có tâm, ALLY có effect heal/buff
  for {id, sk} <- @skills do
    case sk do
      %{"targetType" => t} when t in ~w(SINGLE POINT) ->
        :ok

      %{"targetType" => "AOE", "center" => c} when c in ~w(self target point) ->
        :ok

      %{"targetType" => "ALLY", "effect" => %{"kind" => "heal"}} ->
        :ok

      %{"targetType" => "ALLY", "effect" => %{"kind" => "buff", "stat" => st, "durationMs" => ms}}
      when st in ~w(defense damageBonus) and is_integer(ms) ->
        :ok

      _ ->
        raise "skills.json: #{id} targetType/center/effect sai"
    end
  end

  for {id, c} <- @classes, d = c["derived"], k <- @required, not Map.has_key?(d, k) do
    raise "classes.json: derived của #{id} thiếu #{k}"
  end

  @doc "Các class đang có dữ liệu (Phase 2: DK, DW, ELF)."
  def classes, do: @classes

  @doc "Class theo id (`\"DK\"`), `nil` nếu không có."
  def class(id), do: Map.get(@classes, id)

  def monsters, do: @monsters
  def monster(id), do: Map.get(@monsters, id)

  def skills, do: @skills
  def skill(id), do: Map.get(@skills, id)

  @doc "Template item (`priv/game_data/items.json`, sinh bởi `mix mu.items.import`)."
  def items, do: @items
  def item(template_id), do: Map.get(@items, template_id)

  @doc "Cửa hàng của NPC (`nil` nếu NPC không bán gì)."
  def shop(npc_id), do: Map.get(@shops, npc_id)

  @doc "Bảng rơi đồ của quái (`nil` nếu không có)."
  def drops(monster_id), do: Map.get(@drops, monster_id)
end

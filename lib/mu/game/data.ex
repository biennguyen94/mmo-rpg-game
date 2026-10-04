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
  {p7, quests} = load.("quests.json", "quests", "id")
  {p8, recipes} = load.("chaos.json", "recipes", "id")
  for p <- [p1, p2, p3, p4, p5, p6, p7, p8], do: @external_resource(p)

  @classes classes
  @monsters monsters
  @skills skills
  @drops drops
  @items items
  @shops shops
  @quests quests
  @recipes recipes
  @quest_order p7
               |> File.read!()
               |> Jason.decode!()
               |> Map.fetch!("quests")
               |> Enum.map(& &1["id"])

  for {npc, shop} <- @shops, t <- shop["items"], not Map.has_key?(@items, t) do
    raise "shop.json: #{npc} bán #{t} không có trong items.json"
  end

  for {_, d} <- @drops,
      g <- d["groups"],
      e <- g["entries"],
      not Map.has_key?(@items, e["item"]) do
    raise "drops.json: #{e["item"]} không có trong items.json"
  end

  # quest (P6-M2): mục tiêu kill / collect / level trỏ tới quái / item có thật, thưởng hợp lệ
  for {id, q} <- @quests do
    for o <- q["objectives"] do
      ok? =
        case o do
          %{"type" => "kill", "monsterId" => m, "count" => n} when is_integer(n) and n > 0 ->
            Map.has_key?(@monsters, m)

          %{"type" => "collect", "templateId" => t, "count" => n} when is_integer(n) and n > 0 ->
            Map.has_key?(@items, t)

          %{"type" => "level", "min" => n} when is_integer(n) ->
            true

          _ ->
            false
        end

      ok? || raise "quests.json: #{id} có mục tiêu sai #{inspect(o)}"
    end

    %{"exp" => exp, "zen" => zen, "items" => items} = q["rewards"]

    (is_integer(exp) and exp >= 0 and is_integer(zen) and zen >= 0 and
       Enum.all?(items, &(Map.has_key?(@items, &1["templateId"]) and &1["quantity"] > 0))) ||
      raise "quests.json: #{id} thưởng sai"
  end

  # Chaos Machine (P6-M3): đầu vào / kết quả trỏ tới item có thật, tỉ lệ trong 0..1
  for {id, r} <- @recipes do
    ok? =
      is_integer(r["zen"]) and r["zen"] >= 0 and r["outputs"] != [] and
        Enum.all?(r["outputs"], &Map.has_key?(@items, &1)) and
        Enum.all?(Map.values(r["outputsByClass"] || %{}), &(&1 in r["outputs"])) and
        Enum.all?(r["inputs"], fn i ->
          is_integer(i["count"]) and i["count"] > 0 and
            ((is_list(i["types"]) and is_integer(i["minLevel"])) or
               Map.has_key?(@items, i["templateId"]))
        end) and r["rate"]["max"] <= 1 and r["rate"]["base"] >= 0

    ok? || raise "chaos.json: công thức #{id} sai"
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

  @doc "Quest (P6-M2, `quests.json`), giữ thứ tự trong file."
  def quests, do: @quest_order |> Enum.map(&Map.fetch!(@quests, &1))
  def quest(id), do: Map.get(@quests, id)

  @doc "Công thức Chaos Machine (P6-M3, `chaos.json`)."
  def chaos_recipes, do: Map.values(@recipes)

  @doc "Bảng rơi đồ của quái (`nil` nếu không có)."
  def drops(monster_id), do: Map.get(@drops, monster_id)
end

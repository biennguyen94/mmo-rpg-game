defmodule HacLong.Game.DataCheck do
  @moduledoc """
  Kiểm dữ liệu game lúc biên dịch (`HacLong.Game.Data`, `HacLong.World.Maps` gọi `run!/1`,
  `run_maps!/2`): id món đồ / quái / lớp nhắc tới ở chỗ khác phải tồn tại, kỹ năng có `effect`
  đã biết... Sai thì biên dịch dừng với danh sách lỗi (tên file + id), không đợi tới lúc chơi.

  Hàm thuần trên dữ liệu đã đọc (khóa atom như trong `Data`), không gọi `Data`.
  """

  @npc_roles ~w(quests shop herbalist inn talk chest daily tower carpenter chaos cook event market pets wardrobe tienlen)
  @pet_skills ~w(heal bash pickpocket venom rend)
  @fails [nil, "down", "destroy"]

  def npc_roles, do: @npc_roles

  @doc "Như `errors/1` nhưng ném lỗi biên dịch nếu có lỗi."
  def run!(d), do: raise_on(errors(d))

  @doc "Kiểm bản đồ `maps` (`%{id => map}` của `HacLong.World.Maps`) với dữ liệu `d`."
  def run_maps!(maps, d), do: raise_on(map_errors(maps, d))

  defp raise_on([]), do: :ok

  defp raise_on(errs) do
    raise CompileError,
      description: "dữ liệu game sai:\n" <> Enum.map_join(errs, "\n", &("  - " <> &1))
  end

  @doc "Danh sách lỗi (chuỗi) của dữ liệu `d`; rỗng là dữ liệu hợp lệ."
  def errors(d) do
    item? = &Map.has_key?(d.items, &1)
    monster_ids = for z <- d.zones, m <- [z.boss | z.monsters], into: MapSet.new(), do: m.id
    boss_ids = MapSet.new(d.zones, & &1.boss.id)
    effects = d.rules.skill_effects |> Map.keys() |> Enum.map(&Atom.to_string/1)
    chest_ids = Enum.map(d.rules.chests.tiers, & &1.id)

    items = fn file, where, ids ->
      for id <- ids, not item?.(id), do: "#{file}: #{where} có món \"#{id}\" không có trong ITEMS"
    end

    List.flatten([
      items.("shop.json", "SHOP", d.shop),
      for {boss, id} <- d.boss_drops do
        [
          if(boss in boss_ids,
            do: [],
            else: "zones.json: BOSS_DROPS có trùm \"#{boss}\" không có"
          ),
          items.("zones.json", "BOSS_DROPS[#{boss}]", [id])
        ]
      end,
      for r <- d.recipes do
        items.("recipes.json", "RECIPES[#{r.id}]", [r.out | Map.keys(r.needs)])
      end,
      for q <- d.quests do
        [
          items.("quests.json", "QUESTS[#{q.id}].reward", Map.keys(q.reward.items)),
          quest_target(q, item?, monster_ids, boss_ids),
          if(Enum.at(d.zones, q.zone),
            do: [],
            else: "quests.json: QUESTS[#{q.id}] có vùng #{q.zone} không có"
          ),
          for r <- q.requires, not Enum.any?(d.quests, &(&1.id == r)) do
            "quests.json: QUESTS[#{q.id}] cần nhiệm vụ \"#{r}\" không có"
          end
        ]
      end,
      for {cls, c} <- d.classes, s <- c.skills, (s[:effect] || s.id) not in effects do
        "classes.json: CLASSES[#{cls}] kỹ năng \"#{s.id}\" có effect \"#{s[:effect]}\" chưa có trong RULES.skill_effects"
      end,
      for {id, it} <- d.items, it.slot == "wing", not Map.has_key?(d.classes, it[:cls]) do
        "items.json: ITEMS[#{id}] là cánh của lớp \"#{it[:cls]}\" không có trong CLASSES"
      end,
      for p <- d.pets, sk = p[:skill], sk.id not in @pet_skills do
        "pets.json: PETS[#{p.id}] kỹ năng \"#{sk.id}\" chưa có tác dụng (#{Enum.join(@pet_skills, ", ")})"
      end,
      for e <- d.events do
        [
          items.("events.json", "EVENTS[#{e.id}].token", [e.token]),
          if(Enum.any?(d.furniture, &(&1.id == e.decor)),
            do: [],
            else:
              "events.json: EVENTS[#{e.id}] có đồ trang trí \"#{e.decor}\" không có trong FURNITURE"
          )
        ]
      end,
      for s <- d.upgrade.steps do
        [
          items.("upgrade.json", "UPGRADE.steps[+#{s.level}]", [s.jewel]),
          if(s.fail in @fails,
            do: [],
            else: "upgrade.json: UPGRADE.steps[+#{s.level}] fail \"#{s.fail}\" không hợp lệ"
          )
        ]
      end,
      items.("upgrade.json", "JEWELS.weights", Map.keys(d.jewels.weights)),
      for k <- Map.keys(d.jewels.chest_chance), k not in chest_ids do
        "upgrade.json: JEWELS.chest_chance có rương \"#{k}\" không có trong RULES.chests"
      end,
      for c <- d.chaos do
        # công thức `mode` (Phase 15f) biến đổi chính món đồ bỏ vào, không có `out`
        outs =
          cond do
            c[:mode] ->
              []

            String.contains?(c.out, "{cls}") ->
              Enum.map(Map.keys(d.classes), &String.replace(c.out, "{cls}", &1))

            true ->
              [c.out]
          end

        items.("chaos.json", "CHAOS[#{c.id}]", Map.keys(c.items) ++ outs)
      end,
      items.(
        "rules.json",
        "RULES.character.start_items",
        Map.keys(d.rules.character.start_items)
      ),
      items.("rules.json", "RULES.loot.potions", Enum.map(d.rules.loot.potions, & &1.id)),
      items.("rules.json", "RULES.upgrade.life.jewel", [d.rules.upgrade.life.jewel]),
      items.("rules.json", "RULES.tutorial.reward", Map.keys(d.rules.tutorial.reward.items)),
      for {pool, l} <- d.rules.fishing.pools do
        items.("rules.json", "RULES.fishing.pools.#{pool}", Enum.map(l, &List.last/1))
      end,
      for {slot, cost} <- d.rules.crafting.smith_costs do
        items.("rules.json", "RULES.crafting.smith_costs[#{slot}]", Map.keys(cost))
      end
    ])
  end

  defp quest_target(%{type: "collect"} = q, item?, _m, _b),
    do:
      if(item?.(q.target),
        do: [],
        else: "quests.json: QUESTS[#{q.id}] cần nộp \"#{q.target}\" không có trong ITEMS"
      )

  defp quest_target(%{type: "kill"} = q, _i, monsters, _b),
    do:
      if(q.target in monsters,
        do: [],
        else: "quests.json: QUESTS[#{q.id}] hạ quái \"#{q.target}\" không có"
      )

  defp quest_target(%{type: "boss"} = q, _i, _m, bosses),
    do:
      if(q.target in bosses,
        do: [],
        else: "quests.json: QUESTS[#{q.id}] hạ trùm \"#{q.target}\" không có"
      )

  defp quest_target(q, _i, _m, _b),
    do: "quests.json: QUESTS[#{q.id}] loại \"#{q.type}\" không hợp lệ"

  @doc "Lỗi của các bản đồ: NPC có `role` đã biết, đồ bán / thu thập, quái, cổng, vùng tồn tại."
  def map_errors(maps, d) do
    item? = &Map.has_key?(d.items, &1)
    monsters = for z <- d.zones, m <- z.monsters, into: MapSet.new(), do: m.id
    # Phase 15a: quái bản đồ phụ
    monsters = Enum.reduce(Map.get(d, :side_monsters, []), monsters, &MapSet.put(&2, &1.id))

    for {id, m} <- maps do
      file = "maps/#{id}.json"

      [
        if(m.zone == nil or Enum.at(d.zones, m.zone),
          do: [],
          else: "#{file}: vùng #{m.zone} không có"
        ),
        for n <- m.npcs do
          [
            if(n.role in @npc_roles,
              do: [],
              else: "#{file}: NPC \"#{n.id}\" có role \"#{n.role}\" chưa biết"
            ),
            for(
              s <- n.stock,
              not item?.(s),
              do: "#{file}: NPC \"#{n.id}\" bán \"#{s}\" không có trong ITEMS"
            )
          ]
        end,
        for(
          g <- m.gather,
          not item?.(g.item),
          do: "#{file}: điểm thu thập \"#{g.item}\" không có trong ITEMS"
        ),
        for(
          s <- m.spawns,
          s.monster not in monsters,
          do: "#{file}: quái \"#{s.monster}\" không có trong ZONES"
        ),
        for(
          p <- m.portals,
          not Map.has_key?(maps, p.to),
          do: "#{file}: cổng tới bản đồ \"#{p.to}\" không có"
        )
      ]
    end
    |> List.flatten()
  end
end

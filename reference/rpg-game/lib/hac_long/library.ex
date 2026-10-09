defmodule HacLong.Library do
  @moduledoc """
  Thư viện (Phase 14): danh sách bản đồ, quái, vật phẩm để người chơi tra cứu, sinh hoàn toàn từ dữ liệu
  game (`priv/game_data/`, `priv/maps/`) nên thêm bản đồ / quái / đồ mới là tự có. Gửi cho client một lần
  trong `GAME_DATA.LIBRARY`; client lọc theo tên.

  - Bản đồ: tên, vùng, cấp quái, quái / trùm, cổng đi tới, NPC, điểm thu thập.
  - Quái: cấp, vùng, máu / tấn công / phòng thủ / kinh nghiệm / vàng (công thức `Engine.make_monster/2`,
    vàng lấy trung bình), đòn đặc biệt, hiệu ứng khi đánh trúng, nơi xuất hiện, đồ rơi.
  - Vật phẩm: nơi có được (cửa hàng, trùm, pha chế / nấu, nhiệm vụ, quái rơi, ngọc, thu thập).
  """
  alias HacLong.Game.{Data, Engine}
  alias HacLong.World.Maps

  @doc "Thư viện (tính một lần rồi giữ trong `:persistent_term`, dữ liệu game không đổi khi chạy)."
  def get do
    case :persistent_term.get({__MODULE__, :data}, nil) do
      nil -> tap(build(), &:persistent_term.put({__MODULE__, :data}, &1))
      d -> d
    end
  end

  def build do
    zones = Data.zones() |> Enum.with_index()
    maps = Maps.ids() |> Enum.map(&Maps.get/1) |> Enum.reject(& &1.private)

    %{maps: maps(maps, zones), monsters: monsters(maps, zones), items: items(maps, zones)}
  end

  defp zone_name(nil, _), do: nil
  defp zone_name(i, zones), do: Enum.find_value(zones, fn {z, j} -> j == i && z.name end)

  defp maps(maps, zones) do
    maps
    |> Enum.map(fn m ->
      kinds = m.spawns |> Enum.map(& &1.monster) |> Enum.uniq()
      zone = m.zone && elem(Enum.at(zones, m.zone), 0)

      lv =
        for(z <- [zone], z, mo <- z.monsters, mo.id in kinds, do: mo.level) ++
          if(m.boss && zone, do: [zone.boss.level], else: [])

      %{
        id: m.id,
        name: m.name,
        zone: zone_name(m.zone, zones),
        min: Enum.min(lv, fn -> nil end),
        max: Enum.max(lv, fn -> nil end),
        monsters: kinds,
        boss: m.boss && zone && zone.boss.id,
        world_boss: m.world_boss != nil,
        to: m.portals |> Enum.map(& &1.to) |> Enum.uniq(),
        npcs: Enum.map(m.npcs, & &1.name),
        gather: m.gather |> Enum.map(& &1.item) |> Enum.uniq()
      }
    end)
    |> Enum.sort_by(&{&1.min || 0, &1.max || 0, &1.name})
  end

  defp monsters(maps, zones) do
    for {z, i} <- zones,
        {spec, boss?} <- Enum.map(z.monsters, &{&1, false}) ++ [{z.boss, true}] do
      m = Engine.make_monster(spec, boss?)

      where =
        for mp <- maps,
            (boss? and mp.boss != nil and mp.zone == i) or
              Enum.any?(mp.spawns, &(&1.monster == spec.id)),
            do: mp.name

      %{
        id: spec.id,
        name: spec.name,
        level: spec.level,
        boss: boss?,
        zone: z.name,
        hp: m.maxHp,
        atk: m.atk,
        def: m.def,
        xp: m.xp,
        gold:
          round(
            Engine.base_gold(spec.level) * Map.get(spec, :mult, 1) *
              if(boss?, do: Data.rules().monster.boss.gold, else: 1)
          ),
        special: spec[:special] && %{name: spec.special.name, every: spec.special.every},
        on_hit: spec[:on_hit] && %{id: spec.on_hit.id, chance: spec.on_hit.chance},
        where: Enum.uniq(where),
        drops: drops(spec, boss?)
      }
    end
  end

  defp drops(spec, boss?) do
    j = Data.jewels()

    [Data.potion_for(spec.level)] ++
      if(boss? and Data.boss_drop(spec.id), do: [Data.boss_drop(spec.id)], else: []) ++
      if(boss? or spec.level >= j.monster_level,
        do: Map.keys(j.weights) |> Enum.map(&to_string/1),
        else: []
      )
  end

  defp items(maps, zones) do
    j = Data.jewels()
    potions = Data.rules().loot.potions

    boss_drops =
      for {z, _} <- zones, d = Data.boss_drop(z.boss.id), into: %{}, do: {d, z.boss.name}

    for {id, it} <- Data.items() do
      sources =
        [
          for(mp <- maps, n <- mp.npcs, id in n.stock, do: "Bán: #{n.name} (#{mp.name})"),
          for(r <- Data.recipes(), r.out == id, do: "Pha chế / nấu ở #{npc_name(maps, r.npc)}"),
          for(
            q <- Data.quests(),
            Map.has_key?(q.reward[:items] || %{}, String.to_atom(id)) or
              Map.has_key?(q.reward[:items] || %{}, id),
            do: "Nhiệm vụ: #{q.name}"
          ),
          if(name = boss_drops[id], do: ["Trùm #{name} rơi"], else: []),
          if(p = Enum.find(potions, &(&1.id == id)),
            do: ["Quái cấp #{max(p.level, 1)}+ rơi"],
            else: []
          ),
          if(Map.has_key?(j.weights, String.to_atom(id)) or Map.has_key?(j.weights, id),
            do: ["Quái cấp #{j.monster_level}+, trùm, tháp, rương"],
            else: []
          ),
          for(mp <- maps, id in mp.gather, do: "Thu thập ở #{mp.name}")
        ]
        |> List.flatten()
        |> Enum.uniq()

      Map.merge(
        Map.take(it, [
          :name,
          :slot,
          :level,
          :atk,
          :def,
          :price,
          :cls,
          :heal_pct,
          :mana_pct,
          :dmg,
          :absorb,
          :drop
        ]),
        %{
          id: id,
          sources: sources
        }
      )
    end
    |> Enum.sort_by(&{&1.slot, &1[:level] || 0, &1.name})
  end

  defp npc_name(maps, role) do
    Enum.find_value(maps, role, fn mp ->
      Enum.find_value(mp.npcs, &(&1.role == role && &1.name))
    end)
  end
end

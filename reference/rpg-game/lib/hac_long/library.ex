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
    maps = Maps.ids() |> Enum.map(&Maps.get/1) |> Enum.reject(&(&1.private or &1.event != nil))

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
        if m.side,
          do: Enum.map(kinds, &Data.side_monster(&1).level),
          else:
            for(z <- [zone], z, mo <- z.monsters, mo.id in kinds, do: mo.level) ++
              if(m.boss && zone, do: [zone.boss.level], else: [])

      %{
        id: m.id,
        name: m.name,
        zone: if(m.side, do: "Bản đồ phụ", else: zone_name(m.zone, zones)),
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

  defp monsters(maps, zones), do: zone_monsters(maps, zones) ++ side_monsters(maps)

  # quái bản đồ phụ (Phase 15a)
  defp side_monsters(maps) do
    for spec <- Data.side_monsters() do
      m = Engine.make_monster(spec, false)

      %{
        id: spec.id,
        name: spec.name,
        level: spec.level,
        boss: false,
        zone: "Bản đồ phụ",
        hp: m.maxHp,
        atk: m.atk,
        def: m.def,
        xp: m.xp,
        gold: Engine.base_gold(spec.level),
        special: nil,
        on_hit: nil,
        where: for(mp <- maps, Enum.any?(mp.spawns, &(&1.monster == spec.id)), do: mp.name),
        drops: drops(spec, false)
      }
    end
  end

  defp zone_monsters(maps, zones) do
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

    gear_lv = gear_levels(zones)
    extra = extra_sources()

    for {id, it} <- Data.items() do
      sources =
        [
          for(
            mp <- maps,
            n <- mp.npcs,
            id in n.stock,
            do: "Bán: #{n.name} (#{mp.name})#{for_classes(it)}"
          ),
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
          gather_source(maps, id),
          if(Data.legacy?(id),
            do: ["Đồ bản cũ: không còn rơi / bán, tự đổi sang đồ mới khi vào game"],
            else: []
          ),
          for(
            {cls, c} <- Enum.sort(Data.classes()),
            id in Map.values(Data.starters(cls)),
            do: "Đồ khởi đầu: nhân vật #{c.name} mới tạo mặc sẵn"
          ),
          gear_source(gear_lv[id]),
          chaos_sources(id, it),
          fish_sources(id),
          Map.get(extra, id, [])
        ]
        |> List.flatten()
        |> Enum.uniq()
        |> then(&if(&1 == [], do: ["Chưa có nguồn trong game (chỉ quản trị tặng)"], else: &1))

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

  # ---------- Nguồn rơi / ghép / sự kiện (B-23: Thư viện ghi đủ nguồn và tỉ lệ) ----------

  @slots ~w(weapon shield helm armor pants gloves boots ring pendant)

  # đồ ngẫu nhiên (`Gear.roll`): món thuộc 2 bậc cấp cao nhất ≤ cấp quái → `%{id => {cấp_min, cấp_max}}`
  defp gear_levels(zones) do
    top =
      (Enum.flat_map(zones, fn {z, _} -> [z.boss.level | Enum.map(z.monsters, & &1.level)] end) ++
         Enum.map(Data.side_monsters(), & &1.level))
      |> Enum.max()

    for l <- 1..top, s <- @slots, id <- HacLong.Game.Gear.drop_ids(s, l), reduce: %{} do
      acc -> Map.update(acc, id, {l, l}, fn {a, b} -> {min(a, l), max(b, l)} end)
    end
    |> Map.new(fn {id, {a, b}} -> {id, {a, if(b == top, do: nil, else: b)}} end)
  end

  defp gear_source(nil), do: []

  defp gear_source({a, b}) do
    c = Data.rules().loot.gear_chance
    lv = if b, do: "#{a}–#{b}", else: "#{a}+"

    [
      "Quái cấp #{lv} rơi ngẫu nhiên (mỗi con ra 1 món đồ: thường #{pct(c.normal)}, Bóng Đêm #{pct(c.night)}, trùm #{pct(c.boss)}, tinh anh #{pct(c.elite)}; rồi chia đều các món hợp cấp)",
      "Thưởng Quảng Trường Quỷ (qua hết đợt), Kalima (hạ Kundun), rương"
    ]
  end

  # Máy Hỗn Nguyên: công thức ra món này (`{cls}`: cánh theo lớp)
  defp chaos_sources(id, it) do
    for r <- Data.chaos(),
        out = r[:out],
        is_binary(out),
        out == id or (it[:cls] && String.replace(out, "{cls}", to_string(it[:cls])) == id),
        what = String.trim_trailing(r.desc || r.name, "."),
        do: "Máy Hỗn Nguyên: #{what} (thành công #{pct(r.rate)})"
  end

  # gom các bản đồ có điểm thu thập món này vào một dòng
  defp gather_source(maps, id) do
    # "Vực Quỷ 1", "Vực Quỷ 2"… → "Vực Quỷ (1–5)"
    names =
      for(mp <- maps, Enum.any?(mp.gather, &(&1.item == id)), do: mp.name)
      |> Enum.uniq()
      |> Enum.group_by(&String.replace(&1, ~r/ \d+$/, ""), &number_suffix/1)
      |> Enum.sort()
      |> Enum.map_join(", ", fn {name, ns} ->
        case ns |> Enum.reject(&is_nil/1) |> Enum.sort() do
          [] -> name
          [n] -> "#{name} #{n}"
          ns -> "#{name} (#{hd(ns)}–#{List.last(ns)})"
        end
      end)

    if names == "", do: [], else: ["Thu thập (bụi / mỏ mọc lại) ở: " <> names]
  end

  defp number_suffix(name) do
    case Regex.run(~r/ (\d+)$/, name) do
      [_, n] -> String.to_integer(n)
      _ -> nil
    end
  end

  defp fish_sources(id) do
    pools = Data.rules().fishing.pools

    for {pool, list} <- Enum.sort(pools),
        total = list |> Enum.map(&hd/1) |> Enum.sum(),
        [w, ^id] <- list,
        where = if(to_string(pool) == "deep", do: "Câu cá (vùng sâu)", else: "Câu cá"),
        do: "#{where}: #{pct(w / total)}"
  end

  # vé / mảnh vé / thưởng các sự kiện, đồ lễ hội, rơi thêm của xâm lăng
  defp extra_sources do
    r = Data.rules()
    tower = "Người Gác Tháp (Làng)"
    ds = r.devil_square
    bc = r.blood_castle
    cc = r.chaos_castle
    kal = r.kalima

    part = fn d ->
      "Quái thường cấp #{d.min_level}+ rơi #{pct(d.chance)} (một trong #{length(d.parts)} mảnh)"
    end

    base = [
      {ds.ticket, "Mua ở #{tower}: #{num(ds.ticket_price)} vàng"},
      {bc.ticket, "Mua ở #{tower}: #{num(bc.ticket_price)} vàng"},
      {cc.ticket, "Mua ở #{tower}: #{num(cc.ticket_price)} vàng"},
      {cc.ticket,
       "Quái thường cấp #{cc.ticket_drop.min_level}+ rơi #{pct(cc.ticket_drop.chance)}"},
      {kal.mark, "Quái thường cấp #{kal.mark_drop.min_level}+ rơi #{pct(kal.mark_drop.chance)}"},
      {"condor_feather", "Thưởng hạ Hiệp Sĩ Máu (Lâu Đài Máu)"},
      {"dragon_scale", "Trùm thế giới Cổ Long: top 3 sát thương nhận 1 cái (kèm 1 ngọc)"}
    ]

    parts =
      for {d, _} <- [{ds.ticket_drop, :ds}, {bc.ticket_drop, :bc}],
          id <- d.parts,
          do: {id, part.(d)}

    events =
      for e <- Data.events(),
          do:
            {e.token,
             "Lễ hội #{e.name} (#{e.from} → #{e.to}): quái rơi #{pct(r.loot.event_token_chance)}, trùm rơi #{r.loot.event_token_boss} cái"}

    raids =
      for {_k, rd} <- HacLong.Raids.rules(),
          {id, c} <- rd.drops,
          do: {to_string(id), "#{rd.icon} #{rd.leader.name} (#{rd.name}) rơi thêm #{pct(c)}"}

    rewards =
      for {name, items} <- [
            {"Hỗn Chiến Thành (người thắng)", cc.reward.winner.items},
            {"Công Thành Chiến (Chủ Thành)", r.castle_siege.reward.items}
          ],
          {id, n} <- items,
          do: {to_string(id), "Thưởng #{name}: #{n}"}

    (base ++ parts ++ events ++ raids ++ rewards)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp num(n), do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+$)/, ".")

  defp pct(x) do
    v = x * 100

    if v == round(v),
      do: "#{round(v)} %",
      else: "#{v |> Float.round(1) |> Float.to_string() |> String.replace(".", ",")} %"
  end

  # Thợ Rèn chỉ bán đồ cho lớp được dùng (Engine.class_ok?/2): ghi rõ lớp nào mua được
  defp for_classes(it) do
    case List.wrap(it[:cls]) ++ (it[:classes] || []) do
      [] -> ""
      cs -> " — cho " <> Enum.map_join(Enum.uniq(cs), ", ", &Data.class(&1).name)
    end
  end

  defp npc_name(maps, role) do
    Enum.find_value(maps, role, fn mp ->
      Enum.find_value(mp.npcs, &(&1.role == role && &1.name))
    end)
  end
end

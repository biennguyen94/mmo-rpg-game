# Phase 8: bảng số docs/FORMULA_AUDIT.md §3. Chạy: mix run --no-start scripts/formula_table.exs
alias HacLong.Game.{Data, Engine, Gear}
items = Data.items()
alloc = %{"dk" => %{str: 0.5, vit: 0.3, agi: 0.2}, "dw" => %{ene: 0.55, vit: 0.3, str: 0.1, agi: 0.05},
          "elf" => %{agi: 0.55, str: 0.15, vit: 0.3}, "mg" => %{str: 0.35, ene: 0.25, vit: 0.25, agi: 0.15}}
best = fn cls, slot, lv, p ->
  items
  |> Enum.filter(fn {_, it} -> it[:slot] == slot and !it[:legacy] and (it[:level] || 1) <= lv and Engine.class_ok?(it, cls) and Engine.can_wear?(p, it) end)
  |> Enum.max_by(fn {_, it} -> {it[:level] || 0, it[:atk] || it[:def] || it[:hp] || 0} end, fn -> nil end)
end
build = fn cls, lv, up, opt ->
  {_, p} = HacLong.Game.Commands.run(nil, %{"act" => "create", "name" => "A#{cls}#{lv}", "cls" => cls})
  pts = Data.class(cls).points * (lv - 1)
  stats = Enum.reduce(alloc[cls], p.stats, fn {k, f}, s -> Map.update!(s, k, &(&1 + round(pts * f))) end)
  p = %{p | level: lv, stats: stats, gear: [], equip: Engine.empty_equip()}
  slots = [{"weapon", :weapon}, {"helm", :helm}, {"armor", :armor}, {"pants", :pants}, {"gloves", :gloves}, {"boots", :boots}] ++
          if(cls in ["dk", "dw"], do: [{"shield", :shield}], else: [])
  Enum.reduce(slots, p, fn {slot, key}, p ->
    case best.(cls, slot, lv, p) do
      nil -> p
      {id, it} ->
        if Engine.can_wear?(p, it) do
          g = Gear.new(id, opt)
          p = %{p | gear: p.gear ++ [g]} |> put_in([:equip, key], g.uid)
          if up > 0, do: Map.put(p, :upgrades, Map.put(p[:upgrades] || %{}, g.uid, up)), else: p
        else p end
    end
  end)
end
avg = fn atk, dfn, mult ->
  raw = atk * mult
  max(1, max(raw * raw / (raw + max(dfn, 0)), raw * 0.2))
end
IO.puts("| Lớp | Cấp | Đồ | Máu | Tấn công | Thủ | Chí mạng | Né | Trúng | Quái: máu / công / thủ | Đòn TB | Lượt hạ | Quái đánh TB | Lượt chết |")
IO.puts("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
for cls <- ~w(dk dw elf mg), lv <- [1, 10, 25, 40, 50], {tag, up, opt} <- [{"trắng", 0, 0}, {"+7, 2 dòng", 7, 2}], not (lv == 1 and up > 0) do
  p = build.(cls, lv, up, opt)
  d = Engine.derived(p)
  m = Engine.make_monster(%{id: "x", name: "x", level: lv}, false)
  hit = Engine.hit_chance(d.ar, lv)
  per = avg.(d.atk, m.def, 1) * (1 + d.crit * (d.critMult - 1))
  turns = Float.ceil(m.maxHp / (per * hit))
  mdmg = avg.(m.atk, d.def, 1) * (1 - d.dodge) * (1 + m.crit * 0.5)
  die = Float.ceil(d.maxHp / mdmg)
  IO.puts("| #{cls} | #{lv} | #{tag} | #{d.maxHp} | #{d.atk} | #{d.def} | #{round(d.crit*100)}% | #{round(d.dodge*100)}% | #{round(hit*100)}% | #{m.maxHp} / #{m.atk} / #{m.def} | #{round(per)} | #{trunc(turns)} | #{round(mdmg)} | #{trunc(die)} |")
end

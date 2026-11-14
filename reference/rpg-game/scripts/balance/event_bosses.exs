# Đo độ khó trùm sự kiện theo mốc chuyển sinh bằng TRẬN THẬT (DECISIONS "Cân bằng trùm sự kiện theo chuyển sinh"):
# nhân vật chơi thật từ HacLong.Game.Journey (tmp/journey_tiers, như scripts/pvp/profile.exs), mỗi mốc CS 0–10,
# đánh một mình từng trùm dựng bằng đúng hàm của game; bot tự đánh (`Brain.fight/1`: kỹ năng mạnh nhất, uống bình).
# HP_AT: uống bình khi máu dưới mức này (mặc định 0,5 như người chơi cẩn thận; bot thật 0,35).
# In: tỉ lệ thắng, số lượt (trung vị), bình máu dùng (trung vị) theo mốc.
#
#   mix run --no-start scripts/balance/event_bosses.exs
#   TRIES=3 CS=0,5,10 mix run --no-start scripts/balance/event_bosses.exs
alias HacLong.Game.{Commands, Data, Engine, BloodCastle, DevilSquare, Kalima, EventRooms}
alias HacLong.Bots.Brain

dir = "tmp/journey_tiers"
runs = for f <- File.ls!(dir), String.ends_with?(f, ".bin"), do: :erlang.binary_to_term(File.read!(Path.join(dir, f)))
hp_at = String.to_float(System.get_env("HP_AT") || "0.5")
tries = String.to_integer(System.get_env("TRIES") || "2")
css = (System.get_env("CS") || "0,2,4,6,8,10") |> String.split(",") |> Enum.map(&String.to_integer/1)
r = Data.rules()
zi = Data.zone_count() - 1
band_k = fn cs -> EventRooms.k(EventRooms.band(cs)) end
final_boss = List.last(Data.zones()).boss
# trùm Quảng Trường Quỷ: trùm các vùng trừ Hắc Long (DevilSquare.build), lấy trùm vùng áp chót
ds_boss = Data.zones() |> Enum.map(& &1.boss) |> Enum.reject(&(&1[:final] == true)) |> List.last()

# {tên, dựng trận (p, cs) → p trong trận}
bosses = [
  {"Thạch Long Ẩn", fn p, cs ->
     {_, p} = Engine.start_side_encounter(p, Data.side_monster(r.secret.boss), "động", "cave", true)
     # nhân vật quá mạnh: bản Thức Tỉnh (HacLong.Game.Awaken), như World.encounter
     p |> Engine.scale_event(cs) |> HacLong.Game.Awaken.maybe("secret")
   end},
  {"Hắc Long (vùng)", fn p, cs ->
     {_, p} = Engine.start_side_encounter(p, final_boss, "vùng", "lair", true)
     Engine.scale_event(p, cs)
   end},
  {"QT Quỷ (trùm)", fn p, cs ->
     lv = List.last(r.devil_square.tiers).level + List.last(r.devil_square.waves).add_level
     m = DevilSquare.battle_monster(%{kind: ds_boss.id, name: "Trùm QTQ", level: lv, elite: true})
     {_, p} = Engine.start_with_monster(p, zi, m)
     Engine.scale_event(p, band_k.(cs))
   end},
  {"Hiệp Sĩ Máu", fn p, cs ->
     b = r.blood_castle.boss
     lv = List.last(r.blood_castle.tiers).level + b.add_level
     m = BloodCastle.battle_monster(%{kind: b.kind, name: b.name, level: lv, role: "boss", elite: true})
     {_, p} = Engine.start_with_monster(p, zi, m)
     Engine.scale_event(p, band_k.(cs))
   end},
  {"Kundun", fn p, cs ->
     b = r.kalima.boss
     lv = List.last(r.kalima.tiers).level + b.add_level
     m = Kalima.battle_monster(%{kind: b.kind, name: b.name, level: lv, role: "boss", elite: true})
     {_, p} = Engine.start_with_monster(p, zi, m)
     Engine.scale_event(p, band_k.(cs))
   end}
]

fight = fn p, start, cs ->
  d = Engine.derived(p)
  p = %{p | battle: nil, hp: d.maxHp, mp: d.maxMp}
  p = Map.update(p, :inv, %{}, &Map.merge(&1, %{"potion_l" => 50, "mana_l" => 50}))
  p = start.(p, cs)
  pots0 = p.inv["potion_l"]
  p = Enum.reduce_while(1..400, p, fn _, p ->
    if p.battle.over, do: {:halt, p}, else: {:cont, elem(Commands.run(p, Brain.fight(p, hp_at)), 1)}
  end)
  {p.battle.result == "win", p.battle.turn, pots0 - (p.inv["potion_l"] || 0), p.battle.monster.maxHp}
end

med = fn l -> l |> Enum.sort() |> Enum.at(div(length(l), 2)) end

IO.puts("trùm · " <> Enum.map_join(css, " · ", &"CS #{&1}") <> "   (thắng% / lượt / bình / máu trùm)")
# nhân vật cuối game (tháp 100, đồ ép cao): tmp/endgame_cs10.bin (xuất từ DB server dev), chỉ ở CS 10
endgame = case File.read("tmp/endgame_cs10.bin") do {:ok, b} -> :erlang.binary_to_term(b); _ -> [] end

for {name, start} <- bosses do
  cells =
    for cs <- css do
      ps = for t <- runs, p = t[cs], p != nil, do: p
      rs = for p <- ps, i <- 1..tries, do: (:rand.seed(:exsss, {cs, i, :erlang.phash2(p.cls)}); fight.(p, start, cs))
      w = Enum.count(rs, &elem(&1, 0))
      "#{round(100 * w / max(length(rs), 1))}% / #{med.(Enum.map(rs, &elem(&1, 1)))} / #{med.(Enum.map(rs, &elem(&1, 2)))} / #{elem(hd(rs), 3)}"
    end
  eg =
    if endgame == [] do "" else
      rs = for p <- endgame, i <- 1..tries, do: (:rand.seed(:exsss, {99, i, :erlang.phash2(p.name)}); fight.(p, start, 10))
      " ‖ cuối game CS10: #{round(100 * Enum.count(rs, &elem(&1, 0)) / length(rs))}% / #{med.(Enum.map(rs, &elem(&1, 1)))} / #{med.(Enum.map(rs, &elem(&1, 2)))}"
    end
  IO.puts(String.pad_trailing(name, 16) <> " " <> Enum.join(cells, " · ") <> eg)
end

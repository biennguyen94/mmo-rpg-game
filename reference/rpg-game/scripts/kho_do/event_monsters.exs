# Quái sự kiện theo số lần chuyển sinh của người đánh: máu / công / thủ (đúng như game dựng: Engine.make_monster +
# hệ số của sự kiện + Engine.scale_event/1) và so với nhân vật cùng mốc (Max.tier/2, hồ sơ đồ chơi thật; mốc 10 đồ tối đa):
# số đòn thường để hạ, % máu mất mỗi đòn quái trúng. Kho Đồ dùng qua export.exs; chạy riêng để xem nhanh:
#   MIX_ENV=test mix run --no-start scripts/kho_do/event_monsters.exs print
Code.require_file(Path.join(__DIR__, "../pvp/build.exs"))

defmodule KhoDo.EventMonsters do
  alias HacLong.Game.{Data, Engine}

  @ks [0, 3, 6, 10]
  @classes ~w(dk dw elf mg)

  def ks, do: @ks

  # quái mạnh nhất mỗi sự kiện (bậc cao nhất), hệ số đọc từ RULES như module sự kiện
  defp specs do
    r = Data.rules()
    ds = r.devil_square
    ds_lv = List.last(ds.tiers).level
    bc = r.blood_castle
    bc_lv = List.last(bc.tiers).level
    kal = r.kalima
    kal_lv = List.last(kal.tiers).level
    crown = r.castle_siege.crown

    [
      %{name: "Quái Quảng Trường Quỷ", level: ds_lv, mult: ds.monster_mult, hp: 1},
      %{name: "Trùm Quảng Trường Quỷ", level: ds_lv + List.last(ds.waves).add_level, mult: ds.boss_mult, hp: ds.boss_hp},
      %{name: "Lính Lâu Đài Máu", level: bc_lv, mult: bc.guard_mult, hp: 1},
      %{name: bc.boss.name <> " (trùm Lâu Đài Máu)", level: bc_lv + bc.boss.add_level, mult: bc.boss.mult, hp: bc.boss.hp},
      %{name: "Lính Kalima", level: kal_lv, mult: kal.guard_mult, hp: 1},
      %{name: kal.boss.name <> " (trùm Kalima)", level: kal_lv + kal.boss.add_level, mult: kal.boss.mult, hp: kal.boss.hp},
      %{name: crown.name <> " (Công Thành Chiến)", level: crown.level, mult: crown.mult, hp: 1}
    ]
  end

  defp monster(s, k) do
    m = Engine.make_monster(%{id: "ev", name: s.name, level: s.level, mult: s.mult}, false)
    m = %{m | maxHp: m.maxHp * s.hp}
    Engine.scale_event(%{battle: %{monster: m}}, k).battle.monster
  end

  defp avg(f), do: Enum.sum(for(_ <- 1..200, do: f.())) / 200

  @doc "Mỗi quái: `%{name, level, rows: [%{k, hp, atk, def, vs: %{lớp => %{hits, taken}}}]}` (taken: % máu, số nguyên)."
  def rows do
    :rand.seed(:exsss, {1, 2, 3})
    chars = for k <- @ks, c <- @classes, into: %{}, do: {{c, k}, Engine.derived(elem(Max.tier(c, k), 0))}

    for s <- specs() do
      rows =
        for k <- @ks do
          m = monster(s, k)

          vs =
            for c <- @classes, into: %{} do
              d = chars[{c, k}]
              hit = avg(fn -> Engine.damage(d.atk, m.def) end)
              taken = avg(fn -> Engine.damage(m.atk, d.def) end) * (1 - d.wingAbsorb) * (1 - d.excAbsorb)
              {c, %{hits: round(m.maxHp / max(hit, 1)), taken: round(taken / d.maxHp * 100)}}
            end

          %{k: k, hp: m.maxHp, atk: m.atk, def: m.def, vs: vs}
        end

      %{name: s.name, level: s.level, rows: rows}
    end
  end
end

if System.argv() == ["print"] do
  for m <- KhoDo.EventMonsters.rows(), r <- m.rows do
    vs = Enum.map_join(r.vs, " · ", fn {c, v} -> "#{c} #{v.hits} đòn / #{v.taken}%" end)
    IO.puts("CS #{r.k} #{m.name} (cấp #{m.level}): máu #{r.hp} công #{r.atk} thủ #{r.def} | #{vs}")
  end
end

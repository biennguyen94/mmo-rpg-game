# Đồ sát giữa hai người KHÁC mốc chuyển sinh (đồ ngang theo mốc, Max.tier/2, hệ số lớp theo mốc người bị đánh như
# server): người mốc cao thắng bao nhiêu %, theo từng lớp mốc cao.
#   PAIRS=0-1,2-3,3-5,6-8,9-10 N=16 mix run --no-start scripts/pvp/cross.exs
Code.require_file(Path.join(__DIR__, "balance.exs"))
System.put_env("POT", "1")
alias HacLong.Game.Engine

pairs =
  (System.get_env("PAIRS") || "0-1,1-2,2-3,3-4,4-5,5-6,6-7,7-8,8-9,9-10,0-3,3-7,6-10")
  |> String.split(",")
  |> Enum.map(fn s ->
    s |> String.split("-") |> Enum.map(&String.to_integer/1) |> List.to_tuple()
  end)

n = String.to_integer(System.get_env("N") || "16")
classes = PvpBalance.classes()

char = fn c, k ->
  {p, _} = Max.tier(c, k)
  d = Engine.derived(p)

  %{
    p
    | hp: d.maxHp,
      battle: nil,
      inv: p.inv |> Map.put("potion_l", 100) |> Map.put("mana_l", 100)
  }
  |> Map.put(:mp, d.maxMp)
end

for {lo, hi} <- pairs do
  :rand.seed(:exsss, {lo + 1, hi + 1, 3})

  by =
    for a <- classes, b <- classes, reduce: %{} do
      acc ->
        pa = char.(a, hi)
        pb = %{char.(b, lo) | name: "#{b}x"}
        # mốc cao tấn công, rồi mốc thấp tấn công
        r1 = for _ <- 1..n, do: SlaySim.fight(pa, pb).winner
        r2 = for _ <- 1..n, do: SlaySim.fight(pb, %{pa | name: "#{a}x"}).winner
        w = Enum.count(r1, &(&1 == 1)) + Enum.count(r2, &(&1 == 2))
        t = Enum.count(r1 ++ r2, &(&1 != :draw))
        Map.update(acc, a, {w, t}, fn {x, y} -> {x + w, y + t} end)
    end

  {w, t} = Enum.reduce(Map.values(by), {0, 0}, fn {x, y}, {a, b} -> {a + x, b + y} end)

  per =
    Enum.map_join(classes, " ", fn c ->
      {x, y} = by[c]
      "#{c} #{round(x * 100 / max(y, 1))}%"
    end)

  IO.puts(
    "r#{hi} vs r#{lo}: mốc cao thắng #{round(w * 100 / max(t, 1))}%  (theo lớp mốc cao: #{per})"
  )
end

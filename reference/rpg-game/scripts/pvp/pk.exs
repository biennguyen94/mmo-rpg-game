# PK cược chéo 4 lớp tối đa: N=200 mix run --no-start scripts/pvp/pk.exs
Code.require_file(Path.join(__DIR__, "build.exs"))
n = String.to_integer(System.get_env("N") || "200")
ps = Map.new(~w(dk dw elf mg), &{&1, Max.build(&1)})
rows = for a <- ~w(dk dw elf mg), b <- ~w(dk dw elf mg), a < b do
  res = for _ <- 1..n, do: HacLong.Game.PkFight.fight(ps[a], %{ps[b] | name: ps[b].name <> "2"}, 1, 2)
  w = Enum.count(res, &(&1.winner == :a)); l = Enum.count(res, &(&1.winner == :b))
  IO.puts("#{a} vs #{b}: #{a} thắng #{round(w * 100 / n)}%, #{b} thắng #{round(l * 100 / n)}%, TB #{Float.round(Enum.sum(Enum.map(res, & &1.rounds)) / n, 1)} lượt")
  {a, b, w, l}
end
for c <- ~w(dk dw elf mg) do
  {w, t} = Enum.reduce(rows, {0, 0}, fn {a, b, w, l}, {x, y} -> cond do a == c -> {x + w, y + n}; b == c -> {x + l, y + n}; true -> {x, y} end end)
  IO.puts("  #{c}: #{round(w * 100 / t)}%")
end

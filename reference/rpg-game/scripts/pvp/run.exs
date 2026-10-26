# Đồ sát chéo 4 lớp tối đa: N=200 mix run --no-start scripts/pvp/run.exs (in chỉ số, tỉ lệ thắng, kiểm sát thương hiện = máu mất)
Code.require_file(Path.join(__DIR__, "sim.exs"))
alias HacLong.Game.Engine

n = String.to_integer(System.get_env("N") || "200")
ps = Map.new(~w(dk dw elf mg), &{&1, Max.build(&1)})

IO.puts("== Chỉ số (derived)")

keys =
  ~w(maxHp maxMp atk def crit critMult dodge ar ignoreDef wingDmg wingAbsorb excAbsorb excReflect skillDmg)a

for {c, p} <- ps do
  d = Engine.derived(p)
  IO.puts("#{c}: " <> Enum.map_join(keys, " ", fn k -> "#{k}=#{inspect(Map.get(d, k))}" end))
  IO.puts("   skills: " <> Enum.map_join(Engine.skills(p), ", ", & &1.name))
end

IO.puts("\n== Đồ sát (hàng = người tấn công đi trước), #{n} trận mỗi cặp")
all = for a <- ~w(dk dw elf mg), b <- ~w(dk dw elf mg), do: {a, b}
fx = %{}

{rows, fx} =
  Enum.reduce(all, {[], fx}, fn {a, b}, {rows, fx} ->
    pb = %{ps[b] | name: ps[b].name <> "2"}
    res = for _ <- 1..n, do: SlaySim.fight(ps[a], pb)
    w = Enum.count(res, &(&1.winner == 1))
    avg = Enum.sum(Enum.map(res, & &1.turns)) / n
    # bỏ :by (thống kê theo từng bên, dạng map) khi cộng dồn
    fx =
      Enum.reduce(res, fx, fn r, fx ->
        Map.merge(fx, Map.delete(r.st, :by), fn _, x, y -> x + y end)
      end)

    {[{a, b, w, avg} | rows], fx}
  end)

for {a, b, w, avg} <- Enum.reverse(rows),
    do: IO.puts("#{a} đánh #{b}: thắng #{round(w * 100 / n)}%  (TB #{Float.round(avg, 1)} lượt)")

first = Enum.sum(for {_, _, w, _} <- rows, do: w) / (length(rows) * n)
same = Enum.sum(for {a, b, w, _} <- rows, a == b, do: w) / (4 * n)
IO.puts("\nNgười đi trước thắng: #{round(first * 100)}% (cùng lớp #{round(same * 100)}%)")
IO.puts("\nTổng theo lớp (cả đi trước lẫn đi sau, không tính trận cùng lớp):")

for c <- ~w(dk dw elf mg) do
  {w, tot} =
    Enum.reduce(Enum.reverse(rows), {0, 0}, fn
      {^c, b, w, _}, {x, y} when b != c -> {x + w, y + n}
      {a, ^c, w, _}, {x, y} when a != c -> {x + n - w, y + n}
      _, acc -> acc
    end)

  IO.puts("  #{c}: #{round(w * 100 / tot)}%")
end

IO.puts(
  "\nTổng #{fx.turns} lượt: sát thương hiện ≠ sát thương tính #{fx.mismatch}; mất lượt vì choáng #{fx.stunned};"
)

IO.puts(
  "  đòn bị giảm bởi thủ thế / khiên / thú #{fx.reduced}; được bất tử / Long Vương cứu #{fx.saved}; uống bình máu #{fx.pots}"
)

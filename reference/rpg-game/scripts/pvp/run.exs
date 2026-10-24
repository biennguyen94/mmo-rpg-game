# Đồ sát chéo 4 lớp tối đa: N=200 mix run --no-start scripts/pvp/run.exs (in chỉ số, tỉ lệ thắng, kiểm sát thương hiện = máu mất)
Code.require_file(Path.join(__DIR__, "sim.exs"))
alias HacLong.Game.Engine

n = String.to_integer(System.get_env("N") || "200")
ps = Map.new(~w(dk dw elf mg), &{&1, Max.build(&1)})

IO.puts("== Chỉ số (derived)")
keys = ~w(maxHp maxMp atk def crit critMult dodge ar ignoreDef wingDmg wingAbsorb excAbsorb excReflect skillDmg)a

for {c, p} <- ps do
  d = Engine.derived(p)
  IO.puts("#{c}: " <> Enum.map_join(keys, " ", fn k -> "#{k}=#{inspect(Map.get(d, k))}" end))
  IO.puts("   skills: " <> Enum.map_join(Engine.skills(p), ", ", & &1.name))
end

IO.puts("\n== Đồ sát (hàng = người tấn công đi trước), #{n} trận mỗi cặp")
all = for a <- ~w(dk dw elf mg), b <- ~w(dk dw elf mg), do: {a, b}
fx = %{}

{rows, fx, mism, turns} =
  Enum.reduce(all, {[], fx, 0, 0}, fn {a, b}, {rows, fx, m, t} ->
    pb = %{ps[b] | name: ps[b].name <> "2"}
    res = for _ <- 1..n, do: SlaySim.fight(ps[a], pb)
    w = Enum.count(res, &(&1.winner == 1))
    avg = Enum.sum(Enum.map(res, & &1.turns)) / n
    fx = Enum.reduce(res, fx, fn r, fx -> Map.merge(fx, r.st.fx, fn _, x, y -> x + y end) end)
    m = m + Enum.sum(Enum.map(res, & &1.st.mismatch))
    t = t + Enum.sum(Enum.map(res, & &1.st.turns))
    {[{a, b, w, avg} | rows], fx, m, t}
  end)

for {a, b, w, avg} <- Enum.reverse(rows),
    do: IO.puts("#{a} đánh #{b}: thắng #{round(w * 100 / n)}%  (TB #{Float.round(avg, 1)} lượt)")

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

IO.puts("\nSát thương hiện ≠ máu mất: #{mism} / #{turns} lượt")
IO.puts("Hiệu ứng lượt-lượt (đếm lượt có hiệu ứng): #{inspect(Enum.sort(fx))}")

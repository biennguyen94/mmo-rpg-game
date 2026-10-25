# Đồ sát / PK cược chéo 4 lớp với nhân vật CHƠI THẬT (HacLong.Game.Journey) ở từng mốc chuyển sinh: cùng mốc thì đồ,
# ép, thú, thông thạo ngang nhau theo đúng tiến độ chơi; mỗi lớp nhiều seed (giảm may rủi rơi đồ), seed s đấu seed s.
#   KS=0,1,3,5,7,10 SEEDS=2 N=50 mix run --no-start scripts/pvp/journey_pk.exs
# Nhân vật hành trình lưu ở tmp/journey_pk/<lớp>-r<k>-s<seed>.bin (chạy lại dùng luôn; xóa để dựng lại khi đổi dữ liệu).
#   SRC=tier SEEDS=1 N=100 …: thay nhân vật hành trình bằng bộ đồ giống hệt nhau theo mốc (tách lớp khỏi may rủi đồ).
# Đồ sát: uống bình máu dưới 50% máu, bình mana khi hết MP (mỗi người mang 100 bình lớn mỗi loại).
Code.require_file(Path.join(__DIR__, "sim.exs"))
# POT=0: không uống bình (mặc định 1)
System.put_env("POT", System.get_env("POT") || "1")

alias HacLong.Game.{Engine, Journey, Gear, PkFight}

ks = (System.get_env("KS") || "0,1,3,5,7,10") |> String.split(",") |> Enum.map(&String.to_integer/1)
seeds = 1..String.to_integer(System.get_env("SEEDS") || "2")
n = String.to_integer(System.get_env("N") || "50")
classes = ~w(dk dw elf mg)
dir = "tmp/journey_pk"
File.mkdir_p!(dir)

char = fn cls, k, s ->
  f = Path.join(dir, "#{cls}-r#{k}-s#{s}.bin")

  p =
    case System.get_env("SRC") == "tier" || File.read(f) do
      # SRC=tier: nhân vật đồ giống hệt nhau theo mốc (Max.tier/2, scripts/pvp/build.exs); seed không dùng
      true ->
        elem(Max.tier(cls, k), 0)

      {:ok, bin} ->
        :erlang.binary_to_term(bin)

      _ ->
        # như mix hac_long.journey: Journey dùng :rand, seed đặt ở đây để chạy lại ra đúng nhân vật
        :rand.seed(:exsss, {s, s, s})
        p = Journey.run(cls, rebirths: k).player
        File.write!(f, :erlang.term_to_binary(p))
        p
    end

  d = Engine.derived(p)
  inv = p.inv |> Map.put("potion_l", 100) |> Map.put("mana_l", 100)
  %{p | hp: d.maxHp, battle: nil, inv: inv} |> Map.put(:mp, d.maxMp)
end

pct = fn w, t -> if t == 0, do: "—", else: "#{round(w * 100 / t)}%" end

for k <- ks do
  ps = for c <- classes, s <- seeds, into: %{}, do: {{c, s}, char.(c, k, s)}
  IO.puts("\n================ #{k} lần chuyển sinh (cấp 50) ================")

  for c <- classes do
    p = ps[{c, 1}]
    d = Engine.derived(p)
    ups = for {_, id} <- p.equip, id != nil, do: Engine.upgrade_level(p, id)
    avg_up = if ups == [], do: 0, else: Float.round(Enum.sum(ups) / length(ups), 1)

    IO.puts(
      "#{c}: máu #{d.maxHp} công #{d.atkMin}-#{d.atkMax} thủ #{d.def} chí mạng #{Float.round(d.crit * 100, 1)}% né #{Float.round(d.dodge * 100, 1)}% " <>
        "| ép TB +#{avg_up}, cánh #{if p.equip[:wing], do: Gear.item(p, p.equip.wing).name, else: "—"}, thú #{p[:pet] || "—"}, tháp #{Map.get(p, :tower_best) || 0}"
    )
  end

  # đồ sát: a tấn công b (a đi trước), cả hai chiều; PK cược: cùng lúc
  slay =
    for a <- classes, b <- classes, a != b, s <- seeds, reduce: %{} do
      acc ->
        pb = %{ps[{b, s}] | name: "#{b}#{s}x"}
        res = for _ <- 1..n, do: SlaySim.fight(ps[{a, s}], pb)
        w = Enum.count(res, &(&1.winner == 1))
        # hòa (chạm 200 lượt) không tính
        t = Enum.count(res, &(&1.winner != :draw))
        len = Enum.sum(Enum.map(res, & &1.turns))

        acc
        |> Map.update({a, b}, {w, t}, fn {x, y} -> {x + w, y + t} end)
        |> Map.update(:draws, {n - t, n}, fn {x, y} -> {x + n - t, y + n} end)
        |> Map.update(:len, {len, n}, fn {x, y} -> {x + len, y + n} end)
    end

  pk =
    for a <- classes, b <- classes, a < b, s <- seeds, reduce: %{} do
      acc ->
        pb = %{ps[{b, s}] | name: "#{b}#{s}x"}
        res = for _ <- 1..n, do: PkFight.fight(ps[{a, s}], pb, 1, 2).winner
        wa = Enum.count(res, &(&1 == :a))
        wb = Enum.count(res, &(&1 == :b))

        acc
        |> Map.update({a, b}, {wa, n}, fn {x, y} -> {x + wa, y + n} end)
        |> Map.update({b, a}, {wb, n}, fn {x, y} -> {x + wb, y + n} end)
    end

  # mirror cùng lớp: tỉ lệ người đi trước thắng
  first =
    for c <- classes, s <- seeds, reduce: {0, 0} do
      {w, t} ->
        pb = %{ps[{c, s}] | name: "#{c}#{s}x"}
        {w + Enum.count(1..n, fn _ -> SlaySim.fight(ps[{c, s}], pb).winner == 1 end), t + n}
    end

  total = fn tab, c ->
    # tỉ lệ thắng của lớp c trên mọi trận với lớp khác (đồ sát: cả khi tấn công lẫn khi bị đánh)
    Enum.reduce(Map.drop(tab, [:draws, :len]), {0, 0}, fn
      {{^c, _}, {w, t}}, {x, y} -> {x + w, y + t}
      {{_, ^c}, {w, t}}, {x, y} when tab == slay -> {x + t - w, y + t}
      _, acc -> acc
    end)
  end

  {dr, dt} = slay[:draws]
  {ln, lt} = slay[:len]

  IO.puts(
    "Đồ sát (đi trước thắng, cùng lớp: #{pct.(elem(first, 0), elem(first, 1))}; hòa 200 lượt: #{pct.(dr, dt)}; TB #{round(ln / lt)} lượt):"
  )

  for a <- classes,
      do:
        IO.puts(
          "  #{a} tấn công: " <>
            Enum.map_join(classes -- [a], "  ", fn b -> {w, t} = slay[{a, b}]; "#{b} #{pct.(w, t)}" end)
        )

  IO.puts(
    "  TỔNG đồ sát: " <>
      Enum.map_join(classes, "  ", fn c -> {w, t} = total.(slay, c); "#{c} #{pct.(w, t)}" end)
  )

  IO.puts(
    "  TỔNG PK cược: " <>
      Enum.map_join(classes, "  ", fn c -> {w, t} = total.(pk, c); "#{c} #{pct.(w, t)}" end)
  )
end

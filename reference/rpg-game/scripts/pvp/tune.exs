# DS-6 (d): tự chỉnh RULES.pvp.class_taken (hệ số sát thương nhận theo lớp) để 4 lớp thắng ~50% khi đánh người, với
# nhân vật đồ giống hệt nhau theo mốc chuyển sinh (Max.tier/2). Mỗi vòng: đo tỉ lệ thắng mỗi lớp (đồ sát cả hai chiều,
# có bình máu như người thật, + PK cược), lớp thắng nhiều thì nhận sát thương nhiều hơn:
#   taken[c] ×= (thắng[c] / 50%) ^ bước (bước đầu STEP, tệ đi thì quay về bộ tốt nhất và giảm nửa bước), rồi chuẩn hóa để trung bình nhân giữ như ban đầu (sát thương chung không đổi).
# Hai kiểu:
#   TUNE=tier   chỉnh riêng từng mốc → bảng theo số lần chuyển sinh (xem một bộ chung có đủ không)
#   TUNE=global một bộ chung cho mọi mốc trong KS (tối thiểu tổng lệch), in lệch còn lại từng mốc
#   TUNE=check  đo một bảng có sẵn: TABLE=file.json {"0-3": {"dk": 1.0, …}, "4": {…}} (khóa: mốc hoặc khoảng mốc)
#   KS=0,1,2,3,4,5,6,7,8,9,10 N=24 ITERS=6 STEP=0.3 TUNE=tier mix run --no-start scripts/pvp/tune.exs
#   TUNE=check TABLE=tmp/taken.json SEED=1 N=48 mix run --no-start scripts/pvp/tune.exs
# Đè bảng bằng :persistent_term ({Engine, :class_taken}), không sửa rules.json; in số để chép vào rules.json.
Code.require_file(Path.join(__DIR__, "sim.exs"))
System.put_env("POT", System.get_env("POT") || "1")

alias HacLong.Game.{Engine, PkFight}

ks =
  (System.get_env("KS") || "0,1,2,3,4,5,6,7,8,9,10")
  |> String.split(",")
  |> Enum.map(&String.to_integer/1)

n = String.to_integer(System.get_env("N") || "24")
iters = String.to_integer(System.get_env("ITERS") || "6")
step = String.to_float(System.get_env("STEP") || "0.3")
mode = System.get_env("TUNE") || "tier"
# SEED=…: bộ seed khác (kiểm lại bảng đã chỉnh trên seed chưa dùng khi chỉnh)
seed = String.to_integer(System.get_env("SEED") || "0")
classes = ~w(dk dw elf mg)

base =
  Map.new(Engine.pvp_rules()[:class_taken] || %{}, fn {c, v} -> {to_string(c), v} end)
  |> then(&Map.new(classes, fn c -> {c, &1[c] || 1.0} end))

gmean = fn t -> :math.exp(Enum.sum(Enum.map(classes, &:math.log(t[&1]))) / length(classes)) end
g0 = gmean.(base)

char = fn c, k ->
  {p, _} = Max.tier(c, k)
  d = Engine.derived(p)
  inv = p.inv |> Map.put("potion_l", 100) |> Map.put("mana_l", 100)
  %{p | hp: d.maxHp, battle: nil, inv: inv} |> Map.put(:mp, d.maxMp)
end

chars = for k <- ks, c <- classes, into: %{}, do: {{c, k}, char.(c, k)}

# tỉ lệ thắng mỗi lớp ở mốc k với bảng t (hòa không tính); cùng seed mỗi lần đo để so vòng trước / sau công bằng
measure = fn t, k ->
  :persistent_term.put({Engine, :class_taken}, t)
  :rand.seed(:exsss, {k + 1, 7, 11 + seed})

  slay =
    for a <- classes, b <- classes, a != b, reduce: %{} do
      acc ->
        res =
          for _ <- 1..n, do: SlaySim.fight(chars[{a, k}], %{chars[{b, k}] | name: "#{b}x"}).winner

        w = Enum.count(res, &(&1 == 1))
        l = Enum.count(res, &(&1 == 2))

        acc
        |> Map.update(a, {w, w + l}, fn {x, y} -> {x + w, y + w + l} end)
        |> Map.update(b, {l, w + l}, fn {x, y} -> {x + l, y + w + l} end)
    end

  pk =
    for a <- classes, b <- classes, a < b, reduce: %{} do
      acc ->
        res =
          for _ <- 1..n,
              do: PkFight.fight(chars[{a, k}], %{chars[{b, k}] | name: "#{b}x"}, 1, 2).winner

        wa = Enum.count(res, &(&1 == :a))
        wb = Enum.count(res, &(&1 == :b))

        acc
        |> Map.update(a, {wa, wa + wb}, fn {x, y} -> {x + wa, y + wa + wb} end)
        |> Map.update(b, {wb, wa + wb}, fn {x, y} -> {x + wb, y + wa + wb} end)
    end

  r = fn {w, tot} -> if tot == 0, do: 0.5, else: w / tot end
  Map.new(classes, fn c -> {c, %{slay: r.(slay[c]), pk: r.(pk[c])}} end)
end

# thắng gộp (đồ sát 2/3, PK 1/3: đồ sát là chế độ chính, mỗi lớp có gấp đôi trận đồ sát)
wr = fn m, c -> (2 * m[c].slay + m[c].pk) / 3 end
dev = fn m -> Enum.max(Enum.map(classes, &abs(wr.(m, &1) - 0.5))) end
fmt_t = fn t -> Enum.map_join(classes, " ", &"#{&1} #{Float.round(t[&1], 2)}") end

fmt_m = fn m ->
  Enum.map_join(classes, "  ", fn c ->
    "#{c} #{round(m[c].slay * 100)}/#{round(m[c].pk * 100)}"
  end)
end

update = fn t, ms, step ->
  # ms: danh sách kết quả các mốc cần khớp chung; lớp thắng nhiều nhận sát thương nhiều hơn
  t =
    Map.new(classes, fn c ->
      w = Enum.sum(Enum.map(ms, &wr.(&1, c))) / length(ms)
      {c, t[c] * :math.pow(max(w, 0.05) / 0.5, step)}
    end)

  g = gmean.(t)
  Map.new(t, fn {c, v} -> {c, v * g0 / g} end)
end

IO.puts(
  "bảng hiện tại: #{fmt_t.(base)} | N=#{n}/cặp, #{iters} vòng, STEP #{step}, chế độ #{mode}"
)

IO.puts("(số in: thắng đồ sát / thắng PK cược, %)")

case mode do
  "tier" ->
    rows =
      for k <- ks do
        m0 = measure.(base, k)

        IO.puts(
          "\n#{k} lần chuyển sinh — bảng hiện tại: #{fmt_m.(m0)} (lệch tối đa #{round(dev.(m0) * 100)}%)"
        )

        {best, bm, _} =
          Enum.reduce(1..iters, {base, m0, step}, fn i, {b, bm, st} ->
            t2 = update.(b, [bm], st)
            m2 = measure.(t2, k)
            IO.puts("  vòng #{i}: #{fmt_t.(t2)} → #{fmt_m.(m2)} (lệch #{round(dev.(m2) * 100)}%)")
            if dev.(m2) < dev.(bm), do: {t2, m2, st}, else: {b, bm, st / 2}
          end)

        IO.puts("  TỐT NHẤT: #{fmt_t.(best)} (lệch #{round(dev.(bm) * 100)}%)")
        {k, best, dev.(m0), dev.(bm)}
      end

    IO.puts("\n===== bảng theo mốc =====")

    for {k, t, d0, d1} <- rows,
        do: IO.puts("r#{k}: #{fmt_t.(t)}   lệch #{round(d0 * 100)}% → #{round(d1 * 100)}%")

  "global" ->
    m0 = Map.new(ks, &{&1, measure.(base, &1)})

    for k <- ks,
        do: IO.puts("r#{k} hiện tại: #{fmt_m.(m0[k])} (lệch #{round(dev.(m0[k]) * 100)}%)")

    score = fn ms -> Enum.sum(Enum.map(ks, &dev.(ms[&1]))) / length(ks) end

    {best, bm, _} =
      Enum.reduce(1..iters, {base, m0, step}, fn i, {bt, bms, st} ->
        t2 = update.(bt, Map.values(bms), st)
        ms2 = Map.new(ks, &{&1, measure.(t2, &1)})
        IO.puts("\nvòng #{i}: #{fmt_t.(t2)} lệch TB #{round(score.(ms2) * 100)}%")

        for k <- ks,
            do: IO.puts("  r#{k}: #{fmt_m.(ms2[k])} (lệch #{round(dev.(ms2[k]) * 100)}%)")

        if score.(ms2) < score.(bms), do: {t2, ms2, st}, else: {bt, bms, st / 2}
      end)

    IO.puts(
      "\n===== bộ chung tốt nhất: #{fmt_t.(best)} (lệch TB #{round(score.(m0) * 100)}% → #{round(score.(bm) * 100)}%) ====="
    )

    for k <- ks, do: IO.puts("  r#{k}: #{fmt_m.(bm[k])} (lệch #{round(dev.(bm[k]) * 100)}%)")

  "check" ->
    rows = Jason.decode!(File.read!(System.fetch_env!("TABLE")))

    pick = fn k ->
      Enum.find_value(rows, fn {key, t} ->
        [lo, hi] =
          key
          |> String.split("-")
          |> Enum.map(&String.to_integer/1)
          |> then(&if(length(&1) == 1, do: &1 ++ &1, else: &1))

        k in lo..hi && Map.new(classes, fn c -> {c, t[c] * 1.0} end)
      end) || base
    end

    devs =
      for k <- ks do
        t = pick.(k)
        m = measure.(t, k)
        IO.puts("r#{k}: #{fmt_t.(t)} → #{fmt_m.(m)} (lệch #{round(dev.(m) * 100)}%)")
        dev.(m)
      end

    IO.puts(
      "lệch TB #{round(Enum.sum(devs) / length(devs) * 100)}%, tối đa #{round(Enum.max(devs) * 100)}%"
    )
end

# Cân bằng lớp khi đồ sát theo mốc chuyển sinh (RULES.pvp.class_taken_by_rebirth). Hướng dẫn: scripts/pvp/README.md.
#
#   mix run --no-start scripts/pvp/tune.exs                 kiểm tra bảng hiện tại (mặc định)
#   TUNE=1 mix run --no-start scripts/pvp/tune.exs          tự chỉnh mốc nào lệch quá TOL, in bảng gợi ý
#   TUNE=1 WRITE=1 mix run --no-start scripts/pvp/tune.exs  như trên rồi ghi luôn vào priv/game_data/rules.json
#
# Biến: KS=0,1,…,10 (mốc), N (trận mỗi chiều mỗi cặp lớp: kiểm 48, chỉnh 32), N_VERIFY=48, TOL=0.10 (lệch cho phép
# so với 50%), ITERS=8, STEP=0.3 (bước chỉnh). Chỉnh đo trên seed 0, kiểm lại trên seed 1 (bộ số ngẫu nhiên khác) trước
# khi gợi ý. Kết quả cũng ghi ở tmp/pvp_tune/report.md và tmp/pvp_tune/suggest.json.
Code.require_file(Path.join(__DIR__, "balance.exs"))

env = fn k, d -> System.get_env(k) || d end
ks = env.("KS", "0,1,2,3,4,5,6,7,8,9,10") |> String.split(",") |> Enum.map(&String.to_integer/1)
tol = String.to_float(env.("TOL", "0.10"))
tune? = System.get_env("TUNE") == "1"
n = String.to_integer(env.("N", if(tune?, do: "32", else: "48")))
n_verify = String.to_integer(env.("N_VERIFY", "48"))
opts = [n: n, tol: tol, iters: String.to_integer(env.("ITERS", "8")), step: String.to_float(env.("STEP", "0.3"))]

table = PvpBalance.rules_table()
pc = fn x -> "#{round(x * 100)}%" end
dev = &PvpBalance.dev/1
File.mkdir_p!("tmp/pvp_tune")

if not tune? do
  IO.puts("Kiểm tra RULES.pvp.class_taken_by_rebirth (đồ sát, đồ giống nhau theo mốc, N=#{n}/chiều, lệch cho phép #{pc.(tol)})\n")

  rows =
    for k <- ks do
      r = PvpBalance.row(table, k)
      m = PvpBalance.measure(r, k, n, 1)
      ok = dev.(m) <= tol
      mark = if ok, do: "✓", else: "✗ CẦN CHỈNH"
      IO.puts("r#{k}: #{PvpBalance.fmt_m(m)}  lệch #{pc.(dev.(m))} #{mark}  (hòa #{pc.(m.draws)})")
      {k, r, m, ok}
    end

  bad = for {k, _, _, false} <- rows, do: k

  IO.puts(
    if bad == [],
      do: "\nĐẠT: mọi mốc lệch ≤ #{pc.(tol)}.",
      else: "\nCHƯA ĐẠT ở mốc #{Enum.join(bad, ", ")} → chạy TUNE=1 để có gợi ý."
  )

  File.write!(
    "tmp/pvp_tune/report.md",
    "# Kiểm tra cân bằng đồ sát\n\n| Mốc | Hệ số (dk dw elf mg) | Thắng | Lệch |\n|---|---|---|---|\n" <>
      Enum.map_join(rows, "\n", fn {k, r, m, ok} ->
        "| r#{k} | #{PvpBalance.fmt_row(r)} | #{PvpBalance.fmt_m(m)} | #{pc.(dev.(m))} #{if ok, do: "✓", else: "✗"} |"
      end) <> "\n"
  )

  if bad != [], do: System.halt(1)
else
  IO.puts("Tự chỉnh (chỉnh trên seed 0 N=#{n}, kiểm lại seed 1 N=#{n_verify}, lệch cho phép #{pc.(tol)})")

  results =
    for k <- ks do
      cur = PvpBalance.row(table, k)
      IO.puts("\nr#{k} — hiện tại #{PvpBalance.fmt_row(cur)}")
      {best, _bm, log} = PvpBalance.tune(k, cur, opts)

      for {t, m} <- log,
          do: IO.puts("    #{PvpBalance.fmt_row(t)} → #{PvpBalance.fmt_m(m)} (lệch #{pc.(dev.(m))})")

      # kiểm lại trên bộ số khác: chỉ nhận bộ mới khi tốt hơn bộ hiện tại
      vc = PvpBalance.measure(cur, k, n_verify, 1)
      vb = if best == cur, do: vc, else: PvpBalance.measure(best, k, n_verify, 1)
      {pick, vp} = if dev.(vb) < dev.(vc), do: {best, vb}, else: {cur, vc}
      what = if pick == cur, do: "GIỮ", else: "ĐỔI thành #{PvpBalance.fmt_row(pick)}"
      IO.puts("  kiểm lại: hiện tại lệch #{pc.(dev.(vc))}, gợi ý lệch #{pc.(dev.(vb))} → #{what}")
      {k, cur, pick, vc, vp}
    end

  suggest = Map.merge(table, Map.new(results, fn {k, _, p, _, _} -> {k, p} end))

  lines =
    ["===== Gợi ý class_taken_by_rebirth (dk dw elf mg) ====="] ++
      Enum.map(results, fn {k, c, p, vc, vp} ->
        "r#{k}: #{PvpBalance.fmt_row(p)}   lệch #{pc.(dev.(vc))} → #{pc.(dev.(vp))}" <>
          if(p == c, do: "  (giữ)", else: "  (trước: #{PvpBalance.fmt_row(c)})")
      end)

  IO.puts("\n" <> Enum.join(lines, "\n"))

  File.write!(
    "tmp/pvp_tune/suggest.json",
    Jason.encode!(Map.new(suggest, fn {k, r} -> {to_string(k), r} end), pretty: true)
  )

  File.write!("tmp/pvp_tune/report.md", "# Gợi ý cân bằng đồ sát\n\n```\n" <> Enum.join(lines, "\n") <> "\n```\n")

  if System.get_env("WRITE") == "1" do
    PvpBalance.write_rules!(suggest)
    IO.puts("\nĐã ghi priv/game_data/rules.json. Chạy lại không có TUNE để kiểm tra, rồi mix test.")
  else
    IO.puts("\nChưa ghi rules.json (thêm WRITE=1 để ghi). Bảng gợi ý: tmp/pvp_tune/suggest.json")
  end
end

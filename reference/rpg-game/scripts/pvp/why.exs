# DS-6: tìm nguyên nhân gốc lệch cân bằng lớp theo mốc chuyển sinh (nhân vật hành trình ở tmp/journey_pk, chạy
# scripts/pvp/journey_pk.exs trước). Mỗi mốc in: chỉ số, kỹ năng mang + thông thạo, sát thương trung bình mỗi lượt
# (DPT, chuỗi 60 lượt thật: hồi chiêu, MP, hiệu ứng) lên từng lớp, và số lượt để hạ (TTK = máu đối thủ / DPT).
#   KS=0,3,7,10 mix run --no-start scripts/pvp/why.exs
alias HacLong.Game.{Engine, Mastery}
alias HacLong.Slay

ks = (System.get_env("KS") || "0,3,7,10") |> String.split(",") |> Enum.map(&String.to_integer/1)
classes = ~w(dk dw elf mg)
pad = 10_000_000

load = fn c, k, s ->
  p = :erlang.binary_to_term(File.read!("tmp/journey_pk/#{c}-r#{k}-s#{s}.bin"))
  d = Engine.derived(p)
  %{p | hp: d.maxHp, battle: nil} |> Map.put(:mp, d.maxMp)
end

# sát thương trung bình mỗi lượt của a lên bản sao b (không hồi máu / bình, chỉ ra đòn), và % lượt dùng kỹ năng
dpt = fn a, b ->
  {_, p} = Engine.start_with_monster(a, 0, Slay.opponent(%{b | name: "Bia"}, 2))
  p = put_in(p, [:battle, :live], true)

  {_, tot, sk} =
    Enum.reduce(1..60, {p, 0, 0}, fn _, {p, tot, sk} ->
      p = put_in(p, [:battle, :monster, :hp], pad) |> put_in([:battle, :log], [])
      # INF_MP=1: MP vô hạn (xem thiếu MP làm mất bao nhiêu sát thương)
      p = if System.get_env("INF_MP") == "1", do: Map.put(p, :mp, 99_999), else: p
      {act, k} = Engine.auto_strike(p)
      {_, p2} = Engine.act(p, act, k)
      {%{p2 | hp: p.hp}, tot + pad - p2.battle.monster.hp, sk + if(k, do: 1, else: 0)}
    end)

  {tot / 60, sk / 60}
end

for k <- ks do
  IO.puts("\n================ #{k} lần chuyển sinh ================")
  ps = for c <- classes, s <- [1, 2], into: %{}, do: {{c, s}, load.(c, k, s)}

  for c <- classes, s <- [1, 2] do
    p = ps[{c, s}]
    d = Engine.derived(p)

    IO.puts(
      "#{c}#{s}: máu #{d.maxHp} MP #{d.maxMp} công #{round((d.atkMin + d.atkMax) / 2)} thủ #{d.def} " <>
        "chí mạng #{round(d.crit * 100)}% ×#{Float.round(d.critMult, 2)} né #{round(d.dodge * 100)}% " <>
        "cánh +#{round(d.wingDmg * 100)}%/-#{round(d.wingAbsorb * 100)}% exc -#{round(d.excAbsorb * 100)}% kỹ năng +#{round(d.skillDmg * 100)}% " <>
        "| điểm #{inspect(p.stats)} tháp #{Map.get(p, :tower_best) || 0}"
    )

    IO.puts(
      "      kỹ năng: " <>
        Enum.map_join(Engine.skills(p), ", ", &"#{&1.name} (TT#{Mastery.level(p, &1.id)})")
    )
  end

  IO.puts("  DPT (sát thương / lượt, % lượt dùng kỹ năng) → TTK (lượt để hạ), seed 1:")

  for a <- classes do
    row =
      for b <- classes, a != b do
        pa = ps[{a, 1}]
        pb = ps[{b, 1}]
        {x, skr} = dpt.(pa, pb)
        "#{b} #{round(x)} (#{round(skr * 100)}%) → #{Float.round(Engine.derived(pb).maxHp / max(x, 1), 1)}"
      end

    IO.puts("    #{a} đánh: " <> Enum.join(row, "   "))
  end
end

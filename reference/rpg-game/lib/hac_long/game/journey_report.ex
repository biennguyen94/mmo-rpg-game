defmodule HacLong.Game.JourneyReport do
  @moduledoc "In kết quả `HacLong.Game.Journey` ra Markdown (báo cáo) và CSV (từng trận)."

  alias HacLong.Game.Data

  @doc "Báo cáo Markdown của một hành trình."
  def markdown(r, seed) do
    """
    # Hành trình #{Data.class(r.cls).name} (#{r.cls})

    Seed #{seed || "ngẫu nhiên"} · mục tiêu chuyển sinh #{r.opts.rebirths} · #{if r.done, do: "**hoàn thành**", else: "**chưa xong** (hết max_fights)"}

    ## Tổng
    | Trận | Lượt | Lượt / trận | Chết | Chuyển sinh | Cấp cuối | Trùm vùng đã hạ | Vàng nghỉ trọ | Về Nhà uống giếng (hết vàng) |
    |---|---|---|---|---|---|---|---|---|
    | #{r.fights} | #{r.turns} | #{dec(r.turns / max(1, r.fights))} | #{r.deaths} | #{r.rebirths} | #{r.level} | #{r.bosses} | #{r.rest_gold} | #{r.fountain} |

    Ép đồ: #{r.upgrades.tries} lần, thành công #{r.upgrades.ok}, về +0 #{r.upgrades.reset}, vỡ #{r.upgrades.destroy} · Ngọc Sinh Mệnh: #{r.lines.tries} lần, thêm dòng #{r.lines.ok} · ghép cánh #{r.wing_tries} lần · vàng cho thú cưng (mua, thuần, cho ăn) #{r.pet_gold}.
    #{tower(r)}

    ## Sổ ngọc (vào + / ra −, theo nguồn)
    #{ledger(r)}

    ## Từng chặng (giữa hai lần chuyển sinh)
    #{cycles(r)}

    ## Theo khoảng cấp
    #{bands(r)}

    ## Quái hay làm gục (nhiều trận thua nhất)
    #{deadly(r)}

    ## Nhân vật ở các mốc
    #{snapshots(r)}

    ## Diễn biến
    #{events(r)}
    """
  end

  defp tower(%{tower: t}) when is_map(t),
    do:
      "Tháp Vô Tận: #{t.runs} lần leo, vượt #{t.floors} tầng, #{t.fights} trận (thua #{t.losses}), kỷ lục tầng #{t.best}."

  defp tower(_r), do: ""

  defp ledger(%{ledger: l}) when map_size(l) > 0 do
    ids = l |> Map.keys() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
    whys = l |> Map.keys() |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

    "| Nguồn | " <>
      Enum.map_join(ids, " | ", &Data.item(&1).name) <>
      " |\n|---|" <>
      String.duplicate("---|", length(ids)) <>
      "\n" <>
      Enum.map_join(whys, "\n", fn w ->
        "| #{w} | " <> Enum.map_join(ids, " | ", &"#{Map.get(l, {&1, w}, "")}") <> " |"
      end)
  end

  defp ledger(_r), do: ""

  defp cycles(r) do
    head =
      "| Chặng | Trận | Thắng | Thua | Lượt / trận | Máu bị đánh / trận thắng | Vàng | Kinh nghiệm |\n|---|---|---|---|---|---|---|---|\n"

    rows =
      r.cycles
      |> Enum.sort()
      |> Enum.map_join("\n", fn {k, c} ->
        "| #{cycle_name(k)} | #{c.fights} | #{c.wins} | #{c.losses} | #{dec(c.turns / c.fights)} | #{pct(c.lost / max(1, c.wins))} | #{c.gold} | #{c.xp} |"
      end)

    head <> rows
  end

  defp cycle_name(0), do: "Chưa chuyển sinh"
  defp cycle_name(k), do: "Sau chuyển sinh #{k}"

  defp bands(r) do
    head =
      "| Chặng | Cấp | Trận | Thua | Lượt / trận | Máu bị đánh / trận thắng | Vàng / trận | Bản đồ chính |\n|---|---|---|---|---|---|---|---|\n"

    rows =
      r.bands
      |> Enum.sort()
      |> Enum.map_join("\n", fn {{k, b}, c} ->
        maps =
          c.maps
          |> Enum.sort_by(&(-elem(&1, 1)))
          |> Enum.take(3)
          |> Enum.map_join(", ", fn {n, x} -> "#{n} (#{x})" end)

        "| #{k} | #{if b == 5, do: "cày (cấp tối đa)", else: "#{b * 10 + 1}–#{b * 10 + 10}"} | #{c.fights} | #{c.losses} | #{dec(c.turns / c.fights)} | #{pct(c.lost / max(1, c.wins))} | #{round(c.gold / c.fights)} | #{maps} |"
      end)

    head <> rows
  end

  defp deadly(r) do
    rows =
      r.mons
      |> Enum.filter(fn {_, c} -> c.losses > 0 end)
      |> Enum.sort_by(fn {_, c} -> -c.losses end)
      |> Enum.take(12)

    if rows == [] do
      "Không thua trận nào."
    else
      "| Quái | Cấp | Bản đồ | Trận | Thua | Lượt / trận |\n|---|---|---|---|---|---|\n" <>
        Enum.map_join(rows, "\n", fn {{name, lv, map}, c} ->
          "| #{name} | #{lv} | #{map} | #{c.fights} | #{c.losses} (#{pct(c.losses / c.fights)}) | #{dec(c.turns / c.fights)} |"
        end)
    end
  end

  defp snapshots(r) do
    Enum.map_join(r.snapshots, "\n\n", fn {label, fights, s} ->
      d = s.derived

      """
      ### #{label} (sau #{fights} trận)
      Cấp #{s.level}, chuyển sinh #{s.rebirths}, chết #{s.deaths}, vàng #{s.gold} · Sức #{s.stats.str} / Nhanh #{s.stats.agi} / Thể #{s.stats.vit} / Năng lượng #{s.stats.ene}
      Máu #{d.maxHp}, MP #{d.maxMp}, công #{d.atkMin}–#{d.atkMax}, thủ #{d.def}, chí mạng #{pct(d.crit)} ×#{dec(d.critMult)}, né #{pct(d.dodge)}, trúng #{pct(d.hitRate)}

      #{Enum.map_join(s.gear, "\n", fn {slot, name} -> "- #{slot}: #{name}" end)}

      Thú: #{s.pet} · Ngọc: #{kv(s.jewels)} · Bình: #{kv(s.potions)}
      """
    end)
  end

  defp events(r) do
    Enum.map_join(r.events, "\n", fn
      {f, nil, nil, text} -> "- trận #{f}: #{text}"
      {f, k, l, text} -> "- trận #{f} (CS #{k}, cấp #{l}): #{text}"
    end)
  end

  @doc "Bảng so sánh nhiều hành trình (mỗi dòng một lớp / một lần chạy)."
  def summary(results) do
    max_k = results |> Enum.flat_map(&Map.keys(&1.cycles)) |> Enum.max(fn -> 0 end)
    cols = Enum.map(0..max_k, &"Trận chặng #{&1}")

    head =
      "| Lớp | Xong | Trận | Chết | " <>
        Enum.join(cols, " | ") <> " |\n|" <> String.duplicate("---|", 4 + length(cols)) <> "\n"

    head <>
      Enum.map_join(results, "\n", fn r ->
        per = Enum.map_join(0..max_k, " | ", &"#{get_in(r.cycles, [&1, :fights]) || "—"}")

        "| #{r.cls} | #{if r.done, do: "có", else: "không"} | #{r.fights} | #{r.deaths} | #{per} |"
      end)
  end

  @doc "CSV từng trận (cần `rows: true`)."
  def csv(r) do
    keys = ~w(fight rebirths level map monster monster_level result turns hp_lost_pct gold xp)a

    [
      Enum.join(keys, ",")
      | Enum.map(r.rows, fn row -> Enum.map_join(keys, ",", &cell(row[&1])) end)
    ]
    |> Enum.join("\n")
  end

  defp cell(v) when is_binary(v), do: "\"" <> String.replace(v, "\"", "\"\"") <> "\""
  defp cell(v), do: to_string(v)

  defp kv(m) when map_size(m) == 0, do: "—"
  defp kv(m), do: Enum.map_join(m, ", ", fn {k, v} -> "#{k} #{v}" end)

  defp pct(x), do: "#{dec(x * 100)}%"
  defp dec(x), do: :erlang.float_to_binary(x * 1.0, decimals: 1)
end

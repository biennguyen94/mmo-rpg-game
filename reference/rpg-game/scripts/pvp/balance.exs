# Cân bằng lớp khi đồ sát theo mốc chuyển sinh (DS-6): đo tỉ lệ thắng 4 lớp đồ giống hệt nhau (Max.tier/2) và tự chỉnh
# RULES.pvp.class_taken_by_rebirth. Dùng chung cho scripts/pvp/tune.exs (dòng lệnh) và test `mix test --only balance`.
# Cách dùng: scripts/pvp/README.md.
Code.require_file(Path.join(__DIR__, "sim.exs"))

defmodule PvpBalance do
  alias HacLong.Game.Engine

  @classes ~w(dk dw elf mg)
  @rules "priv/game_data/rules.json"

  def classes, do: @classes

  @doc "Bảng hiện tại trong rules.json: %{mốc => %{lớp => hệ số}}."
  def rules_table do
    Map.new(Engine.pvp_rules()[:class_taken_by_rebirth] || %{}, fn {k, row} ->
      {String.to_integer(to_string(k)), Map.new(row, fn {c, v} -> {to_string(c), v * 1.0} end)}
    end)
  end

  @doc "Dòng dùng cho mốc k (như Engine: mốc lớn nhất ≤ k, quá bảng thì dòng cuối)."
  def row(table, k) do
    table |> Enum.sort() |> Enum.reduce(nil, fn {r, row}, acc -> if r <= k or acc == nil, do: row, else: acc end)
  end

  # nhân vật mốc k (đồ giống hệt nhau mọi lớp), mang 100 bình máu / mana
  defp char(c, k) do
    key = {__MODULE__, c, k}

    Process.get(key) ||
      (
        {p, _} = Max.tier(c, k)
        d = Engine.derived(p)
        inv = p.inv |> Map.put("potion_l", 100) |> Map.put("mana_l", 100)
        p = %{p | hp: d.maxHp, battle: nil, inv: inv} |> Map.put(:mp, d.maxMp)
        Process.put(key, p)
        p
      )
  end

  @doc """
  Tỉ lệ thắng mỗi lớp ở mốc `k` với dòng hệ số `row`: mỗi cặp lớp đánh `n` trận mỗi chiều (người tấn công đi trước,
  uống bình như người thật). Trận hòa không tính. Trả %{lớp => tỉ lệ, :draws => tỉ lệ hòa}.
  """
  def measure(row, k, n, seed) do
    System.put_env("POT", "1")
    :persistent_term.put({Engine, :class_taken}, row)
    :rand.seed(:exsss, {k + 1, 7, 11 + seed})

    {acc, draws, total} =
      for a <- @classes, b <- @classes, a != b, reduce: {%{}, 0, 0} do
        {acc, dr, tot} ->
          res = for _ <- 1..n, do: SlaySim.fight(char(a, k), %{char(b, k) | name: "#{b}x"}).winner
          w = Enum.count(res, &(&1 == 1))
          l = Enum.count(res, &(&1 == 2))

          acc =
            acc
            |> Map.update(a, {w, w + l}, fn {x, y} -> {x + w, y + w + l} end)
            |> Map.update(b, {l, w + l}, fn {x, y} -> {x + l, y + w + l} end)

          {acc, dr + n - w - l, tot + n}
      end

    :persistent_term.erase({Engine, :class_taken})

    Map.new(@classes, fn c -> {w, t} = acc[c]; {c, if(t == 0, do: 0.5, else: w / t)} end)
    |> Map.put(:draws, draws / total)
  end

  @doc "Độ lệch: lớp xa 50% nhất."
  def dev(m), do: @classes |> Enum.map(&abs(m[&1] - 0.5)) |> Enum.max()

  @doc """
  Chỉnh dòng mốc `k` bắt đầu từ `start`: mỗi vòng hệ số[lớp] ×= (thắng / 50%) ^ bước (lớp thắng nhiều nhận sát thương
  nhiều hơn), chuẩn hóa giữ trung bình nhân như `start`; vòng tệ đi thì quay về bộ tốt nhất và giảm nửa bước.
  Dừng khi lệch ≤ `tol`. Trả `{dòng tốt nhất, kết quả đo, nhật ký}`.
  """
  def tune(k, start, opts) do
    n = opts[:n] || 32
    seed = opts[:seed] || 0
    tol = opts[:tol] || 0.1
    g0 = gmean(start)
    m0 = measure(start, k, n, seed)

    {best, bm, _, log} =
      Enum.reduce_while(1..(opts[:iters] || 8), {start, m0, opts[:step] || 0.3, [{start, m0}]}, fn _, {b, bm, st, log} ->
        if dev(bm) <= tol do
          {:halt, {b, bm, st, log}}
        else
          t = Map.new(@classes, fn c -> {c, b[c] * :math.pow(max(bm[c], 0.05) / 0.5, st)} end)
          g = gmean(t)
          t = Map.new(t, fn {c, v} -> {c, Float.round(v * g0 / g, 2)} end)
          m = measure(t, k, n, seed)
          log = log ++ [{t, m}]
          if dev(m) < dev(bm), do: {:cont, {t, m, st, log}}, else: {:cont, {b, bm, st / 2, log}}
        end
      end)

    {best, bm, log}
  end

  defp gmean(t), do: :math.exp(Enum.sum(Enum.map(@classes, &:math.log(t[&1]))) / length(@classes))

  @doc "Ghi bảng vào rules.json (chỉ thay khối class_taken_by_rebirth, giữ nguyên phần còn lại của file)."
  def write_rules!(table) do
    src = File.read!(@rules)

    rows =
      table
      |> Enum.sort()
      |> Enum.map_join(",\n", fn {k, r} ->
        ~s(        "#{k}": {) <> Enum.map_join(@classes, ", ", &~s("#{&1}": #{num(r[&1])})) <> "}"
      end)

    re = ~r/"class_taken_by_rebirth": \{\n.*?\n      \}/s
    true = Regex.match?(re, src)
    File.write!(@rules, Regex.replace(re, src, ~s("class_taken_by_rebirth": {\n#{rows}\n      }), global: false))
  end

  defp num(v), do: :erlang.float_to_binary(v * 1.0, [:compact, decimals: 2])

  def fmt_row(r), do: Enum.map_join(@classes, " ", &"#{&1} #{num(r[&1])}")
  def fmt_m(m), do: Enum.map_join(@classes, "  ", &"#{&1} #{round(m[&1] * 100)}%")
end

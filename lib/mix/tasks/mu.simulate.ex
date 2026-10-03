defmodule Mix.Tasks.Mu.Simulate do
  @shortdoc "Mô phỏng DK đánh Spider tới maxLevel, in số con/thời gian/potion"
  @moduledoc """
      mix mu.simulate                   # 50 lần, cộng điểm cân bằng, không trang bị
      mix mu.simulate --runs 200 --strategy str
      mix mu.simulate --gear full       # mặc toàn bộ trang bị Phase 1 (so Q14)

  Tùy chọn: `--runs N`, `--strategy balanced|str|agi|vit`, `--walk-ms N`,
  `--gear none|full`. Xem giả định ở `Mu.Game.Simulator`.
  """
  use Mix.Task

  alias Mu.Game.Simulator

  @impl true
  def run(args) do
    {o, _, _} =
      OptionParser.parse(args,
        strict: [runs: :integer, strategy: :string, walk_ms: :integer, gear: :string]
      )

    gear =
      case o[:gear] do
        "full" -> Enum.filter(Simulator.item_templates(), &(&1["slot"] != nil))
        _ -> []
      end

    strategy = o[:strategy] || "balanced"
    opts = %{strategy: strategy, walk_ms: o[:walk_ms] || 2000, equipment: gear}
    r = Simulator.run(o[:runs] || 50, opts)
    Mix.shell().info(format(r))
  end

  @doc false
  def format(r) do
    rows =
      for {lv, m} <- Enum.sort(r.milestones) do
        "  cấp #{pad(lv, 2)}: #{num(m.kills, 7)} con #{num(m.minutes, 7)} phút " <>
          "#{num(m.potions, 7)} potion #{num(m.deaths, 6)} lần chết  (#{m.reached}/#{r.runs} lần tới)"
      end

    """
    Mô phỏng #{r.runs} lần — cộng điểm: #{r.opts.strategy}, đi bộ giữa hai con: #{r.opts.walk_ms} ms, trang bị: #{inspect(r.opts.equipment)}
    #{Enum.join(rows, "\n")}
      Zen trung bình: #{Float.round(r.zen, 1)}  — số món rơi: #{Float.round(r.items, 1)}
      Sát thương nhận / con: #{Float.round(r.damage_taken_per_kill, 2)}  — tỉ lệ trúng: #{Float.round(r.hit_rate * 100, 1)}%
    """
  end

  defp num(x, w), do: x |> :erlang.float_to_binary(decimals: 1) |> String.pad_leading(w)
  defp pad(x, w), do: x |> to_string() |> String.pad_leading(w)
end

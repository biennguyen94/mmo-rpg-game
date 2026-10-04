defmodule Mix.Tasks.Mu.Simulate do
  @shortdoc "Mô phỏng một class đánh Spider tới maxLevel, in số con/thời gian/potion"
  @moduledoc """
      mix mu.simulate                   # 50 lần, cộng điểm cân bằng, không trang bị
      mix mu.simulate --runs 200 --strategy str
      mix mu.simulate --gear full       # mặc toàn bộ trang bị t0 của class (so Q14)
      mix mu.simulate --class DW --gear starter --strategy ene
      mix mu.simulate --class DW --strategy ene --monster auto --progress --skills   # P2-M4: tới cấp 30

  Tùy chọn: `--runs N`, `--class DK|DW|ELF`, `--strategy balanced|str|agi|vit|ene`,
  `--walk-ms N`, `--gear none|starter|full|t1`, `--monster spider|auto|<id>` (auto = quái cấp cao
  nhất ≤ cấp nhân vật), `--progress` (đồ t0 → t1 ở cấp 10), `--skills` (dùng skill đánh đã học). Xem giả định ở `Mu.Game.Simulator`.
  """
  use Mix.Task

  alias Mu.Game.Simulator

  @impl true
  def run(args) do
    {o, _, _} =
      OptionParser.parse(args,
        strict: [
          runs: :integer,
          strategy: :string,
          walk_ms: :integer,
          gear: :string,
          class: :string,
          monster: :string,
          progress: :boolean,
          skills: :boolean
        ]
      )

    gear = Simulator.gear(o[:class], o[:gear] || "none")
    strategy = o[:strategy] || "balanced"

    opts = %{
      strategy: strategy,
      walk_ms: o[:walk_ms] || 2000,
      equipment: gear,
      class: o[:class],
      monster: o[:monster] || "spider",
      gear_progress: o[:progress] || false,
      use_skills: o[:skills] || false
    }

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
    Mô phỏng #{r.runs} lần — class #{r.opts.class || "mặc định"}, quái #{r.opts.monster}, cộng điểm: #{r.opts.strategy}, đi bộ giữa hai con: #{r.opts.walk_ms} ms, trang bị: #{inspect(r.opts.equipment)}
    #{Enum.join(rows, "\n")}
      Zen trung bình: #{Float.round(r.zen, 1)}  — số món rơi: #{Float.round(r.items, 1)}  — jewel: #{Float.round(r.jewels, 1)} (#{Float.round(r.jewels_per_hour, 2)} / giờ)
      Sát thương nhận / con: #{Float.round(r.damage_taken_per_kill, 2)}  — tỉ lệ trúng: #{Float.round(r.hit_rate * 100, 1)}%
    """
  end

  defp num(x, w), do: x |> :erlang.float_to_binary(decimals: 1) |> String.pad_leading(w)
  defp pad(x, w), do: x |> to_string() |> String.pad_leading(w)
end

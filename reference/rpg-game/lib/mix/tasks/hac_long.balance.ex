defmodule Mix.Tasks.HacLong.Balance do
  @shortdoc "Ghi docs/BALANCE_REPORT.md: tỉ lệ rơi đồ, ép ngọc, Máy Hỗn Nguyên, kết quả simulator"
  @moduledoc """
  Báo cáo cân bằng (`HacLong.Game.Balance`, `docs/ITEMS_PHASE15B.md` §12):

      mix hac_long.balance            # chỉ bảng tính từ dữ liệu (nhanh)
      mix hac_long.balance --sim 3    # thêm simulator: 3 ván mỗi lớp mỗi cách chơi (vài phút)
      mix hac_long.balance --sim 3 --seed 42

  Ghi `docs/BALANCE_REPORT.md`.
  """
  use Mix.Task

  alias HacLong.Game.{Balance, Simulator}

  @out "docs/BALANCE_REPORT.md"
  @modes [
    {"chỉ đánh", []},
    {"+nhiệm vụ", [quests: true]},
    {"+hằng ngày", [quests: true, daily: true]},
    {"+nâng cấp", [quests: true, daily: true, upgrade: true]},
    {"+rương", [quests: true, daily: true, upgrade: true, chests: true]}
  ]

  @impl true
  def run(args) do
    Mix.Task.run("compile")
    {opts, _, _} = OptionParser.parse(args, strict: [sim: :integer, seed: :integer])
    if seed = opts[:seed], do: :rand.seed(:exsss, {seed, seed, seed})

    sim =
      case opts[:sim] do
        n when is_integer(n) and n > 0 -> simulate(n)
        _ -> []
      end

    File.write!(@out, Balance.report(sim))

    Mix.shell().info(
      "Đã ghi #{@out}#{if sim != [], do: " (simulator #{opts[:sim]} ván)", else: ""}."
    )
  end

  defp simulate(n) do
    for cls <- ~w(dk dw elf mg) do
      Mix.shell().info("simulator #{cls}…")

      modes =
        for {label, o} <- @modes do
          rs = for _ <- 1..n, do: Simulator.run(cls, o)
          avg = fn k -> round(Enum.sum(Enum.map(rs, & &1[k])) / n) end

          {label,
           %{
             fights: avg.(:fights),
             level: avg.(:level),
             deaths: avg.(:deaths),
             gold: avg.(:gold),
             jewels: Float.round(Enum.sum(Enum.map(rs, & &1.jewels)) / n, 1),
             wins: Enum.count(rs, & &1.victory),
             n: n
           }}
        end

      {cls, modes}
    end
  end
end

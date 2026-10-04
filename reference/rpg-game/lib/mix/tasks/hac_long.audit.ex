defmodule Mix.Tasks.HacLong.Audit do
  @shortdoc "Đối soát vàng và đồ hiếm (thoát mã 1 nếu có lỗi)"
  @moduledoc """
  Đối soát vàng (`gold_log`) và đồ hiếm (`gear_log`) với bảng nhân vật, xem `HacLong.Audit`:

      mix hac_long.audit              # đối soát + thống kê vàng 1 ngày qua
      mix hac_long.audit --days 7     # thống kê 7 ngày
      mix hac_long.audit --prune 180  # xóa nhật ký cũ hơn 180 ngày (gộp vàng thành dòng CARRY)

  Có lỗi (vàng lệch nhật ký, đồ hiếm trùng `uid`, đồ không có nhật ký) thì thoát mã 1 để dùng
  trong cron. Bản release: `bin/hac_long eval 'HacLong.Audit.run() |> IO.inspect()'`.
  """
  use Mix.Task
  require Logger

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    Logger.configure(level: :warning)
    {opts, _, _} = OptionParser.parse(args, strict: [days: :integer, prune: :integer])

    if n = opts[:prune] do
      r = HacLong.Audit.prune(n)

      Mix.shell().info(
        "Đã xóa #{r.gold} dòng nhật ký vàng, #{r.gear} dòng đồ hiếm cũ hơn #{n} ngày."
      )
    else
      report(HacLong.Audit.run(days: opts[:days] || 1))
    end
  end

  defp report(%{problems: problems, stats: st}) do
    shell = Mix.shell()
    shell.info("== Vàng #{st.days} ngày qua theo lý do ==")

    for r <- st.by_reason,
        do: shell.info("  #{String.pad_trailing(r.reason, 16)} +#{r.in}  #{r.out}  (#{r.n} lần)")

    shell.info("== Nhận nhiều vàng nhất ==")
    for t <- st.top, do: shell.info("  #{t.name || "(đã xóa) #{t.user_id}"}: +#{t.gold}")

    case problems do
      [] ->
        shell.info("Không có lỗi.")

      _ ->
        shell.error("== #{length(problems)} lỗi ==")
        for p <- problems, do: shell.error("  [#{p.kind}] #{p.text}")
        exit({:shutdown, 1})
    end
  end
end

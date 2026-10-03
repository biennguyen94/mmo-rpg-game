defmodule Mix.Tasks.Mu.Audit do
  @shortdoc "Kiểm chống dupe: serial, item không chỗ, chủ lệch audit, Zen lệch log; cung Zen"
  @moduledoc """
      mix mu.audit            # in báo cáo; có sai lệch thì exit 1
      mix mu.audit --days 30  # cung Zen theo ngày trong 30 ngày gần nhất (mặc định 7)

  Chỉ đọc DB (chỉ khởi động Repo, không mở cổng web nên chạy được cạnh server đang chạy). Các phép
  kiểm: `Mu.Audit`. Quản trị chạy sau soak / theo lịch; không tự khóa tài khoản (P5-6 (3)).
  """
  use Mix.Task
  require Logger

  @impl true
  def run(args) do
    {o, _, _} = OptionParser.parse(args, strict: [days: :integer])
    Mix.Task.run("app.config")
    Logger.configure(level: :info)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Mu.Repo.start_link()

    r = Mu.Audit.run(days: o[:days] || 7)
    s = r.supply
    Mix.shell().info("Zen đang có: #{s.total} (#{s.characters} nhân vật)")

    for d <- s.by_day,
        do:
          Mix.shell().info(
            "  #{d.day} #{String.pad_trailing(d.reason, 13)} +#{d.gained} #{d.spent}"
          )

    if r.problems == [] do
      Mix.shell().info("Không có sai lệch.")
    else
      for p <- r.problems, do: Mix.shell().error("#{p.check} #{p.id}: #{p.detail}")
      Mix.shell().error("#{length(r.problems)} sai lệch.")
      exit({:shutdown, 1})
    end
  end
end

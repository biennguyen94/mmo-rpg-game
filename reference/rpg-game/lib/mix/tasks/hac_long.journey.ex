defmodule Mix.Tasks.HacLong.Journey do
  @shortdoc "Mô phỏng cả hành trình một nhân vật: lên cấp, đồ, ép, trùm, chuyển sinh, vùng chuyển sinh"
  @moduledoc """
  Cho một bot chơi từ cấp 1 qua các lần chuyển sinh (`HacLong.Game.Journey`) và ghi báo cáo:
  mỗi chặng mất bao nhiêu trận, chết bao nhiêu, đánh ở bản đồ nào theo từng khoảng cấp, mặc đồ gì, ép tới đâu,
  chỉ số ở mỗi mốc chuyển sinh, diễn biến (hạ trùm, vào vùng chuyển sinh, ép +7 trở lên, ghép cánh, tránh bản đồ khó).

      mix hac_long.journey                          # Kiếm Sĩ, 3 lần chuyển sinh
      mix hac_long.journey --cls elf --rebirths 5 --seed 42
      mix hac_long.journey --cls all --seed 1       # cả 4 lớp, thêm bảng so sánh
      mix hac_long.journey --csv                    # thêm CSV từng trận (mở bằng Excel / Sheets)

  Tùy chọn: `--cls dk|dw|elf|mg|all`, `--rebirths N` (0–10), `--seed N`, `--max-fights N`,
  `--farm N` (đủ chuyển sinh và cấp tối đa rồi cày thêm N trận: xem rơi đồ, ép, cánh ở vùng cuối),
  `--no-quests`, `--no-soul` (không ép +7..+9), `--no-wings`, `--chaos-up` (ép +10/+11, có thể vỡ),
  `--no-boss-first` (chuyển sinh ngay ở cấp tối đa dù chưa hạ Hắc Long), `--out thư_mục` (mặc định `tmp/journey`).

  Ra: `<out>/<lớp>-s<seed>.md` (và `.csv`), `<out>/summary-s<seed>.md` khi `--cls all`. Đổi số liệu trong
  `priv/game_data/` rồi chạy lại cùng seed để so trước / sau.
  """
  use Mix.Task

  alias HacLong.Game.{Journey, JourneyReport}

  @switches [
    cls: :string,
    rebirths: :integer,
    seed: :integer,
    max_fights: :integer,
    farm: :integer,
    quests: :boolean,
    soul: :boolean,
    wings: :boolean,
    chaos_up: :boolean,
    boss_first: :boolean,
    csv: :boolean,
    out: :string
  ]

  @impl true
  def run(args) do
    Mix.Task.run("compile")
    {o, _, _} = OptionParser.parse(args, strict: @switches)
    seed = o[:seed]
    out = o[:out] || "tmp/journey"
    File.mkdir_p!(out)

    classes =
      if o[:cls] in [nil, ""],
        do: ["dk"],
        else: if(o[:cls] == "all", do: ~w(dk dw elf mg), else: [o[:cls]])

    opts =
      o
      |> Keyword.take(~w(rebirths max_fights farm quests soul wings chaos_up boss_first)a)
      |> Keyword.put(:rows, o[:csv] == true)

    results =
      for cls <- classes do
        if seed, do: :rand.seed(:exsss, {seed, seed, seed})
        t0 = System.monotonic_time(:millisecond)
        r = Journey.run(cls, opts)
        ms = System.monotonic_time(:millisecond) - t0
        base = Path.join(out, "#{cls}-s#{seed || "x"}")
        File.write!(base <> ".md", JourneyReport.markdown(r, seed))
        if o[:csv], do: File.write!(base <> ".csv", JourneyReport.csv(r))

        per =
          r.cycles
          |> Enum.sort()
          |> Enum.map_join(" · ", fn {k, c} ->
            "chặng #{k}: #{c.fights} trận, thua #{c.losses}"
          end)

        Mix.shell().info(
          "#{cls}: #{if r.done, do: "xong", else: "CHƯA XONG"} · #{r.fights} trận · chết #{r.deaths} · chuyển sinh #{r.rebirths} · cấp #{r.level} · #{div(ms, 1000)} giây\n  #{per}\n  → #{base}.md#{if o[:csv], do: " (+ .csv)"}"
        )

        r
      end

    if length(results) > 1 do
      path = Path.join(out, "summary-s#{seed || "x"}.md")

      File.write!(
        path,
        "# So sánh các lớp (seed #{seed || "ngẫu nhiên"})\n\n" <>
          JourneyReport.summary(results) <> "\n"
      )

      Mix.shell().info("→ #{path}")
    end
  end
end

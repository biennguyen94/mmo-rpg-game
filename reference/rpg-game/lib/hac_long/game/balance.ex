defmodule HacLong.Game.Balance do
  @moduledoc """
  Báo cáo cân bằng (mục 8, `docs/ITEMS_PHASE15B.md` §12): tính thẳng từ dữ liệu game (`RULES`, `UPGRADE`, `CHAOS`)
  tỉ lệ rơi đồ / dòng đặc biệt theo loại quái, tỉ lệ ép ngọc, tỉ lệ Máy Hỗn Nguyên; kèm kết quả simulator nếu có.
  Hàm thuần (không ngẫu nhiên, trừ phần simulator do `mix hac_long.balance` chạy). Đổi số trong `priv/game_data/`
  rồi chạy lại `mix hac_long.balance` là bảng tự cập nhật.
  """

  alias HacLong.Game.{Chaos, Data, Gear}

  @kinds [
    {"thường", %{boss: false}},
    {"đêm", %{night: true, boss: false}},
    {"tinh anh", %{elite: true, boss: false}},
    {"trùm", %{boss: true}}
  ]

  @slot_vi %{
    "weapon" => "vũ khí",
    "set" => "bộ giáp",
    "shield" => "khiên",
    "jewelry" => "trang sức"
  }

  @doc "Tỉ lệ mỗi loại đồ rơi ngẫu nhiên là `slot` (`weapon` / `set` / `shield` / `jewelry`) theo `RULES.loot.gear_slots`."
  def slot_shares do
    {shares, _} =
      Enum.map_reduce(Data.rules().loot.gear_slots, 0, fn [t, s], prev -> {{s, t - prev}, t} end)

    Map.new(shares)
  end

  @doc """
  Xác suất **mỗi lần hạ một quái** ra: một món đồ hiếm, món Excellent, món May mắn, vũ khí Kỹ năng, món Thần —
  theo loại quái. `[%{kind, gear, exc, luck, skill, anc}]`.
  """
  def drop_table do
    sh = slot_shares()
    skill = Data.rules().luck_skill.skill_chance

    for {kind, m} <- @kinds do
      g = Gear.drop_chance(m)

      %{
        kind: kind,
        gear: g,
        exc: g * Gear.exc_chance(m),
        luck: g * Gear.luck_chance(m),
        skill: g * Map.get(sh, "weapon", 0) * skill,
        anc: g * Map.get(sh, "set", 0) * Gear.anc_chance(m)
      }
    end
  end

  @doc "Tỉ lệ ép ngọc từng bước +6..+11: `[%{level, jewel, rate, luck_rate, fail}]`."
  def upgrade_table do
    for s <- Data.upgrade().steps do
      %{
        level: s.level,
        jewel: Data.item(s.jewel).name,
        rate: s.rate,
        luck_rate: Gear.luck_rate(%{luck: true}, s.rate),
        fail: s.fail
      }
    end
  end

  @doc "Công thức Máy Hỗn Nguyên: tỉ lệ ở cấp nâng tối thiểu, +2 và ở +11 (cấp nâng tối đa); vàng; nguyên liệu."
  def chaos_table do
    for r <- Data.chaos() do
      min = if r[:gear], do: r.gear.min_up, else: 0

      %{
        id: r.id,
        name: r.name,
        min_up: if(r[:gear], do: min),
        rate: Chaos.rate(r, min),
        rate_plus2: Chaos.rate(r, min + 2),
        rate_max: Chaos.rate(r, 11),
        gold: r.gold,
        items: Enum.map_join(r.items, ", ", fn {id, n} -> "#{n} #{Data.item(id).name}" end)
      }
    end
  end

  @doc "Số lần hạ quái trung bình để ra một lần với xác suất `p` (∞ khi 0)."
  def kills_for(p) when p > 0, do: round(1 / p)
  def kills_for(_), do: nil

  @doc """
  Báo cáo Markdown. `sim`: `[{lớp, [{cách_chơi, %{fights, level, deaths, gold, jewels, wins, n}}]}]` hoặc `[]`.
  """
  def report(sim \\ []) do
    pct = fn x -> "#{:erlang.float_to_binary(x * 100, decimals: 2)} %" end
    per = fn p -> if k = kills_for(p), do: "#{pct.(p)} (~#{k} con)", else: "0" end

    drops =
      for d <- drop_table() do
        "| #{d.kind} | #{per.(d.gear)} | #{per.(d.exc)} | #{per.(d.luck)} | #{per.(d.skill)} | #{per.(d.anc)} |"
      end

    ups =
      for u <- upgrade_table() do
        fail = %{"down" => "tụt 1 cấp", "destroy" => "vỡ đồ", nil => "—"}[u.fail]
        "| +#{u.level} | #{u.jewel} | #{pct.(u.rate)} | #{pct.(u.luck_rate)} | #{fail} |"
      end

    chaos =
      for c <- chaos_table() do
        need = if c.min_up, do: "+#{c.min_up}", else: "—"

        "| #{c.name} (`#{c.id}`) | #{need} | #{pct.(c.rate)} | #{pct.(c.rate_plus2)} | #{pct.(c.rate_max)} | " <>
          "#{c.gold} | #{c.items} |"
      end

    sim_part =
      case sim do
        [] ->
          "_Chưa chạy simulator (`mix hac_long.balance --sim 3`)._\n"

        _ ->
          rows =
            for {cls, modes} <- sim, {mode, r} <- modes do
              "| #{Data.class(cls).name} | #{mode} | #{r.fights} | #{r.level} | #{r.deaths} | #{r.gold} | " <>
                "#{r.jewels} | #{r.wins}/#{r.n} |"
            end

          """
          | Lớp | Cách chơi | Số trận | Cấp cuối | Chết | Vàng cuối | Ngọc | Hạ Hắc Long |
          |---|---|---|---|---|---|---|---|
          #{Enum.join(rows, "\n")}
          """
      end

    """
    # Báo cáo cân bằng (sinh tự động)

    > Sinh bằng `mix hac_long.balance` từ `priv/game_data/` (rules.json, upgrade.json, chaos.json). **Đừng sửa tay**: đổi số
    > trong dữ liệu rồi chạy lại. Giải thích các khóa: `docs/ITEMS_PHASE15B.md`.

    ## 1. Đồ rơi mỗi lần hạ một quái

    Xác suất trên **một** con quái (số trong ngoặc: trung bình bao nhiêu con thì ra một lần). Đồ rơi theo loại:
    #{Enum.map_join(slot_shares(), ", ", fn {s, v} -> "#{@slot_vi[s] || s} #{pct.(v)}" end)}. Trùm thế giới / đấu trường không rơi đồ hiếm.

    | Quái | Đồ hiếm | Excellent | May mắn | Vũ khí Kỹ năng | Đồ Thần |
    |---|---|---|---|---|---|
    #{Enum.join(drops, "\n")}

    ## 2. Ép ngọc +6 → +11

    | Bước | Ngọc | Tỉ lệ | Có May mắn | Thất bại |
    |---|---|---|---|---|
    #{Enum.join(ups, "\n")}

    ## 3. Máy Hỗn Nguyên

    | Công thức | Cần | Tỉ lệ | Cấp cần +2 | Ở +11 | Vàng | Nguyên liệu |
    |---|---|---|---|---|---|---|
    #{Enum.join(chaos, "\n")}

    ## 4. Simulator (chơi từ đầu tới Hắc Long)

    #{sim_part}
    """
  end
end

defmodule HacLong.Game.BalanceTest do
  @moduledoc "Báo cáo cân bằng (mục 8): số tính đúng từ dữ liệu, báo cáo đủ các phần."
  use ExUnit.Case, async: true

  alias HacLong.Game.{Balance, Data}

  test "tỉ lệ loại đồ rơi cộng lại bằng 1" do
    assert_in_delta Enum.sum(Map.values(Balance.slot_shares())), 1.0, 1.0e-9
  end

  test "bảng rơi: tích các tỉ lệ trong RULES" do
    r = Data.rules()
    sh = Balance.slot_shares()
    [normal | _] = Balance.drop_table()
    g = r.loot.gear_chance.normal
    assert normal.gear == g
    assert_in_delta normal.exc, g * r.excellent.chance.normal, 1.0e-12
    assert_in_delta normal.anc, g * sh["set"] * r.ancient.chance.normal, 1.0e-12
    assert_in_delta normal.skill, g * sh["weapon"] * r.luck_skill.skill_chance, 1.0e-12
    assert Balance.kills_for(0.25) == 4 and Balance.kills_for(0) == nil
  end

  test "ép ngọc: May mắn không làm giảm tỉ lệ; Máy Hỗn Nguyên đủ công thức" do
    for u <- Balance.upgrade_table(), do: assert(u.luck_rate >= u.rate)
    assert length(Balance.chaos_table()) == length(Data.chaos())
  end

  test "báo cáo có đủ 4 phần, có / không có simulator" do
    md = Balance.report()
    for h <- ["## 1.", "## 2.", "## 3.", "## 4."], do: assert(md =~ h)
    assert md =~ "Chưa chạy simulator"

    sim = [
      {"dk",
       [{"chỉ đánh", %{fights: 400, level: 35, deaths: 0, gold: 100, jewels: 3.0, wins: 1, n: 1}}]}
    ]

    assert Balance.report(sim) =~ "| Kiếm Sĩ | chỉ đánh | 400 | 35 | 0 | 100 | 3.0 | 1/1 |"
  end
end

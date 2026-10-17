defmodule HacLong.Game.JourneyTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Journey, JourneyReport}

  test "hành trình ngắn: lên cấp, ghi số liệu theo chặng / khoảng cấp, in được báo cáo và CSV" do
    :rand.seed(:exsss, {3, 3, 3})
    r = Journey.run("elf", rebirths: 0, max_fights: 150, rows: true)

    assert r.fights == 150 and not r.done
    assert r.level > 10
    assert r.cycles[0].fights == 150
    assert Enum.sum(Enum.map(r.bands, fn {_, c} -> c.fights end)) == 150
    assert length(r.rows) == 150
    assert [{"Kết thúc", 150, %{level: lv}}] = r.snapshots
    assert lv == r.level

    md = JourneyReport.markdown(r, 3)
    assert md =~ "Theo khoảng cấp" and md =~ "Diễn biến"
    assert JourneyReport.csv(r) |> String.split("\n") |> length() == 151
  end

  test "đủ cấp tối đa thì chuyển sinh, về cấp 1 và đi tiếp" do
    :rand.seed(:exsss, {5, 5, 5})
    r = Journey.run("dk", rebirths: 1, boss_first: false, max_fights: 1500)

    assert r.done and r.rebirths == 1
    assert Enum.any?(r.events, fn {_, _, _, t} -> t =~ "Chuyển sinh lần 1" end)
    assert Map.has_key?(r.cycles, 1)
    assert [{"Trước chuyển sinh 1", _, %{level: 50}}, {"Kết thúc", _, _}] = r.snapshots
  end
end

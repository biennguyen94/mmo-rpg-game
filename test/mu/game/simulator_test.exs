defmodule Mu.Game.SimulatorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mu.Game.Simulator

  test "lặp lại theo seed; số Spider tới cấp 2/5/10 khớp bảng EXP (không penalty ở Phase 1)" do
    a = Simulator.once(3, %{})
    assert a == Simulator.once(3, %{})
    assert a.c.level == 10
    assert {a.at[2].kills, a.at[5].kills, a.at[10].kills} == {10, 171, 1111}
    assert a.potions > 0
  end

  test "Q14: mặc đủ đồ t0 thì Spider gần như vô hại (sát thương nhận/con < 1)" do
    gear = Enum.filter(Simulator.item_templates(), &(&1["slot"] != nil))
    assert length(gear) == 8
    bare = Simulator.run(5, %{})
    full = Simulator.run(5, %{equipment: gear})
    assert bare.damage_taken_per_kill > 5
    assert full.damage_taken_per_kill < 1
    assert full.milestones[10].minutes < bare.milestones[10].minutes
  end

  test "mix mu.simulate in báo cáo" do
    out = capture_io(fn -> Mix.Tasks.Mu.Simulate.run(["--runs", "2", "--strategy", "str"]) end)
    assert out =~ "cấp 10:"
    assert out =~ "cộng điểm: str"
  end
end

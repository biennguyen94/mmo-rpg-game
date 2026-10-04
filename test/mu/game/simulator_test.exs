defmodule Mu.Game.SimulatorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mu.Game.Simulator

  test "lặp lại theo seed; số Spider tới cấp 2/5/10 khớp bảng EXP (không penalty ở Phase 1)" do
    a = Simulator.once(3, %{max_kills: 1111})
    assert a == Simulator.once(3, %{max_kills: 1111})
    assert a.c.level == 10
    assert {a.at[2].kills, a.at[5].kills, a.at[10].kills} == {10, 171, 1111}
    assert a.potions > 0
  end

  test "Q14: mặc đủ đồ t0 thì Spider gần như vô hại (sát thương nhận/con < 1)" do
    gear = Simulator.gear("DK", "full")
    assert length(gear) == 8
    bare = Simulator.run(5, %{max_kills: 1111})
    full = Simulator.run(5, %{equipment: gear, max_kills: 1111})
    assert bare.damage_taken_per_kill > 5
    assert full.damage_taken_per_kill < 1
    assert full.milestones[10].minutes < bare.milestones[10].minutes
  end

  test "P2-M2: DW/ELF với đồ khởi đầu; cung đánh xa nhận ít sát thương hơn; full ELF bỏ khiên" do
    dw_bare = Simulator.run(3, %{class: "DW", strategy: "ene", max_kills: 200})

    dw =
      Simulator.run(3, %{
        class: "DW",
        strategy: "ene",
        max_kills: 200,
        equipment: Simulator.gear("DW", "starter")
      })

    elf =
      Simulator.run(3, %{
        class: "ELF",
        strategy: "agi",
        max_kills: 200,
        equipment: Simulator.gear("ELF", "starter")
      })

    assert dw.milestones[5].minutes < dw_bare.milestones[5].minutes
    assert elf.damage_taken_per_kill < dw.damage_taken_per_kill

    elf_full = Enum.map(Simulator.gear("ELF", "full"), & &1["slot"])
    assert "WEAPON" in elf_full and "SHIELD" not in elf_full

    assert Enum.find(Simulator.gear("ELF", "full"), &(&1["slot"] == "WEAPON"))["templateId"] ==
             "bow_t0"
  end

  test "P2-M4: quái auto theo cấp, đồ t0 → t1, DW dùng skill + mana; lặp lại theo seed" do
    opts = %{
      class: "DW",
      strategy: "ene",
      monster: "auto",
      gear_progress: true,
      use_skills: true,
      max_kills: 320
    }

    a = Simulator.once(5, opts)
    assert a == Simulator.once(5, opts)
    assert a.c.level >= 10
    assert a.mp >= 0
    # có skill thì nhanh hơn đánh thường
    b = Simulator.once(5, %{opts | use_skills: false})
    assert a.at[10].ms < b.at[10].ms

    assert Enum.map(Simulator.gear("DK", "t1"), & &1["templateId"])
           |> Enum.count(&String.ends_with?(&1, "_t1")) == 7
  end

  test "mix mu.simulate in báo cáo" do
    out =
      capture_io(fn ->
        Mix.Tasks.Mu.Simulate.run([
          "--runs",
          "1",
          "--strategy",
          "str",
          "--class",
          "DW",
          "--gear",
          "starter"
        ])
      end)

    assert out =~ "cấp 10:"
    assert out =~ "cộng điểm: str"
    assert out =~ "class DW"
  end
end

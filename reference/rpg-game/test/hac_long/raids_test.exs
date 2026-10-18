defmodule HacLong.RaidsTest do
  @moduledoc "B-20: Rồng Đỏ / Phù Thủy Trắng xâm lăng — lịch, thả quái, hạ hết thì kết thúc sớm, hết giờ dọn quái, thưởng."
  use HacLong.DataCase, async: false

  alias HacLong.Raids
  alias HacLong.Game.{Data, Engine, Rng}
  alias HacLong.World.MapServer

  @map "forest_1"

  setup do
    MapServer.clear_monsters(@map)

    on_exit(fn ->
      Raids.stop_now()
      Rng.clear()
    end)

    :ok
  end

  defp raiders(key), do: Enum.filter(MapServer.snapshot(@map).monsters, &(&1.raid == key))

  defp kill(m, uid) do
    {:engage, _} = MapServer.step(@map, uid, {m.x, m.y}, true)
    :ok = MapServer.defeat(@map, uid, m.id)
  end

  defp wait(pred, n \\ 50) do
    st = Raids.status()
    if pred.(st) or n == 0, do: st, else: Process.sleep(10) && wait(pred, n - 1)
  end

  # giờ Việt Nam hh:mm → DateTime UTC
  defp vn(h, m), do: DateTime.new!(~D[2026-10-10], Time.new!(h, m, 0)) |> DateTime.add(-7 * 3600)

  test "lịch: mốc every_hours giờ lệch offset_minutes phút (giờ Việt Nam)" do
    r = Raids.rule("red_dragon")
    h = div(r.offset_minutes, 60)
    m = rem(r.offset_minutes, 60)
    assert Raids.next_start("red_dragon", vn(h, m - 1)) == vn(h, m)
    assert Raids.next_start("red_dragon", vn(h, m)) == vn(h + r.every_hours, m)

    w = Raids.rule("white_wizard")

    assert Raids.next_start("white_wizard", vn(0, 0)) ==
             vn(div(w.offset_minutes, 60), rem(w.offset_minutes, 60))
  end

  test "Phù Thủy Trắng: đầu đàn + lính; hạ hết thì kết thúc sớm, không hồi sinh" do
    r = Raids.rule("white_wizard")
    {:ok, st} = Raids.start_now("white_wizard", [@map])
    assert st.active and st.maps == %{@map => r.leader.count + r.minion.count}

    all = raiders("white_wizard")
    assert Enum.count(all, & &1.boss) == r.leader.count
    assert Enum.find(all, & &1.boss).name == r.leader.name
    assert Enum.find(all, & &1.boss).kind == r.leader.kind

    Enum.each(all, &kill(&1, 1))
    st = wait(&(not &1["white_wizard"].active))
    refute st["white_wizard"].active
    Process.sleep(50)
    assert raiders("white_wizard") == []
  end

  test "hết giờ: con chưa ai đánh biến mất" do
    {:ok, _} = Raids.start_now("red_dragon", [@map])
    assert [_ | _] = raiders("red_dragon")
    send(Raids, {:tick, "red_dragon"})
    refute wait(&(not &1["red_dragon"].active))["red_dragon"].active
    assert raiders("red_dragon") == []
  end

  test "chỉ số theo vùng, thưởng × reward_mult, đầu đàn rơi thêm đồ" do
    r = Raids.rule("red_dragon")
    spec = Raids.spec("red_dragon", "red_dragon", 2)
    assert spec.level == Data.zone(2).boss.level + r.leader.level_bonus

    assert spec.name == r.leader.name and spec.reward_mult == r.reward_mult and
             spec.jewel_chance == 1.0

    m = Engine.make_monster(spec, true)
    assert m.raid == "red_dragon" and m.jewel_chance == 1.0

    w = Raids.spec("white_wizard", "orc_soldier", 0)

    assert w.level ==
             Enum.max(Enum.map(Data.zone(0).monsters, & &1.level)) +
               Raids.rule("white_wizard").minion.level_bonus

    assert Raids.drops("red_dragon") |> Enum.map(&elem(&1, 0)) |> Enum.all?(&Data.item/1)
  end
end

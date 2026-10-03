defmodule Mu.WorldEventsTest do
  @moduledoc """
  P6-M5: lịch giờ UTC (thuần) và `Mu.WorldEvents` với đồng hồ giả trên MapServer thật của app:
  báo trước 5 phút, bắt đầu (sinh quái vàng ở Lorencia + Noria / boss ở Lorencia, SYSTEM,
  `world_event`), hết giờ thì thu quái; bật / tắt tay; boss bị hạ thì kết thúc sớm.
  """
  use MuWeb.ChannelCase

  alias Mu.Game.{Config, EventSchedule}
  alias Mu.World.MapServer

  defp at(h, m), do: DateTime.to_unix(DateTime.new!(~D[2026-10-03], Time.new!(h, m, 0)))

  defp events(map, tag),
    do: for({_, m} <- MapServer.debug_state(map).monsters, m.event == tag, do: m)

  setup do
    for m <- ~w(lorencia noria), do: Phoenix.PubSub.subscribe(Mu.PubSub, MapServer.topic(m))

    on_exit(fn ->
      for k <- Mu.WorldEvents.kinds(), do: Mu.WorldEvents.stop(k)
    end)

    :ok
  end

  test "lịch: Golden Invasion mỗi 3 giờ (0, 3, 6 …) 15 phút; boss giờ lẻ 20 phút; báo trước 5 phút" do
    g = Config.get(["events", "goldenInvasion"])
    b = Config.get(["events", "worldBoss"])
    assert {:running, s, e} = EventSchedule.phase(at(3, 5), g)
    assert {s, e} == {at(3, 0), at(3, 15)}
    assert {:idle, _} = EventSchedule.phase(at(3, 15), g)
    assert {:announce, s} = EventSchedule.phase(at(5, 56), g)
    assert s == at(6, 0)
    assert {:idle, _} = EventSchedule.phase(at(5, 54), g)
    # qua ngày: 23:58 → lần kế 0:00 hôm sau
    assert {:announce, next} = EventSchedule.phase(at(23, 58), g)
    assert next == at(23, 58) + 120

    assert {:running, s, _} = EventSchedule.phase(at(1, 19), b)
    assert s == at(1, 0)
    assert {:idle, _} = EventSchedule.phase(at(2, 10), b)
    assert {:announce, _} = EventSchedule.phase(at(2, 56), b)
  end

  test "đồng hồ giả: báo trước → bắt đầu (8 + 8 quái vàng, boss) → hết giờ thu quái" do
    :ok = Mu.WorldEvents.check(at(2, 56))
    assert_receive {:map_event, "world_event", %{kind: "golden_invasion", state: "soon"}}
    assert_receive {:map_event, "chat", %{channel: "SYSTEM", text: "Golden Invasion sẽ" <> _}}

    :ok = Mu.WorldEvents.check(at(3, 0))
    assert length(events("lorencia", "golden_invasion")) == 8
    assert length(events("noria", "golden_invasion")) == 8
    assert [%{template_id: "bull_fighter_lord"}] = events("lorencia", "world_boss")
    assert_receive {:map_event, "world_event", %{kind: "world_boss", state: "start"}}

    assert Enum.map(Mu.WorldEvents.active(), & &1.kind) |> Enum.sort() ==
             ~w(golden_invasion world_boss)

    # cùng cửa sổ: không sinh thêm
    :ok = Mu.WorldEvents.check(at(3, 1))
    assert length(events("lorencia", "golden_invasion")) == 8

    :ok = Mu.WorldEvents.check(at(3, 15))

    assert events("lorencia", "golden_invasion") == [] and
             events("noria", "golden_invasion") == []

    assert [_] = events("lorencia", "world_boss")
    :ok = Mu.WorldEvents.check(at(3, 20))
    assert events("lorencia", "world_boss") == []
    assert_receive {:map_event, "chat", %{text: "Bull Fighter Lord đã biến mất."}}
    assert Mu.WorldEvents.active() == []
  end

  test "bật / tắt tay; boss bị hạ → kết thúc sớm, SYSTEM tên người hạ" do
    :ok = Mu.WorldEvents.start("world_boss")
    assert {:error, :running} = Mu.WorldEvents.start("world_boss")
    assert {:error, :unknown} = Mu.WorldEvents.start("blood_castle")
    assert [_] = events("lorencia", "world_boss")

    Mu.WorldEvents.monster_killed("world_boss", %{
      map: "lorencia",
      monster: "bull_fighter_lord",
      name: "Bull Fighter Lord",
      top: "Anh"
    })

    assert_receive {:map_event, "chat", %{text: "Anh đã hạ Bull Fighter Lord!"}}
    assert_receive {:map_event, "world_event", %{kind: "world_boss", state: "end"}}
    assert events("lorencia", "world_boss") == []

    :ok = Mu.WorldEvents.start("golden_invasion")
    :ok = Mu.WorldEvents.stop("golden_invasion")
    assert {:error, :not_running} = Mu.WorldEvents.stop("golden_invasion")
    assert events("noria", "golden_invasion") == []
  end
end

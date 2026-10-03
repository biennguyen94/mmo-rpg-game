defmodule MuWeb.AoiTest do
  @moduledoc "P3-M1: lưới AOI thuần (ô 16, nhìn 3×3 ô), spawn / despawn khi vào / ra tầm nhìn."
  use ExUnit.Case, async: true

  alias MuWeb.Aoi

  defp ent(id, x, y, extra \\ %{}),
    do: Map.merge(%{id: id, kind: "monster", x: x, y: y, hp: 10, state: "idle"}, extra)

  defp snap(entities, removed \\ []), do: %{t: 1, entities: entities, removed: removed}

  defp ids(pushes, ev), do: for({^ev, p} <- pushes, do: p.id) |> Enum.sort()

  setup do
    # mình ở (20, 20) → ô (1, 1): thấy ô x 0..2, y 0..2 → toạ độ 0..47
    aoi =
      Aoi.new("p_me", [
        ent("p_me", 20, 20, %{kind: "player"}),
        ent("near", 47, 0),
        ent("far", 48, 20),
        ent("npc_x", 5, 5, %{kind: "npc"})
      ])

    %{aoi: aoi}
  end

  test "ô và tầm nhìn theo config (aoiCellSize 16, aoiViewCells 1)" do
    assert {Mu.Game.Config.get(["server", "aoiCellSize"]),
            Mu.Game.Config.get(["server", "aoiViewCells"])} == {16, 1}

    assert Aoi.cell(15, 16, 16) == {0, 1}
    assert Aoi.near?({1, 1}, {2, 0}, 1)
    refute Aoi.near?({1, 1}, {3, 1}, 1)
  end

  test "vào map: chỉ spawn entity trong 3×3 ô (kể cả NPC, chính mình)", %{aoi: aoi} do
    assert ids(Aoi.spawns(aoi), "spawn") == ["near", "npc_x", "p_me"]
  end

  test "entity đi ra / vào tầm nhìn qua snapshot → despawn / spawn (trạng thái mới)", %{aoi: aoi} do
    {aoi, out} =
      Aoi.event(aoi, "snapshot", snap([%{id: "near", x: 48, y: 0, hp: 9, state: "walk"}]))

    assert out == [{"despawn", %{id: "near"}}]

    {aoi, out} =
      Aoi.event(aoi, "snapshot", snap([%{id: "far", x: 47, y: 20, hp: 7, state: "walk"}]))

    assert [{"spawn", %{id: "far", x: 47, hp: 7, state: "walk", kind: "monster"}}] = out

    # entity đã thấy di chuyển trong tầm: chỉ snapshot, đã lọc
    {_aoi, out} =
      Aoi.event(
        aoi,
        "snapshot",
        snap([
          %{id: "far", x: 46, y: 20, hp: 7, state: "walk"},
          %{id: "near", x: 49, y: 0, hp: 9, state: "walk"}
        ])
      )

    assert [{"snapshot", %{entities: [%{id: "far", x: 46}], removed: []}}] = out
  end

  test "mình đổi ô → xét lại mọi entity; snapshot rỗng sau lọc thì bỏ", %{aoi: aoi} do
    # mình (20,20) → (40,20): ô (2,1), thấy x 16..63; near (47,0) vẫn thấy, npc (5,5) ra
    {aoi, out} =
      Aoi.event(aoi, "snapshot", snap([%{id: "p_me", x: 40, y: 20, hp: 1, state: "walk"}]))

    assert ids(out, "spawn") == ["far"]
    assert ids(out, "despawn") == ["npc_x"]
    assert [%{entities: [%{id: "p_me"}]}] = for({"snapshot", p} <- out, do: p)

    {_aoi, out} =
      Aoi.event(aoi, "snapshot", snap([%{id: "x_unknown", x: 1, y: 1, hp: 1, state: "idle"}]))

    assert out == []
  end

  test "spawn / despawn / removed / combat chỉ cho entity trong tầm nhìn", %{aoi: aoi} do
    {aoi, out} = Aoi.event(aoi, "spawn", ent("m2", 100, 100))
    assert out == []
    {aoi, out} = Aoi.event(aoi, "spawn", ent("m3", 30, 30))
    assert [{"spawn", %{id: "m3"}}] = out

    assert {_, []} = Aoi.event(aoi, "despawn", %{id: "far"})
    assert {_, [{"despawn", %{id: "near"}}]} = Aoi.event(aoi, "despawn", %{id: "near"})

    {_aoi, out} = Aoi.event(aoi, "snapshot", snap([], ["far", "near"]))
    assert [{"snapshot", %{removed: ["near"]}}] = out

    hit = fn a, t -> %{rid: nil, attacker: a, target: t, dmg: 1, crit: false, hp: 1} end
    assert {_, [_]} = Aoi.event(aoi, "combat", hit.("far", "p_me"))
    assert {_, [_]} = Aoi.event(aoi, "combat", hit.("far", "near"))
    assert {_, []} = Aoi.event(aoi, "combat", hit.("far", "m2"))
    # chat và sự kiện khác đi thẳng
    assert {_, [{"chat", %{}}]} = Aoi.event(aoi, "chat", %{})
  end

  test "mình spawn lại chỗ khác (hồi sinh) → tính lại tầm nhìn", %{aoi: aoi} do
    {aoi, _} = Aoi.event(aoi, "despawn", %{id: "p_me"})
    {_aoi, out} = Aoi.event(aoi, "spawn", ent("p_me", 60, 20, %{kind: "player"}))
    assert [{"spawn", %{id: "p_me"}} | _] = out
    assert ids(out, "spawn") == ["far", "p_me"]
    assert ids(out, "despawn") == ["npc_x"]
  end
end

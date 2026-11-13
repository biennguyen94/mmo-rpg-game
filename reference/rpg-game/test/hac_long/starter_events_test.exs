defmodule HacLong.StarterEventsTest do
  @moduledoc """
  DECISIONS "Review sự kiện theo chuyển sinh": Golden Invasion / xâm lăng thêm bản đồ vùng chuyển sinh (quái mạnh như
  vùng đó); ở bản đồ đầu vùng trùm vàng / đầu đàn chỉ rơi ngọc cho người dưới `jewel_max_rebirths` lần chuyển sinh.
  """
  use HacLong.DataCase, async: false

  alias HacLong.{Invasion, Raids}
  alias HacLong.Game.{Commands, Data}
  alias HacLong.World
  alias HacLong.World.{Maps, MapServer}

  @st Data.rules().starter_events
  @realm "realm_03"

  setup do
    for id <- ["forest_1", @realm], do: MapServer.clear_monsters(id)
    uid = System.unique_integer([:positive])
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Thử Ngọc", "cls" => "dk"})

    on_exit(fn ->
      Raids.stop_now()
      Invasion.stop_now()
      for id <- ["forest_1", @realm], do: MapServer.leave(id, uid)
    end)

    %{uid: uid, p: p}
  end

  test "xâm lăng ở vùng chuyển sinh: chỉ số từ quái mạnh nhất của bản đồ" do
    r = Raids.rule("red_dragon")
    map = Maps.get(@realm)

    base =
      map.spawns
      |> Enum.map(&Data.side_monster(&1.monster))
      |> Enum.max_by(&(&1[:stat_level] || &1.level))

    spec = Raids.spec("red_dragon", "red_dragon", map)
    assert spec.stat_level == (base[:stat_level] || base.level) + r.leader.level_bonus
    assert spec.level == base.level + r.leader.level_bonus
    # bản đồ đầu vùng vẫn theo vùng như cũ
    assert Raids.spec("red_dragon", "red_dragon", Maps.get("forest_1")) ==
             Raids.spec("red_dragon", "red_dragon", 0)

    {:ok, st} = Raids.start_now("red_dragon", [@realm])
    assert st.maps[@realm] == r.leader.count
  end

  test "Golden Invasion ở vùng chuyển sinh: quái vàng là quái của bản đồ; hạ hết là xong (không có trùm vàng)" do
    st = Invasion.start_now(%{@realm => 2})
    assert st.maps[@realm] == "run"
    kinds = Enum.map(Maps.get(@realm).spawns, & &1.monster)
    golds = Enum.filter(MapServer.snapshot(@realm).monsters, & &1[:gold])
    assert length(golds) == 2 and Enum.all?(golds, &(&1.kind in kinds))

    Invasion.cleared(@realm, false)
    Process.sleep(50)
    refute Invasion.status().active
  end

  defp leader_fight(p, uid) do
    {:ok, _} = Raids.start_now("red_dragon", ["forest_1"])

    m =
      MapServer.snapshot("forest_1").monsters |> Enum.find(&(&1.raid == "red_dragon" and &1.boss))

    map = Maps.get("forest_1")

    {{x, y}, dir} =
      Enum.find(
        [
          {{m.x, m.y + 1}, "up"},
          {{m.x, m.y - 1}, "down"},
          {{m.x + 1, m.y}, "left"},
          {{m.x - 1, m.y}, "right"}
        ],
        fn {{x, y}, _} ->
          Maps.walkable?(map, x, y) and Maps.portal_at(map, x, y) == nil
        end
      )

    p = %{p | level: 60, pos: %{map: "forest_1", x: x, y: y}}
    World.enter(p, uid)
    {%{ok: true}, fighting} = World.move(p, uid, dir, true)
    fighting.battle.monster
  end

  test "đầu đàn ở bản đồ đầu vùng: người mới rơi ngọc như cũ", %{uid: uid, p: p} do
    m = leader_fight(Map.put(p, :rebirths, @st.jewel_max_rebirths - 1), uid)
    assert m.jewel_chance == 1.0 and m[:no_drops] != true
  end

  test "đầu đàn ở bản đồ đầu vùng: người chuyển sinh nhiều không rơi ngọc / đồ thêm", %{
    uid: uid,
    p: p
  } do
    m = leader_fight(Map.put(p, :rebirths, @st.jewel_max_rebirths), uid)
    assert m.jewel_chance == 0 and m.no_drops
  end
end

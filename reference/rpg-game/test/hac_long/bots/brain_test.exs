defmodule HacLong.Bots.BrainTest do
  # Phase 16: bộ não người chơi AI (hàm thuần)
  use ExUnit.Case, async: true

  alias HacLong.Bots.Brain
  alias HacLong.Game.{Engine, Rng}
  alias HacLong.World.Maps

  defp player(cls \\ "dk") do
    {:ok, p} = Engine.new_player("Bot", cls)
    p
  end

  test "chưa có nhân vật thì tạo" do
    assert %{"act" => "create", "name" => "Hắc Phong", "cls" => "elf"} =
             Brain.decide(nil, nil, %{name: "Hắc Phong", cls: "elf"})
  end

  test "trong trận: xong thì rời, máu thấp uống bình, có kỹ năng thì dùng" do
    Rng.put_sequence([0.5])
    {_, p} = Engine.start_battle(%{player() | level: 10}, 0, true)
    assert %{"act" => "skill", "skill" => _} = Brain.decide(p, nil)

    low = %{p | hp: 5, inv: %{"potion_s" => 2}}
    assert %{"act" => "potion"} = Brain.decide(low, nil)

    assert %{"act" => "leave"} = Brain.decide(put_in(p.battle.over, true), nil)
  end

  test "còn điểm thì cộng vào chỉ số chính của lớp" do
    assert %{"act" => "alloc", "stat" => "ene", "n" => 7} =
             Brain.decide(%{player("dw") | points: 7}, nil)
  end

  test "máu thấp ngoài trận: có bình thì uống, không thì về Nhà uống giếng" do
    p = player() |> Map.put(:pos, %{map: "forest_1", x: 5, y: 5})
    d = Engine.derived(p)

    assert %{"act" => "use", "id" => "potion_s"} =
             Brain.decide(%{p | hp: 1, inv: %{"potion_s" => 1}}, nil)

    assert %{"act" => "travel", "to" => "home"} = Brain.decide(%{p | hp: 1, inv: %{}}, nil)

    home = Maps.home_spawn()
    at_home = %{p | hp: 1, inv: %{}, pos: home}
    assert %{"act" => "move"} = Brain.decide(at_home, nil)
    assert d.maxHp > 1
  end

  test "chọn bản đồ hợp cấp, mỗi bot (seed) có thể chọn khác nhau" do
    lv1 = player()
    assert Brain.target_map(lv1) in ~w(forest_1 side_01)
    # đã hạ mọi trùm vùng: cấp 30 luyện ở bản đồ quái cấp 28–31
    all = HacLong.Game.Data.zones() |> Enum.map(& &1.boss.id)
    p = %{lv1 | level: 30, bosses: all}
    picks = for s <- 0..2, do: Brain.target_map(p, s)
    for id <- picks, do: assert(HacLong.World.min_level(Maps.get(id)) in 26..30)
    assert length(Enum.uniq(picks)) > 1
  end

  test "tìm đường: cổng đầu tiên trên đường tới bản đồ phụ, bước đi tới quái" do
    p = %{player() | level: 1}
    assert %{to: "forest_1"} = Brain.next_portal(p, "village", "side_01")
    assert %{to: "side_01"} = Brain.next_portal(p, "forest_1", "side_01")

    map = Maps.get("side_01")
    me = Map.put(p, :pos, %{map: "side_01", x: 1, y: 8})
    snap = %{monsters: [%{x: 3, y: 8, kind: "quokka", busy: false, boss: false}]}
    assert %{"act" => "move", "dir" => "right"} = Brain.walk(me, map, [{3, 8}], snap)
  end

  test "đủ cấp thì vào phòng trùm vùng chưa hạ" do
    p = player()
    assert Brain.boss_room(%{p | level: 3}) == nil
    assert Brain.boss_room(%{p | level: 7}) == "forest_boss"
    assert Brain.boss_room(%{p | level: 13, bosses: ["wolf"]}) == "camp_boss"
  end
end

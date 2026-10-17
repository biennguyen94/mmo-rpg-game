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

  test "đồ sát: chưa tới lượt thì chờ, tới lượt thì đánh / uống bình như thường" do
    Rng.put_sequence([0.5])
    {_, p} = Engine.start_battle(%{player() | level: 10}, 0, true)

    live = fn p, mine ->
      %{p | battle: Map.merge(p.battle, %{live: true, encounter: %{mine: mine}})}
    end

    assert Brain.decide(live.(p, false), nil) == nil
    assert %{"act" => "skill"} = Brain.decide(live.(p, true), nil)

    assert %{"act" => "potion"} =
             Brain.decide(live.(%{p | hp: 5, inv: %{"potion_s" => 2}}, true), nil)
  end

  test "còn điểm thì cộng vào chỉ số chính của lớp" do
    assert %{"act" => "alloc", "stat" => "ene", "n" => 7} =
             Brain.decide(%{player("dw") | points: 7}, nil)
  end

  test "máu thấp ngoài trận: có bình thì uống; hết bình, không vàng thì về Nhà uống giếng" do
    p = %{player() | level: 5, gold: 0} |> Map.put(:pos, %{map: "forest_1", x: 5, y: 5})
    d = Engine.derived(p)

    assert %{"act" => "use", "id" => "potion_s"} =
             Brain.decide(%{p | hp: 1, inv: %{"potion_s" => 1}}, nil)

    assert %{"act" => "travel", "to" => "home"} = Brain.decide(%{p | hp: 1, inv: %{}}, nil)

    home = Maps.home_spawn()
    at_home = %{p | hp: 1, inv: %{}, pos: home}
    assert %{"act" => "move"} = Brain.decide(at_home, nil)
    assert d.maxHp > 1
  end

  test "Phase 5: sắp hết bình mà đủ vàng thì về Làng mua ở Bà Lang" do
    p =
      %{player() | level: 5, gold: 5000, inv: %{}}
      |> Map.put(:pos, %{map: "forest_1", x: 5, y: 5})

    assert [{"potion_" <> _ = hp, 10}, {"mana_" <> _, 6}] = Brain.restock(p)
    assert %{"act" => "travel", "to" => "village"} = Brain.decide(p, nil)

    # ở Làng: đi tới Bà Lang, đứng cạnh thì mua
    {hx, hy} = Enum.find(Maps.get("village").npcs, &(&1.role == "herbalist")).at
    assert %{"act" => "move"} = Brain.decide(%{p | pos: %{map: "village", x: 12, y: 5}}, nil)

    assert %{"act" => "buy", "id" => ^hp, "n" => 10} =
             Brain.decide(%{p | pos: %{map: "village", x: hx, y: hy + 1}}, nil)

    # đủ bình thì thôi; ít vàng quá không mua nổi mức tối thiểu thì cũng thôi
    assert Brain.restock(%{p | inv: %{"potion_s" => 3, "mana_s" => 2}}) == []
    assert Brain.restock(%{p | gold: 10}) == []
  end

  test "Phase 5: máu thấp, hết bình, không mua nổi bình mà đủ tiền trọ thì nghỉ ở Quán Trọ" do
    p = %{player() | level: 5, inv: %{}} |> Map.put(:pos, %{map: "village", x: 12, y: 5})
    p = %{p | hp: 1, gold: Engine.rest_cost(%{p | hp: 1}) * 2}
    assert Brain.restock(p) == []
    {ix, iy} = Enum.find(Maps.get("village").npcs, &(&1.role == "inn")).at
    assert %{"act" => "move"} = Brain.decide(p, nil)
    assert %{"act" => "rest"} = Brain.decide(%{p | pos: %{map: "village", x: ix, y: iy + 1}}, nil)
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

  test "vừa gục thì nghỉ ngẫu nhiên trong RULES.bots.rest_after_death_s rồi mới đi luyện" do
    [lo, hi] = HacLong.Game.Data.rules().bots.rest_after_death_s
    p = %{player() | deaths: 3}

    # lần đầu bot nhìn (chưa biết số lần chết) / số lần chết không đổi: không nghỉ
    assert Brain.rest_until(0, nil, p, 1_000) == 0
    assert Brain.rest_until(0, 3, p, 1_000) == 0

    # chết thêm một lần: nghỉ từ lo tới hi giây
    Rng.put_sequence([0.0])
    assert Brain.rest_until(0, 2, p, 1_000) == 1_000 + lo * 1000
    Rng.put_sequence([1.0])
    assert Brain.rest_until(0, 2, p, 1_000) == 1_000 + hi * 1000
    Rng.clear()

    assert Brain.resting?(p, 5_000, 4_999)
    refute Brain.resting?(p, 5_000, 5_000)
    # trận gục ngã còn mở (bảng kết quả) thì vẫn rời trận như thường
    refute Brain.resting?(Map.put(p, :battle, %{over: true}), 5_000, 1_000)
  end
end

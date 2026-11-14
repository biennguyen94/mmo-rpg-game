defmodule HacLong.World.SecretTest do
  # DECISIONS "Động Bí Ẩn": đêm mở, trùm đêm, động sụp lúc sáng, đếm đêm, Bia
  use HacLong.DataCase, async: false

  alias HacLong.Game.{Achievements, Data, Engine}
  alias HacLong.World.{MapServer, Secret, SecretRecords, SecretWatch}

  setup do
    on_exit(fn -> Application.delete_env(:hac_long, :time_of_day) end)
    :ok
  end

  test "khoảng open_chance số đêm cửa mở, cố định theo đêm" do
    dates = for d <- 0..999, do: Date.add(~D[2026-01-01], d)
    share = Enum.count(dates, &Secret.open_night?/1) / 1000
    assert_in_delta share, Secret.rules().open_chance, 0.06
    assert Secret.open_night?(~D[2026-11-07]) == Secret.open_night?(~D[2026-11-07])
  end

  test "trùm đêm thức giấc trong khung giờ (giờ Việt Nam, qua 0 giờ)" do
    r = Secret.rules()

    for d <- 0..50 do
      at = Secret.boss_at(Date.add(~D[2026-11-01], d))
      h = DateTime.add(at, 7 * 3600).hour
      assert h >= r.boss_from_h or h < r.boss_to_h, "giờ #{h}"
      # thuộc đúng đêm đó
      assert Secret.night_of(at) == Date.add(~D[2026-11-01], d)
    end
  end

  test "báo động sụp trong warn_min phút trước 5 giờ (giờ Việt Nam)" do
    assert Secret.collapse_soon?(~U[2026-11-07 21:55:00Z])
    refute Secret.collapse_soon?(~U[2026-11-07 21:40:00Z])
    refute Secret.collapse_soon?(~U[2026-11-07 22:01:00Z])
  end

  test "đếm đêm vào động (mỗi đêm một lần) và thành tựu Kẻ Đi Đêm" do
    {:ok, p} = Engine.new_player("Dem", "dk")
    p = Secret.visit(p, ~U[2026-11-07 14:00:00Z])
    p = Secret.visit(p, ~U[2026-11-07 18:00:00Z])
    assert Secret.load(p.secret).nights == 1
    p = Secret.visit(p, ~U[2026-11-08 14:00:00Z])
    assert Secret.load(p.secret).nights == 2
    assert Achievements.value(p, :secret_nights) == 2
    assert Achievements.get("night_walker").goal == Secret.rules().night_walker
    assert Achievements.get("secret_boss")
  end

  test "đêm mở, tới giờ: SecretWatch thả Thạch Long Ẩn vào động (một lần), Bia ghi được" do
    Application.put_env(:hac_long, :time_of_day, "night")
    night = Enum.find(for(d <- 0..60, do: Date.add(~D[2026-11-01], d)), &Secret.open_night?/1)
    now = DateTime.add(Secret.boss_at(night), 60)
    assert Secret.boss_due?(now)

    map = Secret.map_id()
    MapServer.clear_monsters(map)
    s = SecretWatch.tick(%{boss_night: nil, warned: nil}, now)
    assert s.boss_night == night
    boss = Enum.find(MapServer.snapshot(map).monsters, & &1.boss)
    assert boss.kind == Secret.rules().boss and boss.name == Data.side_monster(boss.kind).name
    # nhịp sau không thả thêm
    SecretWatch.tick(s, DateTime.add(now, 30))
    assert Enum.count(MapServer.snapshot(map).monsters, & &1.boss) == 1
    MapServer.clear_monsters(map)

    SecretRecords.record(-5, "Thử", "boss", night)
    assert [%{name: "Thử", kind: "boss"} | _] = SecretRecords.recent(5)
  end

  test "bước vào Thạch Long Ẩn: trận dựng như trùm (máu / công / thủ trùm) và mạnh theo chuyển sinh" do
    map = Secret.map_id()
    kind = Secret.rules().boss
    spec = Data.side_monster(kind)
    MapServer.clear_monsters(map)

    {x, y} =
      Enum.find(for(y <- 2..20, x <- 2..30, do: {x, y}), fn {x, y} ->
        m = HacLong.World.Maps.get(map)

        HacLong.World.Maps.walkable?(m, x, y) and HacLong.World.Maps.walkable?(m, x - 1, y) and
          HacLong.World.Maps.portal_at(m, x, y) == nil
      end)

    MapServer.put_monster(map, kind, {x, y}, false, false, %{
      name: spec.name,
      level: spec.level,
      night_boss: true
    })

    {:ok, p} = Engine.new_player("Dem", "dk")
    p = Map.merge(p, %{level: 50, rebirths: 10, pos: %{map: map, x: x - 1, y: y}})
    {_r, p} = HacLong.World.move(p, -1, "right", true)
    MapServer.clear_monsters(map)

    want = Engine.make_monster(spec, true)
    m = p.battle.monster
    assert m.boss
    sc = Data.rules().event_scale
    assert m.maxHp == round(want.maxHp * (1 + sc.hp_per_rebirth * 10))
    assert m.atk == round(want.atk * (1 + sc.atk_per_rebirth * 10))
  end

  test "quái trong động (ẩn khỏi Thư viện) mang tên, cấp để client vẽ đúng" do
    map = Secret.map_id()
    kind = hd(HacLong.World.Maps.get(map).spawns).monster
    spec = Data.side_monster(kind)
    MapServer.clear_monsters(map)
    q = MapServer.put_monster(map, kind, {3, 3})
    assert q.name == spec.name and q.level == spec.level
    MapServer.clear_monsters(map)
  end

  test "quản trị mở / đóng có hiệu lực tới 5 giờ sáng kế tiếp" do
    on_exit(fn -> :persistent_term.put({Secret, :override}, {"auto", 0}) end)
    t = ~U[2026-11-07 10:00:00Z]
    # 17 giờ giờ VN → 5 giờ sáng hôm sau = 22 giờ UTC
    assert Secret.next_dawn(t) == ~U[2026-11-07 22:00:00Z]
    assert Secret.next_dawn(~U[2026-11-07 20:00:00Z]) == ~U[2026-11-07 22:00:00Z]

    Secret.set_override("open", t)
    assert Secret.override(t) == "open"
    assert Secret.open?(t)
    refute Secret.override(~U[2026-11-07 22:00:01Z])

    Secret.set_override("close", t)
    refute Secret.open?(t)
    Secret.set_override("auto", t)
    assert Secret.override(t) == nil
  end
end

defmodule HacLong.World.VnMapsTest do
  # DECISIONS "Bản đồ đẹp hơn": bản đồ chất Việt (B1), bản đồ lớn (B3), bản đồ bí mật (B2)
  use HacLong.DataCase, async: false

  alias HacLong.{Library, World}
  alias HacLong.Game.{Data, Engine}
  alias HacLong.World.{Maps, Secret}

  @ids ~w(vn_lang_chai vn_cho_noi vn_rung_tre vn_ruong_bac_thang vn_dong_bang vn_den_co vn_dong_bi_an)

  test "7 bản đồ có đủ, cổng hai chiều, ô xuất hiện đi được, quái có trong SIDE_MONSTERS" do
    for id <- @ids do
      m = Maps.get(id)
      assert m, id

      for p <- m.portals do
        t = Maps.get(p.to)
        assert t, "#{id} → #{p.to}"
        assert Enum.any?(t.portals, &(&1.to == id)), "#{p.to} không có cổng về #{id}"
        {x, y} = p.spawn
        assert Maps.walkable?(t, x, y), "#{id} → #{p.to}: ô xuất hiện (#{x}, #{y}) không đi được"
      end

      for s <- m.spawns, do: assert(Data.side_monster(s.monster), s.monster)
    end

    assert Maps.get("vn_ruong_bac_thang").width == 50 and
             Maps.get("vn_ruong_bac_thang").height == 35

    assert Maps.get("vn_dong_bang").width == 50
  end

  test "Động Bí Ẩn: chỉ vào được ban đêm, không dịch chuyển tới, không có trong Thư viện" do
    secret = Maps.get("vn_dong_bi_an")
    assert secret.secret == "night"
    refute World.can_travel?(%{level: 60, rebirths: 0}, secret)
    refute Enum.any?(Library.get().maps, &(&1.id == "vn_dong_bi_an"))
    assert Enum.any?(Library.get().maps, &(&1.id == "vn_den_co"))
    refute Enum.any?(Library.build().monsters, &(&1.id == "vn_thach_long"))
    assert Enum.any?(Library.build().monsters, &(&1.id == "vn_ha_ba"))
  end

  test "người đầu tiên mỗi đêm được báo một lần; đêm kéo qua 0 giờ" do
    map = %{id: "vn_test_secret", name: "Động Thử"}
    t = ~U[2026-11-07 14:00:00Z]
    assert Secret.found(map, %{name: "A"}, -1, t) == :announced
    assert Secret.found(map, %{name: "B"}, -2, DateTime.add(t, 6 * 3600)) == :ok
    # 21 giờ hôm sau (giờ VN) là đêm mới
    assert Secret.found(map, %{name: "C"}, -3, DateTime.add(t, 24 * 3600)) == :announced
    assert Secret.night_of(~U[2026-11-07 13:30:00Z]) == Secret.night_of(~U[2026-11-07 21:00:00Z])
  end

  test "quái bản đồ mới có chỉ số theo cấp như quái bản đồ phụ khác" do
    m = Engine.make_monster(Data.side_monster("vn_ha_ba"), false)
    assert m.level == 30 and m.maxHp > 0
  end
end

defmodule HacLong.Game.LongVuongTest do
  # DECISIONS "Long Vương" (+ "Biển Long Vương"): Biển Long Vương, câu được thú hiếm, Mồi Rồng, ba kỹ năng, Bia Long Vương
  use HacLong.DataCase, async: false

  alias HacLong.Game.{Achievements, Crafting, Data, Engine, Fishing, Gear, Pets, Rng}
  alias HacLong.World.Maps
  alias HacLong.{RarePets, World}

  setup do
    on_exit(&Rng.clear/0)
  end

  @lake "long_vuong_lake"
  @dragon Data.rules().fishing.dragon

  # đứng trên cầu tàu (13, 11), cạnh nước biển
  defp angler(level \\ 30) do
    {:ok, p} = Engine.new_player("Cần Thủ", "dk")
    %{p | level: level, gold: 1_000_000} |> Map.put(:pos, %{map: @lake, x: 13, y: 11})
  end

  defp with_pet(p, lv) do
    p
    |> Map.put(:pets, ["long_vuong"])
    |> Map.put(:pet, "long_vuong")
    |> Map.put(:pet_xp, %{"long_vuong" => Pets.xp_for(lv)})
  end

  test "bản đồ: biển phía nam, bãi cát, cầu tàu đi được, câu được từ cầu tàu; cần cấp 30" do
    m = Maps.get(@lake)
    assert m.spawns == [] and m.fish == "lake" and m.min_level == 30
    # cầu tàu, bãi cát đi được; nước thì không
    assert Maps.walkable?(m, 13, 11) and Maps.walkable?(m, 6, 12) and Maps.walkable?(m, 5, 7)
    refute Maps.walkable?(m, 16, 13)
    assert Fishing.near_water?(angler())
    # ngoài khơi là nước sâu (Vực Rồng)
    assert Maps.tile(m, 14, 15) == "="

    # cổng ở Rừng Mê 1 hai chiều; dưới cấp 30 không vào được
    f1 = Maps.get("forest_1")
    gate = Enum.find(f1.portals, &(&1.to == @lake))
    assert Enum.any?(m.portals, &(&1.to == "forest_1"))
    assert World.min_level(m) == 30
    refute World.can_travel?(%{angler(29) | rebirths: 0}, m)
    assert World.can_travel?(angler(30), m)
    assert gate
  end

  test "bảng cá riêng: nhiều Lươn Điện, Cá Chép Vàng 3 %" do
    pool = Map.new(Fishing.pool(@lake), fn {w, id} -> {id, w} end)
    assert pool["fish_gold"] == 3 and pool["fish_eel"] > 0
  end

  # ô nước cạnh chỗ đứng của angler()
  defp spot do
    m = Maps.get(@lake)
    Enum.find([{12, 11}, {14, 11}, {13, 13}], fn {x, y} -> Maps.water?(m, x, y) end)
  end

  test "Long Vương cắn câu chỉ khi thả trúng ô Ngài nổi; giật đúng lúc thì được thú, trễ thì mất" do
    at = spot()
    # lần ngẫu nhiên 1: thời gian chờ; lần 2: cơ hội Long Vương (dưới chance)
    Rng.put_sequence([0.0, @dragon.chance * 0.5])
    {%{ok: true, big: true}, p} = Fishing.cast(angler(), 0, at, at)
    assert {%{ok: false, msg: "Dây câu đứt phựt!" <> _}, _} = Fishing.reel(p, 5_000)

    {%{ok: true, rare_pet: "long_vuong"}, got} = Fishing.reel(%{p | long_khi: 150}, 3_100)
    assert "long_vuong" in got.pets and got.long_khi == 0

    # mồi: cơ hội × bait_mult, chỉ tốn khi thả trúng ô Ngài
    bait = Engine.add_item(angler(), @dragon.bait, 2)
    Rng.put_sequence([0.0, @dragon.chance * 1.5])
    {%{ok: true, big: true}, p} = Fishing.cast(bait, 0, at, at)
    assert p.inv[@dragon.bait] == 1
    Rng.put_sequence([0.0, 0.0, 0.5])
    {r, p} = Fishing.cast(bait, 0, at, nil)
    refute r[:big]
    assert p.inv[@dragon.bait] == 2

    # Long Khí đầy: cơ hội × (1 + max/div); không mồi, không Long Khí thì cùng số đó không đủ
    full = %{angler() | long_khi: @dragon.long_khi_max}
    k = 1 + @dragon.long_khi_max / @dragon.long_khi_div
    Rng.put_sequence([0.0, @dragon.chance * (k - 0.1)])
    assert {%{big: true}, _} = Fishing.cast(full, 0, at, at)
    Rng.put_sequence([0.0, @dragon.chance * 1.5, 0.5])
    {r, _} = Fishing.cast(angler(), 0, at, at)
    refute r[:big]

    # thả lệch ô Ngài, ô ngoài tầm, ở hồ khác: không có Long Vương
    Rng.put_sequence([0.0, 0.0, 0.5])
    {r, _} = Fishing.cast(angler(), 0, at, {0, 0})
    refute r[:big]

    assert {%{ok: false, msg: "Ô đó xa quá" <> _}, _} =
             Fishing.cast(angler(), 0, {14, 6 + 9}, nil)

    Rng.put_sequence([0.0, 0.0, 0.5])
    {r, _} = Fishing.cast(Map.put(angler(), :pos, %{map: "village", x: 10, y: 5}), 0, nil, at)
    refute r[:big]
  end

  test "Long Khí: +1 mỗi con cá câu ở hồ, tối đa long_khi_max; hồ khác không tính" do
    {_, p} = Fishing.land(angler(), "fish_eel")
    assert p.long_khi == 1
    {_, p} = Fishing.land(%{p | long_khi: @dragon.long_khi_max}, "fish_eel")
    assert p.long_khi == @dragon.long_khi_max
    {_, p} = Fishing.land(Map.put(angler(), :pos, %{map: "village", x: 10, y: 5}), "fish_eel")
    assert p.long_khi == 0
  end

  test "Đàn Cá Vàng: thả trúng ô đàn thì dễ ra Cá Chép Vàng, +Long Khí của đàn; lệch ô thì như thường" do
    sc = Data.rules().fishing.school
    at = spot()
    Rng.put_sequence([0.0])
    {%{ok: true, school: true}, p} = Fishing.cast(angler(), 0, at, nil, at)
    Rng.put_sequence([sc.gold_chance * 0.9])
    {%{ok: true, fish: "fish_gold"}, p} = Fishing.reel(p, 3_100)
    assert p.long_khi == sc.long_khi

    Rng.put_sequence([0.0, 0.5])
    {r, p} = Fishing.cast(angler(), 0, at, nil, {0, 0})
    refute r[:school]
    {%{ok: true}, p} = Fishing.reel(p, 3_100)
    assert p.long_khi == 1
  end

  test "việc của Ông Lão: câu đủ cá ở hồ trong ngày thì nhận vàng, kinh nghiệm, Long Khí một lần" do
    el = Data.rules().fishing.elder
    p = HacLong.Game.Daily.ensure(angler(), "2026-10-18")
    assert {%{ok: false, msg: "Câu đủ" <> _}, _} = Fishing.claim_elder(p)

    p = Enum.reduce(1..el.count, p, fn _, p -> Fishing.land(p, "fish_eel") |> elem(1) end)
    {_, p} = Fishing.land(p, "old_boot")
    e = Fishing.elder(p)
    assert e.n == el.count and not e.done and e.reward.gold > 0 and e.reward.xp > 0

    {%{ok: true}, got} = Fishing.claim_elder(p)
    assert got.gold == p.gold + e.reward.gold
    assert got.long_khi == min(p.long_khi + el.long_khi, @dragon.long_khi_max)
    assert {%{ok: false, msg: "Hôm nay lão trả công rồi" <> _}, _} = Fishing.claim_elder(got)

    # ngày mới: đếm lại
    assert Fishing.elder(HacLong.Game.Daily.ensure(got, "2026-10-19")).n == 0
  end

  test "LakeEvent: nổi ở ô câu được, báo mọi người, có người câu được hoặc hết giờ thì lặn" do
    spots = HacLong.LakeEvent.spots()
    assert spot() in spots
    m = Maps.get(@lake)
    assert Enum.all?(spots, fn {x, y} -> Maps.water?(m, x, y) end)

    Phoenix.PubSub.subscribe(HacLong.PubSub, HacLong.LakeEvent.topic())
    st = HacLong.LakeEvent.summon()
    assert %{tile: [x, y], left: left} = st
    assert {x, y} in spots and left > 0 and left <= @dragon.stay * 1000
    assert_receive {:lake, %{tile: [^x, ^y]}}
    assert HacLong.LakeEvent.tile() == {x, y}

    # Đàn Cá Vàng hiện ở ô khác ô Ngài
    %{school: [sx, sy]} = HacLong.LakeEvent.school_summon()
    assert {sx, sy} != {x, y} and {sx, sy} in spots
    assert HacLong.LakeEvent.tiles() == {{x, y}, {sx, sy}}

    HacLong.LakeEvent.dive()
    assert_receive {:lake, %{tile: nil, school: [^sx, ^sy]}}
    assert HacLong.LakeEvent.tile() == nil
  end

  test "đã có Long Vương: con mới vào túi dạng Ấn; đóng ấn / mở ấn giữ cấp; ghép Hắc Long ở Lão Hỗn Nguyên" do
    p = with_pet(angler(), 5)
    {r, p} = Fishing.land_dragon(p)
    assert r.rare_pet == "long_vuong" and p.pets == ["long_vuong"]
    assert [card] = Enum.filter(p.gear, &(&1.base == "seal_long_vuong"))
    assert Gear.resolve(card).name =~ "cấp 1"

    # đã có con cùng loại: không mở được; đóng ấn con đang có (giữ cấp 5) rồi mở con mới
    assert {%{ok: false}, _} = Pets.unseal(p, card.uid)
    {%{ok: true}, p} = Pets.seal(p, "long_vuong")
    assert p.pets == [] and p.pet == nil
    [old] = Enum.filter(p.gear, &(&1.base == "seal_long_vuong" and &1.xp > 0))
    assert Gear.resolve(old).name =~ "cấp 5"
    {%{ok: true}, p} = Pets.unseal(p, old.uid)
    assert Pets.level(p, "long_vuong") == 5

    # ghép Hắc Long: cần Long Vương và Chim Lạc cấp tối đa; xong mất cả hai, có Hắc Long
    assert {%{ok: false, msg: "Chưa ghép được" <> _}, _} = HacLong.Game.DragonEgg.combine(p)
    top = Pets.xp_for(Pets.max_level("long_vuong"))

    full =
      p
      |> Map.put(:pets, ["long_vuong", "chim_lac"])
      |> Map.put(:pet_xp, %{
        "long_vuong" => top,
        "chim_lac" => Pets.xp_for(Pets.max_level("chim_lac"))
      })

    Rng.put_sequence([0.99])
    {r, p} = HacLong.Game.DragonEgg.combine(full)
    assert r.ok and r.rare_pet == "hac_long" and p.pets == ["hac_long"]
  end

  test "không bán ở Người Nuôi Thú; không tính vào thành tựu đủ thú; có danh hiệu Long Vương Chủ" do
    assert {%{ok: false, msg: msg}, _} = Pets.buy(angler(), "long_vuong")
    assert msg =~ "chỉ câu được ở Biển Long Vương"

    p = with_pet(angler(), 1)
    got = Achievements.check(p) |> elem(0) |> Map.get(:achievements, [])
    assert "long_vuong" in got
    assert Achievements.get("long_vuong").title == "Long Vương Chủ"
    assert Achievements.value(p, :pets) == 0
  end

  test "Thần thú: cộng cả ba nhóm (tấn công, chí mạng, thủ, máu, giảm sát thương nhận, kinh nghiệm, vàng), không kỹ năng" do
    # DECISIONS "Thú cưng 3 nhóm, chỉ cộng chỉ số"
    pt = Pets.data("long_vuong")
    assert pt.group == "all" and pt[:skill] == nil
    assert Enum.all?(~w(atk crit def reduce xp gold)a, &Map.has_key?(pt.bonus, &1))
    # máu / MP cộng số mỗi cấp thú (DECISIONS "Thú cưng: máu / MP cộng số")
    assert pt.flat.hp > 0 and pt.flat.mp > 0

    base = Engine.derived(angler())
    d = Engine.derived(with_pet(angler(), 1))
    assert abs(d.atk - base.atk * (1 + pt.bonus.atk)) <= 1
    assert d.maxHp == base.maxHp + pt.flat.hp
    assert d.maxMp == base.maxMp + pt.flat.mp
  end

  test "giảm sát thương nhận (Hộ vệ / Long Vương); không còn hồi sinh" do
    hit = fn p ->
      {_, p} = Engine.start_battle(p, 0, false)

      p =
        p
        |> put_in([:battle, :monster, :hp], 100_000)
        |> put_in([:battle, :monster, :atk], 400)
        |> put_in([:battle, :monster, :crit], 0)

      hp = p.hp

      # trượt đòn của mình (≥ 0,95); quái đánh trúng, không chí mạng
      Rng.put_sequence([0.99])
      {_, p} = Engine.act(p, "attack")
      {hp - p.hp, p}
    end

    {plain, _} = hit.(Map.put(angler(), :pet, nil))
    {guarded, _} = hit.(with_pet(angler(), 1))
    assert guarded < plain

    p = with_pet(angler(), 20)
    {_, p} = Engine.start_battle(p, 0, false)

    p =
      p
      |> put_in([:battle, :monster, :hp], 100_000)
      |> put_in([:battle, :monster, :atk], 100_000)
      |> Map.put(:hp, 1)

    Rng.put_sequence([0.99])
    {_, p} = Engine.act(p, "attack")
    assert p.battle.result == "lose"
  end

  test "Mồi Rồng: Bà Lang pha ra 100 mồi, cần nghề Nấu ăn cấp 3" do
    p =
      angler()
      |> Map.put(:inv, %{"fish_gold" => 1, "herb_rare" => 3})
      |> Map.put(:crafting, %{cook: 60, smith: 0})

    {%{ok: true, msg: "Pha được Mồi Rồng ×100."}, p} = Crafting.brew(p, "brew_dragon_bait")
    assert p.inv["dragon_bait"] == 100 and p.inv["fish_gold"] == nil
  end

  test "Bia Long Vương: đánh số theo thứ tự, ghi lại không thêm dòng" do
    {:ok, a} = HacLong.Accounts.register(%{"username" => "rongmot", "password" => "matkhau1"})
    {:ok, b} = HacLong.Accounts.register(%{"username" => "ronghai", "password" => "matkhau1"})
    assert RarePets.record!(a.id, "Một", "long_vuong") == 1
    assert RarePets.record!(b.id, "Hai", "long_vuong") == 2
    assert RarePets.record!(a.id, "Một", "long_vuong") == 1
    assert [%{n: 1, name: "Một"}, %{n: 2, name: "Hai"}] = RarePets.list("long_vuong")
  end

  describe "thần thú độc nhất (DECISIONS \"Long Vương: thần thú độc nhất\")" do
    test "cấp tối đa 30 (thú khác 20), chỉ số nhân theo cấp 30; còn cho ăn được sau cấp 20" do
      assert Pets.max_level("long_vuong") == 30 and Pets.max_level("sheep") == 20
      p = with_pet(angler(), 30)
      assert Pets.level(p, "long_vuong") == 30

      # Long Vương tăng mỗi cấp riêng (`per_level` 0.08), thú khác `RULES.pets.bonus_per_level` (DECISIONS "Long Vương mạnh hơn")
      per = Pets.data("long_vuong").per_level
      assert per > HacLong.Game.Data.rules().pets.bonus_per_level
      mult = 1 + 29 * per
      assert_in_delta Pets.mult(p), mult, 1.0e-9
      assert_in_delta Pets.bonus(p, :atk), Pets.data("long_vuong").bonus.atk * mult, 1.0e-9
      assert Pets.flat(p, :hp) == 30 * Pets.data("long_vuong").flat.hp
      # thú thường cấp 20 là hết; Long Vương cấp 20 còn lên tiếp
      assert Pets.feed_cost(with_pet(angler(), 20)) != nil
      assert Pets.feed_cost(p) == nil
      {p2, _} = Pets.gain(with_pet(angler(), 30), true)
      assert Pets.level(p2, "long_vuong") == 30
    end

    test "Long Uy kháng một nửa hiệu ứng xấu; Long Ân thêm ngọc; thú khác không có" do
      lv = with_pet(angler(), 1)

      assert Pets.trait(lv, :ward) == 0.5 and Pets.trait(lv, :jewel) == 0.25 and
               Pets.trait(lv, :boss) == 0.1

      other = angler() |> Map.put(:pets, ["daemon"]) |> Map.put(:pet, "daemon")
      assert Pets.trait(other, :ward) == 0 and Pets.trait(angler(), :jewel) == 0
    end

    test "Long Uy trong trận: trúng xác suất thì không bị choáng" do
      p = with_pet(angler(), 1)
      {_, p} = Engine.start_battle(p, 0, false)
      Rng.put_sequence([0.1])
      q = Engine.pvp_receive(p, [%{id: "stun", turns: 1, power: 0}])
      refute Engine.stunned?(q)
      assert Enum.any?(q.battle.log, &(&1.text =~ "Long Uy"))
      Rng.put_sequence([0.9])
      assert Engine.stunned?(Engine.pvp_receive(p, [%{id: "stun", turns: 1, power: 0}]))
      on_exit(&Rng.clear/0)
    end
  end
end

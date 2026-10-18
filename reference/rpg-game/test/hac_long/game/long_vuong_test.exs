defmodule HacLong.Game.LongVuongTest do
  # DECISIONS "Long Vương": Hồ Long Vương, câu được thú hiếm, Mồi Rồng, ba kỹ năng, Bia Long Vương
  use HacLong.DataCase, async: false

  alias HacLong.Game.{Achievements, Crafting, Data, Engine, Fishing, Pets, Rng}
  alias HacLong.World.Maps
  alias HacLong.{RarePets, World}

  setup do
    on_exit(&Rng.clear/0)
  end

  @lake "long_vuong_lake"
  @dragon Data.rules().fishing.dragon

  # đứng trên bến gỗ giữa bờ bắc (14, 6), cạnh nước
  defp angler(level \\ 30) do
    {:ok, p} = Engine.new_player("Cần Thủ", "dk")
    %{p | level: level, gold: 1_000_000} |> Map.put(:pos, %{map: @lake, x: 14, y: 6})
  end

  defp with_pet(p, lv) do
    p
    |> Map.put(:pets, ["long_vuong"])
    |> Map.put(:pet, "long_vuong")
    |> Map.put(:pet_xp, %{"long_vuong" => Pets.xp_for(lv)})
  end

  test "bản đồ: hồ ở giữa, lối đi vòng quanh, bến / cầu gỗ đi được, câu được từ bến; cần cấp 30" do
    m = Maps.get(@lake)
    assert m.spawns == [] and m.fish == "lake" and m.min_level == 30
    assert Maps.walkable?(m, 14, 6) and Maps.walkable?(m, 19, 9) and Maps.walkable?(m, 17, 10)
    refute Maps.walkable?(m, 14, 9)
    assert Fishing.near_water?(angler())
    # bến cuối sát Vực Rồng
    assert Maps.tile(m, 14, 8) == "="

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
    Enum.find([{14, 7}, {13, 6}, {15, 6}, {14, 5}], fn {x, y} -> Maps.water?(m, x, y) end)
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

    HacLong.LakeEvent.dive()
    assert_receive {:lake, %{tile: nil}}
    assert HacLong.LakeEvent.tile() == nil
  end

  test "mỗi nhân vật một con: đã có thì được Cá Chép Vàng" do
    p = with_pet(angler(), 1)
    {r, p} = Fishing.land_dragon(p)
    refute r[:rare_pet]
    assert p.inv["fish_gold"] == 1 and p.pets == ["long_vuong"]
  end

  test "không bán ở Người Nuôi Thú; không tính vào thành tựu đủ thú; có danh hiệu Long Vương Chủ" do
    assert {%{ok: false, msg: msg}, _} = Pets.buy(angler(), "long_vuong")
    assert msg =~ "chỉ câu được ở Hồ Long Vương"

    p = with_pet(angler(), 1)
    got = Achievements.check(p) |> elem(0) |> Map.get(:achievements, [])
    assert "long_vuong" in got
    assert Achievements.get("long_vuong").title == "Long Vương Chủ"
    assert Achievements.value(p, :pets) == 0
  end

  test "chỉ số cao, ba kỹ năng mở ở cấp 5 / 15 / 20" do
    base = Engine.derived(angler())
    d = Engine.derived(with_pet(angler(), 1))
    assert abs(d.atk - base.atk * 1.10) <= 1 and abs(d.maxHp - base.maxHp * 1.08) <= 1

    assert [] == Pets.active_skills(with_pet(angler(), 4))
    assert ~w(tidal scales) == Enum.map(Pets.active_skills(with_pet(angler(), 15)), & &1.id)

    assert ~w(tidal scales rebirth) ==
             Enum.map(Pets.active_skills(with_pet(angler(), 20)), & &1.id)

    assert Pets.skill_at("long_vuong", 20).name == "Long Vương Hồi Sinh"
  end

  test "Thủy Long Ba: cắn gấp đôi, quái choáng; mỗi 3 lượt một lần" do
    p = with_pet(angler(), 5)
    {_, p} = Engine.start_battle(p, 0, false)
    p = p |> put_in([:battle, :monster, :hp], 100_000) |> put_in([:battle, :monster, :dodge], 0)
    Rng.put_sequence([0.0])
    {_, p} = Engine.act(p, "attack")
    assert Enum.any?(p.battle.log, &(&1.text =~ "Thủy Long Ba: cắn thêm"))
    assert Enum.any?(p.battle.log, &(&1.text =~ "bị cột nước đánh choáng"))
    assert Enum.any?(p.battle.log, &(&1.text =~ "bị choáng, không đánh được"))

    # hai lượt sau còn trong thời gian chờ (cắn thường), lượt thứ ba lại dùng được
    at = p.battle.tidal_at
    {_, p} = Engine.act(p, "attack")
    {_, p} = Engine.act(p, "attack")
    assert p.battle.tidal_at == at
    {_, p} = Engine.act(p, "attack")
    assert p.battle.tidal_at == at + 3
  end

  test "Long Lân Hộ Thể giảm sát thương nhận; Long Vương Hồi Sinh cứu một lần mỗi trận" do
    hit = fn p ->
      {_, p} = Engine.start_battle(p, 0, false)

      p =
        p
        |> put_in([:battle, :monster, :hp], 100_000)
        |> put_in([:battle, :monster, :atk], 400)
        |> put_in([:battle, :monster, :crit], 0)

      hp = p.hp

      # lần 1: trượt đòn của mình (≥ 0,95), thú không cắn; quái đánh trúng, không chí mạng
      Rng.put_sequence([0.99])
      {_, p} = Engine.act(p, "attack")
      {hp - p.hp, p}
    end

    {plain, _} = hit.(Map.put(with_pet(angler(), 1), :pet_xp, %{"long_vuong" => 0}))
    {guarded, _} = hit.(with_pet(angler(), 15))
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
    assert p.hp > 0 and p.battle.pet_revived
    assert Enum.any?(p.battle.log, &(&1.text =~ "Long Vương Hồi Sinh!"))
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
end

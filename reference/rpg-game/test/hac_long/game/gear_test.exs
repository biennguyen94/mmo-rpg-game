defmodule HacLong.Game.GearTest do
  use HacLong.DataCase, async: true

  alias HacLong.Game.{Characters, Data, Engine, Gear, Rng}

  setup do
    on_exit(&Rng.clear/0)
  end

  defp player do
    {:ok, p} = Engine.new_player("Thử", "dk")
    %{p | level: 25}
  end

  # B-15: đồ kiểu MU, 2 dòng cộng thêm (+8 tấn công)
  defp sword, do: %{uid: "#KIEM", base: "item_0_5", rarity: 0, bonus: %{}, opt: 2}

  test "tạo món ngẫu nhiên theo cấp quái" do
    # 0.1: vũ khí; 0.1: đồ gốc thuộc mức cấp cao nhất (cấp 12) của Kiếm Sĩ; 0.9: 2 dòng cộng thêm
    # (trọng số 0/1/2/3 dòng: 50/35/12/3)
    Rng.put_sequence([0.1, 0.1, 0.9])
    g = Gear.roll(12, Gear.weights(), nil, "dk")
    base = Data.items()[g.base]
    assert base.slot == "weapon" and base.level == 12 and "dk" in base.classes
    # kiểu MU (B-15): không còn chỉ số cộng ngẫu nhiên, chỉ dòng cộng thêm
    assert g.opt == 2 and g.rarity == 0 and g.bonus == %{}
    assert Gear.kind(g) == "opt" and Gear.label(g) == "#{base.name} (+8)"
    assert String.starts_with?(g.uid, "#")

    # 0.1 ở trọng số: đồ thường không dòng nào
    Rng.put_sequence([0.1])
    g = Gear.roll(12, Gear.weights(), nil, "dk")
    refute Map.has_key?(g, :opt)
    assert Gear.kind(g) == "" and Gear.label(g) == Data.item(g.base).name

    # cấp quá thấp, không có đồ gốc nào (trừ đồ khởi đầu giá 0) thì không rơi
    Rng.put_sequence([0.99])
    assert Gear.roll(2) == nil
  end

  test "nạp đồ cũ: độ hiếm Tốt / Hiếm / Sử Thi thành dòng cộng thêm, bỏ chỉ số cộng (B-15)" do
    [a, b, c] =
      Gear.load([
        %{"uid" => "#A", "base" => "item_0_5", "rarity" => 3, "bonus" => %{"str" => 9}},
        %{"uid" => "#B", "base" => "item_0_5", "rarity" => 1, "bonus" => %{}, "opt" => 3},
        %{"uid" => "#C", "base" => "item_0_5", "rarity" => 0, "bonus" => %{}}
      ])

    assert %{opt: 3, rarity: 0, bonus: %{}} = a
    assert b.opt == 3
    refute Map.has_key?(c, :opt)
  end

  test "mặc đồ có dòng cộng thêm, tháo ra thì về túi" do
    p = player()
    base = Engine.derived(p)
    {p, _} = Gear.add(p, sword())
    assert [%{name: "Đại Đao", kind: "opt", opt: 2}] = Enum.map(Gear.bag(p), &Gear.resolve/1)

    {%{ok: true, msg: "Đã trang bị Đại Đao."}, p} = Engine.equip(p, "#KIEM")
    d = Engine.derived(p)

    # Kiếm Sĩ: Đại Đao 42 tấn công thay Rìu Nhỏ 4; 2 dòng cộng thêm +8 (làm tròn nên lệch tối đa 1)
    assert abs(d.atk - (base.atk + 38 + 8)) <= 1
    assert Gear.bag(p) == []
    # rìu cũ về túi đồ thường
    assert p.inv["item_1_0"] == 1
    assert {%{ok: false, msg: "Đang mặc món này."}, _} = Engine.sell(p, "#KIEM")

    {_, p} = Engine.equip(p, "item_1_0")
    assert [%{uid: "#KIEM"}] = Gear.bag(p)
    gold = p.gold
    {%{ok: true}, p} = Engine.sell(p, "#KIEM")
    assert p.gold > gold and p.gear == []
  end

  test "nâng cấp đồ ngẫu nhiên như đồ thường" do
    p = %{player() | gold: 10_000} |> Engine.add_item("jewel_bless", 5)
    {p, _} = Gear.add(p, sword())
    {_, p} = Engine.equip(p, "#KIEM")

    {%{ok: true, msg: "✨ Ép thành công Đại Đao lên +1!"}, p} =
      Engine.upgrade(p, "weapon")

    assert Engine.upgrade_level(p, "#KIEM") == 1
  end

  test "túi đầy thì món mới bán luôn" do
    p = player()

    p =
      Enum.reduce(1..Gear.max_bag(), p, fn i, p ->
        elem(Gear.add(p, %{sword() | uid: "##{i}"}), 0)
      end)

    assert {p2, {:sold, gold}} = Gear.add(p, sword())
    assert p2.gold == p.gold + gold and length(p2.gear) == Gear.max_bag()
  end

  test "lưu và nạp lại từ database" do
    {:ok, user} =
      HacLong.Accounts.register(%{
        "username" => "luudo#{System.unique_integer([:positive])}",
        "password" => "matkhau1"
      })

    {:ok, p} = Engine.new_player("Lưu Đồ #{System.unique_integer([:positive])}", "dk")
    {p, _} = Gear.add(%{p | level: 25}, sword())
    {_, p} = Engine.equip(p, "#KIEM")
    p = p |> Map.merge(%{pos: %{map: "village", x: 12, y: 14}, upgrades: %{"#KIEM" => 2}})
    Characters.save!(user.id, p)
    q = Characters.load(user.id)
    assert q.gear == p.gear and q.equip.weapon == "#KIEM"
    assert q.upgrades == %{"#KIEM" => 2}
    assert Engine.derived(q) == Engine.derived(p)
  end

  test "nạp nhân vật: máu / MP cũ vượt mức tối đa thì hạ về tối đa (B-15)" do
    {:ok, user} =
      HacLong.Accounts.register(%{
        "username" => "maucu#{System.unique_integer([:positive])}",
        "password" => "matkhau1"
      })

    {:ok, p} = Engine.new_player("Máu Cũ #{System.unique_integer([:positive])}", "dk")
    d = Engine.derived(p)
    p = Map.merge(p, %{pos: %{map: "village", x: 12, y: 14}, hp: d.maxHp + 97, mp: d.maxMp + 5})
    Characters.save!(user.id, p)
    q = Characters.load(user.id)
    assert q.hp == d.maxHp and q.mp == d.maxMp
  end

  test "trận đang đánh có hiệu ứng, hồi chiêu, đồ rơi vẫn lưu và nạp lại đúng" do
    {:ok, user} =
      HacLong.Accounts.register(%{
        "username" => "tran#{System.unique_integer([:positive])}",
        "password" => "matkhau1"
      })

    Rng.put_sequence([0.99])
    {:ok, p} = Engine.new_player("Trận #{System.unique_integer([:positive])}", "elf")
    p = %{p | level: 10} |> Map.put(:pos, %{map: "forest_1", x: 5, y: 5})
    {_, p} = Engine.start_battle(p, 0, false)
    p = put_in(p.battle.monster.hp, 10_000)
    {_, p} = Engine.act(p, "skill", "venom")
    p = put_in(p.battle.reward, %{xp: 1, gold: 1, items: [], levels: 0, gear: ["Kiếm"]})
    Characters.save!(user.id, p)
    q = Characters.load(user.id)
    assert q.battle.effects == p.battle.effects and q.battle.cds == p.battle.cds
    assert q.battle.reward.gear == ["Kiếm"]
    assert {%{ok: true}, _} = Engine.act(q, "attack")
  end
end

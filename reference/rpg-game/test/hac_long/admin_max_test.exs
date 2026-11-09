defmodule HacLong.AdminMaxTest do
  @moduledoc "Công thức nhân vật tối đa trong docs/ADMIN_GUIDE.md §6: mọi lệnh hợp lệ, mặc được đủ 11 ô (Đấu Sĩ 10, không mũ; Tiên Nữ không tay trái)."
  use ExUnit.Case, async: true

  alias HacLong.Admin
  alias HacLong.Game.{Commands, Data, Engine, Gear}

  @exc_w ~w(atk_pct crit heal_kill mp_kill atk_lvl ar_pct)
  @exc_a ~w(hp_pct dmg_red gold_pct mp_pct reflect def_rate)
  @set %{
    "dk" => {"item_0_19", true, ~w(item_7_33 item_8_33 item_9_33 item_10_33 item_11_33)},
    "dw" => {"item_5_11", true, ~w(item_7_30 item_8_30 item_9_30 item_10_30 item_11_30)},
    "elf" => {"item_4_24", false, ~w(item_7_31 item_8_31 item_9_31 item_10_31 item_11_31)},
    "mg" => {"item_0_28", true, ~w(item_8_29 item_9_29 item_10_29 item_11_29)}
  }

  # tỉ lệ chia điểm gợi ý (docs/ADMIN_GUIDE.md §6), điểm lẻ cộng vào chỉ số đầu
  @share %{
    "dk" => [{"str", 0.45}, {"agi", 0.2}, {"vit", 0.25}, {"ene", 0.1}],
    "dw" => [{"ene", 0.5}, {"agi", 0.2}, {"vit", 0.2}, {"str", 0.1}],
    "elf" => [{"agi", 0.45}, {"str", 0.2}, {"vit", 0.25}, {"ene", 0.1}],
    "mg" => [{"str", 0.4}, {"ene", 0.25}, {"agi", 0.2}, {"vit", 0.15}]
  }

  defp op(p, name, params) do
    {:ok, f} = Admin.build(name, params)
    assert {:ok, p, _msg} = f.(p)
    p
  end

  for cls <- ~w(dk dw elf mg) do
    test "nhân vật #{cls} tối đa" do
      cls = unquote(cls)
      {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Max#{cls}", "cls" => cls})
      # dual: cầm 2 vũ khí (B-42), vũ khí thứ hai ở tay trái thay khiên
      {weapon, dual, set} = @set[cls]
      full = %{"opt" => 4, "luck" => true, "up" => 11}

      p =
        p
        |> op("set_rebirths", %{"n" => 10})
        |> op("set_level", %{"level" => 50})
        |> op("reset_stats", %{})

      # điểm đúng như người chơi thật (49 cấp + 10 lần chuyển sinh), cộng theo tỉ lệ gợi ý trong tài liệu
      assert p.points ==
               49 * Engine.points_per_level(cls) + 10 * Engine.rebirth_points()

      # như tài liệu: chia điểm bằng lệnh quản trị (add_stats rồi add_points trừ hết), dựng được cả cho người khác
      total = p.points
      base_sum = p.stats |> Map.values() |> Enum.sum()
      add = Map.new(@share[cls], fn {k, r} -> {k, floor(total * r)} end)
      {first, _} = hd(@share[cls])
      add = Map.update!(add, first, &(&1 + total - Enum.sum(Map.values(add))))

      p = p |> op("add_stats", add) |> op("add_points", %{"n" => -total})
      assert p.points == 0
      assert p.stats |> Map.values() |> Enum.sum() == base_sum + total

      p =
        p
        |> op("give_gear", Map.merge(full, %{"base" => weapon, "skill" => true, "exc" => @exc_w}))

      p =
        Enum.reduce(
          set,
          p,
          &op(&2, "give_gear", Map.merge(full, %{"base" => &1, "exc" => @exc_a}))
        )

      p =
        p
        |> op("give_gear", Map.merge(full, %{"base" => "item_13_24", "exc" => @exc_a}))
        |> op("give_gear", Map.merge(full, %{"base" => "item_13_24", "exc" => @exc_a}))
        |> op("give_gear", Map.merge(full, %{"base" => "item_13_27", "exc" => @exc_w}))
        |> op("give_gear", Map.merge(full, %{"base" => "wing_#{cls}_3", "wopt" => "ignore_def"}))

      wing = Enum.find(Gear.list(p), &(&1.base == "wing_#{cls}_3"))
      assert wing.opt == 4 and wing.luck and wing.wopt == "ignore_def"

      p =
        Enum.reduce(Gear.bag(p), p, fn g, p ->
          {r, p} = Commands.run(p, %{"act" => "equip", "id" => g.uid})
          assert r.ok, "#{g.base}: #{r[:msg]}"
          p
        end)

      p =
        if dual do
          p =
            op(
              p,
              "give_gear",
              Map.merge(full, %{"base" => weapon, "skill" => true, "exc" => @exc_w})
            )

          g = Enum.find(Gear.bag(p), &(&1.base == weapon))
          {r, p} = Commands.run(p, %{"act" => "equip", "id" => g.uid, "hand" => "left"})
          assert r.ok, r[:msg]
          p
        else
          p
        end

      worn = p.equip |> Map.values() |> Enum.count(& &1)
      assert worn == if(dual, do: 11, else: 10) - if(cls == "mg", do: 1, else: 0)
      if dual, do: assert(Engine.left_weapon(p).name == Data.item(weapon).name)

      # Long Vương cấp tối đa, dắt theo
      p = p |> op("give_pet", %{"id" => "long_vuong", "level" => 20})
      assert p.pet == "long_vuong" and "long_vuong" in p.pets
      assert HacLong.Game.Pets.level(p, "long_vuong") == 20
    end
  end

  test "give_pet: thú thường / thú hiếm, đặt cấp, đã có thì không thêm lần nữa; sai id / cấp thì báo lỗi" do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Pet", "cls" => "dk"})

    p =
      p
      |> op("give_pet", %{"id" => "sheep", "level" => 5})
      |> op("give_pet", %{"id" => "long_vuong"})

    assert p.pets == ["sheep", "long_vuong"] and p.pet == "long_vuong"

    assert HacLong.Game.Pets.level(p, "sheep") == 5 and
             HacLong.Game.Pets.level(p, "long_vuong") == 1

    p = op(p, "give_pet", %{"id" => "long_vuong", "level" => 15})
    assert p.pets == ["sheep", "long_vuong"] and HacLong.Game.Pets.level(p, "long_vuong") == 15
    assert {:error, _} = Admin.build("give_pet", %{"id" => "rong_gia"})
    assert {:error, _} = Admin.build("give_pet", %{"id" => "sheep", "level" => 21})
  end

  test "reset_stats: chỉ số về gốc, điểm theo cấp và chuyển sinh, bỏ điểm cày / cộng thêm trước đó" do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Reset", "cls" => "dk"})

    p =
      p
      |> op("set_level", %{"level" => 30})
      |> op("add_points", %{"n" => 77})
      |> op("add_stats", %{"str" => 120})
      |> op("set_rebirths", %{"n" => 2})
      |> op("reset_stats", %{})

    assert p.stats == Data.class("dk").base
    assert p.points == 29 * Engine.points_per_level("dk") + 2 * Engine.rebirth_points()
  end

  test "give_gear: Excellent đúng loại món (vũ khí / dây chuyền, giáp / khiên / nhẫn), cánh không có Excellent" do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Exc", "cls" => "dk"})

    give = fn base, exc ->
      with {:ok, f} <- Admin.build("give_gear", %{"base" => base, "exc" => exc}), do: f.(p)
    end

    assert {:ok, _, _} = give.("item_0_26", ["atk_pct"])
    assert {:ok, _, _} = give.("item_13_27", ["crit"])
    assert {:ok, _, _} = give.("item_13_24", ["hp_pct"])
    assert {:error, _} = give.("item_0_26", ["hp_pct"])
    assert {:error, _} = give.("item_13_24", ["atk_pct"])
    assert {:error, "Dòng Excellent" <> _} = give.("wing_dk_3", ["hp_pct"])
    assert {:ok, _, _} = give.("wing_dk_3", [])
  end

  test "clear_bag: hủy mọi trang bị trong túi (cả món khóa, cấp ép), giữ đồ đang mặc và đồ cất tủ" do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Don", "cls" => "dk"})
    worn = p.equip
    p = p |> Engine.add_item("item_1_1", 3) |> Engine.add_item("potion_s", 2)
    [a, b, c] = Gear.bag(p)

    p =
      p
      |> Gear.set_locked(a.uid, true)
      |> Gear.put(b.uid, :stored, true)
      |> Map.put(:upgrades, %{a.uid => 5, b.uid => 3})

    p = op(p, "clear_bag", %{})
    assert Gear.bag(p) == [] and p.equip == worn
    assert [%{uid: uid}] = Enum.filter(Gear.list(p), & &1[:stored])
    assert uid == b.uid and Gear.find(p, c.uid) == nil
    assert p.upgrades == %{b.uid => 3} and p.inv["potion_s"] == 5
  end

  # thẻ Quản trị → Dựng nhân vật tối đa: bộ đồ ở RULES.admin_max_build, `give_gear` `equip: true` mặc luôn,
  # chia điểm đủ chỉ số yêu cầu trước → mọi món có tác dụng (không viền đỏ), `give_pet` `level: "max"`
  for cls <- ~w(dk dw elf mg) do
    test "thẻ Dựng tối đa (RULES.admin_max_build) #{cls}: mặc luôn, mọi món có tác dụng" do
      cls = unquote(cls)
      m = Data.rules().admin_max_build
      set = m.sets[String.to_existing_atom(cls)]
      {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Mx#{cls}", "cls" => cls})

      p =
        p
        |> op("set_rebirths", %{"n" => m.rebirths})
        |> op("set_level", %{"level" => m.level})
        |> op("reset_stats", %{})

      left = set[:left]
      # vũ khí 2 tay (cung Tiên Nữ): không khiên / tay trái
      two = Data.item(set.weapon)[:hands] == 2
      shield = if two or left, do: nil, else: m.shield

      gear =
        Enum.reject([set.weapon, left, shield, m.ring, m.ring, m.pendant | set.armor], &is_nil/1)

      need =
        Enum.reduce(gear, %{}, fn id, acc ->
          Map.merge(acc, Data.item(id)[:req] || %{}, fn _, a, b -> max(a, b) end)
        end)

      add = for {k, v} <- need, into: %{}, do: {Atom.to_string(k), max(0, v - p.stats[k])}

      p = %{
        p
        | stats: Map.new(p.stats, fn {k, v} -> {k, v + Map.get(add, Atom.to_string(k), 0)} end),
          points: 0
      }

      g = fn p, base, extra ->
        op(
          p,
          "give_gear",
          Map.merge(
            %{"base" => base, "opt" => m.opt, "up" => m.up, "luck" => true, "equip" => true},
            extra
          )
        )
      end

      p = g.(p, set.weapon, %{"exc" => m.exc_weapon, "skill" => true})
      p = if left, do: g.(p, left, %{"hand" => "left"}), else: p
      p = if shield, do: g.(p, shield, %{}), else: p
      p = Enum.reduce(set.armor, p, &g.(&2, &1, %{"exc" => m.exc_armor}))

      p =
        p
        |> g.(m.ring, %{})
        |> g.(m.ring, %{})
        |> g.(m.pendant, %{})
        |> g.("wing_#{cls}_3", %{"wopt" => m.wing_opt})

      # thần thú: tặng hết ở cấp tối đa, dắt con cuối; đầy Long Khí / Phong Khí
      last = List.last(m.pets)

      p =
        Enum.reduce(m.pets, p, fn id, p ->
          op(p, "give_pet", %{"id" => id, "level" => "max", "lead" => id == last})
        end)
        |> op("set_qi", %{"long" => "max", "phong" => "max"})

      assert Engine.inactive_slots(p) == []

      assert p.equip.wing && p.equip.ring1 && p.equip.ring2 && p.equip.pendant && p.equip.weapon
      assert p.equip.shield != nil == not two
      # món vừa tặng (+up) không món nào nằm lại trong túi: mặc được hết
      assert Enum.all?(Gear.bag(p), &(Engine.upgrade_level(p, &1.uid) == 0))

      assert Gear.item(p, p.equip.weapon).base == set.weapon
      assert Engine.upgrade_level(p, p.equip.armor) == m.up
      assert p.pet == last and p.pets == m.pets

      assert Enum.all?(
               m.pets,
               &(HacLong.Game.Pets.level(p, &1) == HacLong.Game.Pets.max_level(&1))
             )

      assert p.long_khi == Data.rules().fishing.dragon.long_khi_max
      assert HacLong.Game.Kite.phong_khi(p) == HacLong.Game.Kite.phong_khi_max()
    end
  end

  test "set_qi: đặt Long Khí / Phong Khí (số hoặc max), ngoài khoảng thì báo lỗi; give_pet lead: false giữ thú đang dắt" do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Khi", "cls" => "elf"})
    p = op(p, "set_qi", %{"long" => 7})
    assert p.long_khi == 7 and HacLong.Game.Kite.phong_khi(p) == 0
    p = op(p, "set_qi", %{"phong" => "max"})
    assert p.long_khi == 7 and HacLong.Game.Kite.phong_khi(p) == HacLong.Game.Kite.phong_khi_max()
    assert {:error, _} = Admin.build("set_qi", %{})
    assert {:error, "Long Khí" <> _} = Admin.build("set_qi", %{"long" => 100_000})
    assert {:error, "Phong Khí" <> _} = Admin.build("set_qi", %{"phong" => -1})

    p =
      p
      |> op("give_pet", %{"id" => "chim_lac"})
      |> op("give_pet", %{"id" => "hac_long", "lead" => false})

    assert p.pet == "chim_lac" and "hac_long" in p.pets
  end

  test "túi đầy: tặng + mặc luôn vẫn được, món bị thay ra gửi Hộp thư giữ +N; không mặc thì báo túi đầy" do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Full", "cls" => "dk"})
    p = op(p, "set_level", %{"level" => 50})
    # mũ đang mặc +7 (món sẽ bị thay ra)
    p = op(p, "give_gear", %{"base" => "item_7_33", "up" => 7, "equip" => true})
    old = p.equip.helm
    assert Engine.upgrade_level(p, old) == 7

    p =
      Enum.reduce(1..(Gear.max_bag() - length(Gear.bag(p))), p, fn _, p ->
        op(p, "give_gear", %{"base" => "item_13_8"})
      end)

    assert length(Gear.bag(p)) == Gear.max_bag()

    {:ok, f} = Admin.build("give_gear", %{"base" => "item_13_8"})
    assert {:error, "Túi trang bị đã đầy" <> _} = f.(p)

    {:ok, f} = Admin.build("give_gear", %{"base" => "item_7_33", "up" => 11, "equip" => true})
    assert {:ok, p2, msg} = f.(p)
    assert msg =~ "đã mặc" and msg =~ "gửi vào Hộp thư"
    assert Engine.upgrade_level(p2, p2.equip.helm) == 11
    assert length(Gear.bag(p2)) == Gear.max_bag()
    assert [%{uid: ^old, up: 7}] = p2.mail_out
    refute Map.has_key?(p2.upgrades, old)
  end
end

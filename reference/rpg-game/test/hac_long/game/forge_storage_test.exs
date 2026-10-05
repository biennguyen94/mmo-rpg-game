defmodule HacLong.Game.ForgeStorageTest do
  # Phase 4 (INTEGRATION_PLAN §12): Ngọc Sinh Mệnh, ép đồ trong túi, vứt đồ, Tủ Đồ ở Nhà.
  use ExUnit.Case, async: true

  alias HacLong.Game.{Commands, Data, Engine, Gear, Rng, Storage}

  @smith %{map: "village", x: 8, y: 11}
  @wardrobe %{map: "home", x: 6, y: 1}

  setup do
    on_exit(&Rng.clear/0)
  end

  defp player(attrs) do
    {:ok, p} = Engine.new_player("Thử", "dk")
    Map.merge(Map.merge(p, %{pos: @smith, gold: 100_000, tutorial: nil, level: 30}), attrs)
  end

  defp sword(attrs \\ %{}), do: Map.merge(Gear.new("broadsword", 2, %{str: 3}), attrs)

  describe "Ngọc Sinh Mệnh (D4)" do
    test "thành công thêm dòng +4 tấn công; thất bại mất dòng cuối; tối đa 4 dòng" do
      l = Data.rules().upgrade.life
      g = sword()
      p = player(%{gear: [g], inv: %{l.jewel => 10}}) |> then(&elem(Engine.equip(&1, g.uid), 1))
      atk0 = Engine.derived(p).atk

      Rng.put_sequence([0.0])

      {%{ok: true, life: %{result: "success", lines: 1}}, p} =
        Commands.run(p, %{"act" => "life", "slot" => "weapon"})

      assert Gear.find(p, g.uid).opt == 1
      assert Engine.derived(p).atk == atk0 + l.per_line
      assert p.inv[l.jewel] == 9

      {_, p} = Commands.run(p, %{"act" => "life", "id" => g.uid})
      assert Gear.find(p, g.uid).opt == 2

      Rng.put_sequence([0.99])

      {%{ok: true, life: %{result: "fail", lines: 1}}, p} =
        Commands.run(p, %{"act" => "life", "id" => g.uid})

      assert Gear.find(p, g.uid).opt == 1

      Rng.put_sequence([0.0])

      p =
        Enum.reduce(1..3, p, fn _, p ->
          elem(Commands.run(p, %{"act" => "life", "id" => g.uid}), 1)
        end)

      assert Gear.find(p, g.uid).opt == 4

      assert {%{ok: false, msg: msg}, _} = Commands.run(p, %{"act" => "life", "id" => g.uid})
      assert msg =~ "đủ 4 dòng"
    end

    test "đồ thường trong túi được tách bản riêng; cánh +phòng thủ; thiếu ngọc / xa Thợ Rèn thì từ chối" do
      l = Data.rules().upgrade.life
      p = player(%{inv: %{"chain" => 2, l.jewel => 1}})
      Rng.put_sequence([0.0])
      {%{ok: true}, p} = Commands.run(p, %{"act" => "life", "id" => "chain"})
      assert p.inv["chain"] == 1
      assert [%{base: "chain", opt: 1}] = Gear.list(p)

      assert {%{ok: false, msg: "Cần 1 Ngọc Sinh Mệnh."}, _} =
               Commands.run(p, %{"act" => "life", "id" => "chain"})

      far = %{p | pos: @wardrobe, inv: Map.put(p.inv, l.jewel, 1)}

      assert {%{ok: false, msg: "Hãy đến gặp Thợ Rèn ở Làng."}, _} =
               Commands.run(far, %{"act" => "life", "id" => "chain"})
    end
  end

  describe "ép +N đồ trong túi (D8)" do
    test "đồ hiếm và đồ thường trong túi ép được bằng quặng; vỡ đồ trong túi chỉ mất món đó" do
      g = sword()
      p = player(%{gear: [g], inv: %{"ore" => 10, "dagger" => 1}})

      {%{ok: true, upgrade: %{level: 1}}, p} =
        Commands.run(p, %{"act" => "upgrade", "id" => g.uid})

      assert Engine.upgrade_level(p, g.uid) == 1
      assert Engine.view(p).forgeBag[g.uid].level == 1

      {%{ok: true}, p} = Commands.run(p, %{"act" => "upgrade", "id" => "dagger"})
      [d] = Enum.filter(Gear.list(p), &(&1.base == "dagger"))
      assert Engine.upgrade_level(p, d.uid) == 1 and p.inv["dagger"] == nil

      # +10 → +11 thất bại là vỡ: món trong túi biến mất, đồ đang mặc không đổi
      p = %{p | upgrades: Map.put(p.upgrades, g.uid, 10), inv: Map.put(p.inv, "jewel_chaos", 1)}
      Rng.put_sequence([0.99])

      {%{ok: true, upgrade: %{result: "destroy"}}, p} =
        Commands.run(p, %{"act" => "upgrade", "id" => g.uid, "confirm" => true})

      assert Gear.find(p, g.uid) == nil and p.equip.weapon == "club"
    end
  end

  describe "vứt đồ (C6)" do
    test "đồ thường theo số lượng; đồ hiếm; không vứt đồ đang mặc / khóa" do
      g = sword()
      locked = sword(%{locked: true})
      p = player(%{gear: [g, locked], inv: %{"herb" => 5}})
      {%{ok: true}, p} = Commands.run(p, %{"act" => "discard", "id" => "herb", "n" => 3})
      assert p.inv["herb"] == 2
      assert {%{ok: false}, _} = Commands.run(p, %{"act" => "discard", "id" => "herb", "n" => 3})
      {%{ok: true}, p} = Commands.run(p, %{"act" => "discard", "id" => g.uid})
      assert Gear.find(p, g.uid) == nil

      assert {%{ok: false, msg: msg}, _} =
               Commands.run(p, %{"act" => "discard", "id" => locked.uid})

      assert msg =~ "đang khóa"
      {_, p} = Engine.equip(p, "club")
      assert {%{ok: false}, _} = Commands.run(p, %{"act" => "discard", "id" => "club"})
    end
  end

  describe "Tủ Đồ ở Nhà (C7)" do
    test "cất / lấy đồ thường và đồ hiếm; đồ đang cất không nằm trong túi, không bán / mặc được" do
      g = sword()
      p = player(%{pos: @wardrobe, gear: [g], inv: %{"herb" => 5}})
      {%{ok: true}, p} = Commands.run(p, %{"act" => "store", "id" => "herb", "n" => 4})
      assert p.inv["herb"] == 1 and Storage.get(p).inv["herb"] == 4
      {%{ok: true}, p} = Commands.run(p, %{"act" => "store", "id" => g.uid})
      assert Gear.bag(p) == [] and Gear.stored?(p, g.uid)
      assert Engine.view(p).storage.gear == [g.uid]
      assert {%{ok: false}, _} = Engine.sell(p, g.uid)
      assert {%{ok: false}, _} = Engine.equip(p, g.uid)
      assert {%{ok: false}, _} = Engine.discard(p, g.uid)

      {%{ok: true}, p} = Commands.run(p, %{"act" => "unstore", "id" => "herb", "n" => 4})
      {%{ok: true}, p} = Commands.run(p, %{"act" => "unstore", "id" => g.uid})
      assert p.inv["herb"] == 5 and Storage.get(p).inv == %{} and length(Gear.bag(p)) == 1

      village = %{p | pos: @smith}

      assert {%{ok: false, msg: "Hãy đến gặp Tủ Đồ ở Nhà."}, _} =
               Commands.run(village, %{"act" => "store", "id" => "herb"})
    end

    test "giới hạn số loại / số đồ hiếm; mở rộng bằng vàng" do
      r = Data.rules().storage
      items = Data.items() |> Map.keys() |> Enum.take(r.items + 1)
      p = player(%{pos: @wardrobe, inv: Map.new(items, &{&1, 1})})

      p =
        Enum.reduce(Enum.take(items, r.items), p, fn id, p -> elem(Storage.store(p, id, 1), 1) end)

      assert {%{ok: false, msg: msg}, _} = Storage.store(p, List.last(items), 1)
      assert msg =~ "#{r.items} loại"

      gear = for _ <- 1..(r.gear + 1), do: sword()
      p = player(%{pos: @wardrobe, gear: gear})
      p = Enum.reduce(Enum.take(gear, r.gear), p, fn g, p -> elem(Storage.store(p, g.uid), 1) end)
      assert {%{ok: false}, _} = Storage.store(p, List.last(gear).uid)
      [first | _] = r.expand
      gold = p.gold
      {%{ok: true}, p} = Commands.run(p, %{"act" => "storage_expand"})
      assert p.gold == gold - first.gold and Storage.gear_cap(p) == r.gear + first.gear
      assert {%{ok: true}, _} = Storage.store(p, List.last(gear).uid)
    end
  end
end

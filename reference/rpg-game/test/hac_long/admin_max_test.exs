defmodule HacLong.AdminMaxTest do
  @moduledoc "Công thức nhân vật tối đa trong docs/ADMIN_GUIDE.md §6: mọi lệnh hợp lệ, mặc được đủ 11 ô (Pháp Sư 10)."
  use ExUnit.Case, async: true

  alias HacLong.Admin
  alias HacLong.Game.{Commands, Data, Engine, Gear}

  @exc_w ~w(atk_pct crit heal_kill mp_kill atk_lvl ar_pct)
  @exc_a ~w(hp_pct dmg_red gold_pct mp_pct reflect def_rate)
  @set %{
    "dk" => {"item_0_19", "item_6_18", ~w(item_7_33 item_8_33 item_9_33 item_10_33 item_11_33)},
    "dw" => {"item_5_11", "item_6_18", ~w(item_7_30 item_8_30 item_9_30 item_10_30 item_11_30)},
    "elf" => {"item_4_24", nil, ~w(item_7_31 item_8_31 item_9_31 item_10_31 item_11_31)},
    "mg" => {"item_0_28", nil, ~w(item_8_29 item_9_29 item_10_29 item_11_29)}
  }

  # tỉ lệ chia điểm gợi ý (docs/ADMIN_GUIDE.md §6), điểm lẻ cộng vào chỉ số đầu
  @share %{
    "dk" => [{"str", 0.45}, {"agi", 0.2}, {"vit", 0.25}, {"ene", 0.1}],
    "dw" => [{"ene", 0.5}, {"agi", 0.2}, {"vit", 0.2}, {"str", 0.1}],
    "elf" => [{"agi", 0.45}, {"str", 0.2}, {"vit", 0.25}, {"ene", 0.1}],
    "mg" => [{"str", 0.4}, {"ene", 0.25}, {"agi", 0.2}, {"vit", 0.15}]
  }

  defp alloc(p, _stat, 0), do: p

  # mỗi lệnh cộng tối đa 99 điểm (như nút cộng nhiều trong game)
  defp alloc(p, stat, n) do
    k = min(n, 99)
    {r, p} = Commands.run(p, %{"act" => "alloc", "stat" => stat, "n" => k})
    assert r.ok, inspect(r)
    alloc(p, stat, n - k)
  end

  defp op(p, name, params) do
    {:ok, f} = Admin.build(name, params)
    assert {:ok, p, _msg} = f.(p)
    p
  end

  for cls <- ~w(dk dw elf mg) do
    test "nhân vật #{cls} tối đa" do
      cls = unquote(cls)
      {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Max#{cls}", "cls" => cls})
      {weapon, shield, set} = @set[cls]
      full = %{"opt" => 4, "luck" => true, "up" => 11}

      p =
        p
        |> op("set_rebirths", %{"n" => 10})
        |> op("set_level", %{"level" => 50})
        |> op("reset_stats", %{})

      # điểm đúng như người chơi thật (49 cấp + 10 lần chuyển sinh), cộng theo tỉ lệ gợi ý trong tài liệu
      assert p.points ==
               49 * Engine.points_per_level(cls) + 10 * Engine.rebirth_points()

      total = p.points
      p = Enum.reduce(@share[cls], p, fn {k, r}, p -> alloc(p, k, floor(total * r)) end)
      p = alloc(p, @share[cls] |> hd() |> elem(0), p.points)
      assert p.points == 0

      p =
        p
        |> op("give_gear", Map.merge(full, %{"base" => weapon, "skill" => true, "exc" => @exc_w}))

      p =
        if shield,
          do: op(p, "give_gear", Map.merge(full, %{"base" => shield, "exc" => @exc_a})),
          else: p

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

      worn = p.equip |> Map.values() |> Enum.count(& &1)
      assert worn == if(shield, do: 11, else: 10) - if(cls == "mg", do: 1, else: 0)
    end
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
end

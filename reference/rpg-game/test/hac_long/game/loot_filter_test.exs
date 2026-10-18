defmodule HacLong.Game.LootFilterTest do
  @moduledoc "Menu → Cài đặt \"Tự hủy đồ rơi\" (`AutoHunt.loot_filter/2`): món không thuộc loại giữ lại bị bỏ ngay khi rơi."
  use ExUnit.Case, async: true

  alias HacLong.Game.{AutoHunt, Data, Engine, Gear, Rng}

  defp fight(p) do
    m = Engine.make_monster(%{id: "ghoul", name: "Ma", level: 30}, false)
    {_, p} = Engine.start_with_monster(%{p | level: 30}, 0, Map.put(m, :hp, m.maxHp))

    # mọi lần may rủi = 0: chắc chắn rơi đồ
    Rng.put_sequence([0.0])
    {_, p} = Engine.finish_win(p)
    Rng.clear()
    p
  end

  defp hero do
    {:ok, p} = Engine.new_player("Lọc", "dk")
    p
  end

  test "lưu cài đặt, chỉ nhận loại hợp lệ; tự đánh bật lại không làm mất" do
    {%{ok: true}, p} = AutoHunt.loot_filter(hero(), %{"on" => true, "keep" => ["exc", "bogus"]})
    assert AutoHunt.filter_keep(p) == ["exc"]
    {%{ok: true}, p2} = AutoHunt.loot_filter(p, %{"on" => false, "keep" => ["exc"]})
    assert AutoHunt.filter_keep(p2) == nil

    p3 = Map.merge(p, %{pos: %{map: "forest_1", x: 13, y: 16}})
    {%{ok: true}, p3} = AutoHunt.configure(p3, %{"on" => true, "target" => "all"})
    assert AutoHunt.filter_keep(p3) == ["exc"]
  end

  test "bật mà món không thuộc loại giữ: không vào túi, ghi tự hủy; tắt thì giữ" do
    kept = fight(hero())
    assert length(Gear.bag(kept)) == 1

    {_, p} = AutoHunt.loot_filter(hero(), %{"on" => true, "keep" => []})
    trashed = fight(p)
    assert Gear.bag(trashed) == []
    assert Enum.any?(trashed.battle.log, &(&1.text =~ "Tự hủy"))
    assert Data.rules().auto.keep != []
  end

  test "\"Tốt hơn đồ đang mặc\" tính cả cấp ép của đồ đang mặc (như so sánh trên bảng chi tiết)" do
    p = %{hero() | level: 50, stats: %{str: 200, agi: 200, vit: 50, ene: 50}}
    {p, :kept} = Gear.add(p, Gear.plain("item_6_12"))
    [worn] = Gear.bag(p)
    p = %{p | equip: Map.put(p.equip, :shield, worn.uid)}
    drop = Gear.resolve(Gear.plain("item_6_20"))
    assert drop.def > Gear.item(p, worn.uid).def

    # khiên đang mặc +0 yếu hơn: món rơi tốt hơn, giữ
    assert AutoHunt.good?(p, drop, ["better"])

    # ép +11: đang mặc mạnh hơn món rơi (+0), không giữ
    p = Map.put(p, :upgrades, %{worn.uid => 11})
    assert Gear.item(p, worn.uid).def + Engine.upgrade_bonus(p, worn.uid) >= drop.def
    refute AutoHunt.good?(p, drop, ["better"])
  end
end

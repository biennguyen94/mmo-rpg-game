defmodule HacLong.Bots.BrainForgeTest do
  # DECISIONS "Bot ép đồ, chuyển sinh": bot rèn đồ, ghép cánh, chuyển sinh như người thật
  use ExUnit.Case, async: true

  alias HacLong.Bots.Brain
  alias HacLong.Game.{Data, Engine, Gear}

  @f Data.rules().bots.forge

  defp player(attrs \\ %{}) do
    {:ok, p} = Engine.new_player("Bot", "dk")
    Map.merge(p, Map.merge(%{level: 30, gold: 10_000_000}, attrs))
  end

  defp up(p, id, n), do: Map.put(p, :upgrades, Map.put(p[:upgrades] || %{}, id, n))

  test "ép món đang mặc cấp thấp nhất bằng Ngọc Ước Nguyện ở Thợ Rèn; giữ lại vàng mua bình" do
    p = player(%{inv: %{"jewel_bless" => 1}})
    assert {"shop", %{"act" => "upgrade", "slot" => _}} = Brain.forge_job(p)
    # vàng không dư quá phần giữ lại: không ép
    assert Brain.forge_job(%{p | gold: @f.gold_keep_per_level * p.level}) == nil
    # không có ngọc: không ép
    assert Brain.forge_job(%{p | inv: %{}}) == nil
  end

  test "bước có thể hỏng (+7) chỉ ép khi dư Ngọc Tâm Linh" do
    p = player()
    p = Enum.reduce(p.equip, p, fn {_s, id}, p -> if id, do: up(p, id, 6), else: p end)
    assert Brain.forge_job(%{p | inv: %{"jewel_soul" => 1}}) == nil

    assert {"shop", %{"act" => "upgrade"}} =
             Brain.forge_job(%{p | inv: %{"jewel_soul" => 1 + @f.spare}})
  end

  test "+10 / +11 ở Máy Hỗn Nguyên chỉ bot liều" do
    p = player(%{inv: %{"jewel_bless" => 9, "jewel_soul" => 9, "jewel_chaos" => 9}})
    p = Enum.reduce(p.equip, p, fn {_s, id}, p -> if id, do: up(p, id, 9), else: p end)
    assert Brain.forge_job(p, %{seed: 1}) == nil

    assert {"chaos", %{"act" => "chaos_upgrade"}} =
             Brain.forge_job(p, %{seed: @f.daring_every})
  end

  test "Ngọc Sinh Mệnh thêm dòng cho vũ khí" do
    p = player(%{inv: %{"jewel_life" => 1}})
    assert {"shop", %{"act" => "life", "slot" => "weapon"}} = Brain.forge_job(p)
  end

  test "chưa có cánh: ép món trong túi tới +5 rồi ghép cánh cấp 1" do
    p = player(%{inv: %{"jewel_chaos" => 1, "jewel_bless" => 1}})
    p = p |> Gear.add(%{Gear.new("item_8_33") | uid: "#SAC"}) |> elem(0)
    # món đang mặc không ép được nữa (đã +11) để bot làm cánh
    p = Enum.reduce(p.equip, p, fn {_s, id}, p -> if id, do: up(p, id, 11), else: p end)
    assert {"shop", %{"act" => "upgrade", "id" => "#SAC"}} = Brain.forge_job(p)

    p = up(p, "#SAC", 5)

    assert {"chaos", %{"act" => "chaos", "id" => "wing1", "gear" => "#SAC"}} =
             Brain.forge_job(p)
  end

  test "cánh đủ cấp: tháo ra rồi ghép lên cấp (trước cả bước mặc đồ)" do
    mats = %{"jewel_bless" => 5, "jewel_soul" => 5, "jewel_chaos" => 2}
    p = player(%{inv: mats})
    p = Enum.reduce(p.equip, p, fn {_s, id}, p -> if id, do: up(p, id, 11), else: p end)
    {p, _} = Gear.add(p, %{Gear.new("wing_dk_1") | uid: "#W1"})
    {%{ok: true}, p} = Engine.equip(p, "#W1")

    # cánh ép tới +9 ở Thợ Rèn trước (cấp thấp nhất được ép trước), +10 chỉ bot liều
    p = up(p, "#W1", 9)
    assert {nil, %{"act" => "unequip", "slot" => "wing"}} = Brain.forge_job(p)

    {_, p} = Engine.unequip(p, "wing")
    # đứng cạnh Lão Hỗn Nguyên ở Làng
    %{at: {x, y}} = Enum.find(HacLong.World.Maps.get("village").npcs, &(&1.role == "chaos"))
    p = Map.put(p, :pos, %{map: "village", x: x, y: y + 1})

    assert %{"act" => "chaos", "id" => "wing2", "gear" => "#W1"} = Brain.decide(p, nil)
  end

  test "chuyển sinh: cấp tối đa; lần sau cần hạ chúa tể thì đi vùng chuyển sinh" do
    max = Data.rules().character.max_level
    p = player(%{level: max, inv: %{"potion_l" => 20, "mana_l" => 20}})
    p = %{p | hp: Engine.derived(p).maxHp}
    assert Brain.rebirth_ready?(p)
    refute Brain.rebirth_ready?(%{p | level: max - 1})

    q = Map.put(p, :rebirths, 1)
    refute Brain.rebirth_ready?(q)
    assert "realm_01" <> _ = Brain.realm_target(q)
    assert Brain.realm_target(Map.put(player(), :rebirths, 1)) == nil

    # đứng cạnh Trưởng Làng thì gửi lệnh chuyển sinh
    %{at: {x, y}} = Enum.find(HacLong.World.Maps.get("village").npcs, &(&1.role == "quests"))

    assert %{"act" => "rebirth"} =
             Brain.decide(Map.put(p, :pos, %{map: "village", x: x, y: y + 1}), nil)
  end
end

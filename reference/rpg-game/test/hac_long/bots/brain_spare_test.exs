defmodule HacLong.Bots.BrainSpareTest do
  # DECISIONS "Bot ép món dự bị, để dành ngọc ghép cánh"
  use ExUnit.Case, async: true

  alias HacLong.Bots.Brain
  alias HacLong.Game.{Engine, Gear}

  # vũ khí đầu game công 4; món dự bị công 21 (cấp 12)
  @better "item_0_3"

  defp player(attrs \\ %{}) do
    {:ok, p} = Engine.new_player("Bot", "dk")
    p = Map.merge(p, Map.merge(%{level: 50, gold: 50_000_000}, attrs))
    %{p | hp: Engine.derived(p).maxHp}
  end

  defp up(p, id, n), do: Map.put(p, :upgrades, Map.put(p[:upgrades] || %{}, id, n))

  defp up_all(p, n),
    do: Enum.reduce(p.equip, p, fn {_s, id}, p -> if id, do: up(p, id, n), else: p end)

  defp add(p, base, uid), do: p |> Gear.add(%{Gear.new(base) | uid: uid}) |> elem(0)

  test "vũ khí cũ +11, túi có vũ khí gốc mạnh hơn hẳn: ép món dự bị, không ép món đang mặc" do
    p = player(%{inv: %{"jewel_bless" => 1}}) |> up_all(11) |> add(@better, "#NEW")
    # món mới +0 chưa hơn vũ khí cũ +11 nên chưa mặc
    assert %{weapon: %{uid: "#NEW"}} = Brain.spares(p)
    assert {"shop", %{"act" => "upgrade", "id" => "#NEW"}} = Brain.forge_job(p)

    # món đang mặc thấp cấp hơn vẫn bị bỏ qua ở ô có món dự bị
    p = up(p, p.equip.weapon, 3)
    assert {"shop", %{"act" => "upgrade", "id" => "#NEW"}} = Brain.forge_job(p)
  end

  test "món dự bị ép tới hơn món đang mặc kể cả cấp ép: mặc vào" do
    p = player() |> up_all(11) |> add(@better, "#NEW")
    assert Brain.spares(p) != %{}
    p = up(p, "#NEW", 6)
    assert Brain.spares(p) == %{}
    assert %{"act" => "equip", "id" => "#NEW"} = Brain.decide(p, nil)
  end

  test "+10 / +11 món dự bị ở Máy Hỗn Nguyên chỉ bot liều" do
    # vũ khí công 21 +11 (66) giữ chỗ; rìu công 31 +9 (49) vẫn là món dự bị
    p =
      player(%{inv: %{"jewel_bless" => 9, "jewel_soul" => 9, "jewel_chaos" => 9}})
      |> add(@better, "#OLD")

    {%{ok: true}, p} = Engine.equip(p, "#OLD")
    p = p |> up_all(11) |> add("battleaxe", "#BIG") |> up("#BIG", 9)
    # có cánh rồi (không thì làm cánh trước), cánh bậc cuối +11
    {p, _} = Gear.add(p, %{Gear.new("wing_dk_3") | uid: "#W3"})
    {%{ok: true}, p} = Engine.equip(p, "#W3")
    p = up(p, "#W3", 11)
    assert %{weapon: %{uid: "#BIG"}} = Brain.spares(p)
    assert Brain.forge_job(p, %{seed: 1}) == nil

    assert {"chaos", %{"act" => "chaos_upgrade", "id" => "#BIG"}} =
             Brain.forge_job(p, %{seed: HacLong.Game.Data.rules().bots.forge.daring_every})
  end

  test "cánh đủ cấp ép để ghép bậc kế: thôi ép, để dành ngọc; cánh bậc cuối thì ép tiếp" do
    p = player(%{inv: %{"jewel_bless" => 3}}) |> up_all(11)
    {p, _} = Gear.add(p, %{Gear.new("wing_dk_1") | uid: "#W1"})
    {%{ok: true}, p} = Engine.equip(p, "#W1")

    # +4: chưa đủ +5 để ghép cánh 2, ép tiếp
    p = up(p, "#W1", 4)
    assert {"shop", %{"act" => "upgrade", "slot" => "wing"}} = Brain.forge_job(p)

    # +5 mà chưa đủ nguyên liệu ghép: không ép nữa (trước đây đổ ngọc ép lên +11 rồi ghép về +0)
    p = up(p, "#W1", 5)
    assert Brain.forge_job(p) == nil

    {_, p} = Engine.unequip(p, "wing")
    {p, _} = Gear.add(p, %{Gear.new("wing_dk_3") | uid: "#W3"})
    {%{ok: true}, p} = Engine.equip(p, "#W3")
    p = up(p, "#W3", 5)
    assert {"shop", %{"act" => "upgrade", "slot" => "wing"}} = Brain.forge_job(p)
  end

  test "dọn túi: giữ một món dự bị tốt nhất mỗi ô, bán món dự bị kém hơn và đồ cũ đã ép" do
    # dao công 7 cũng hơn 1,3 × vũ khí đầu game nhưng kém món công 21
    # có cánh rồi (chưa có thì bot giữ một món làm cánh)
    p = player() |> add("wing_dk_3", "#W3")
    {%{ok: true}, p} = Engine.equip(p, "#W3")
    p = p |> up_all(11) |> add(@better, "#A") |> add("dagger", "#B")
    assert %{weapon: %{uid: "#A"}} = Brain.spares(p)
    {best, other} = {"#A", "#B"}
    village = %{map: "village", x: 1, y: 1}
    # đủ món để bán ở Làng (trên `down_to`)
    p =
      Enum.reduce(1..21, Map.put(p, :pos, village), fn i, p ->
        p |> Gear.add(Map.merge(Gear.new(@better), %{uid: "#F#{i}", locked: true})) |> elem(0)
      end)

    assert {"shop", %{"act" => "sell", "id" => ^other}} = Brain.sell_job(p)

    # mặc món dự bị (đã ép), vũ khí cũ +11 vào túi: đồ cũ là đồ thừa
    old = p.equip.weapon
    p = up(p, best, 11)
    {%{ok: true}, p} = Engine.equip(p, best)
    p = %{p | gear: Enum.reject(p.gear, &(&1.uid == other))}
    assert {"shop", %{"act" => "sell", "id" => ^old}} = Brain.sell_job(p)
  end
end

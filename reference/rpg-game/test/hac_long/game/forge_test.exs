defmodule HacLong.Game.ForgeTest do
  @moduledoc """
  Đợt 3 (docs/INTEGRATION_PLAN.md §3, §4; FEATURE_CATALOG C10, C18, D1, D2, D3, D5, D6, D7):
  cấp nâng theo từng món, khóa đồ, ép +6 → +11 bằng ngọc, Máy Hỗn Nguyên, cánh, ngọc rơi.
  """
  use ExUnit.Case, async: true

  alias HacLong.Game.{Chaos, Engine, Gear, Rng, TradeOffer}

  setup do
    on_exit(&Rng.clear/0)
    :ok
  end

  defp player(cls \\ "dk") do
    {:ok, p} = Engine.new_player("Thử", cls)
    %{p | gold: 10_000_000, level: 40}
  end

  # vũ khí đang mặc ở cấp `up` (bản riêng)
  defp armed(p, base, up) do
    g = Gear.plain(base)
    p = %{p | equip: %{p.equip | weapon: g.uid}, gear: [g]}
    Map.put(p, :upgrades, %{g.uid => up})
  end

  defp jewels(p, n \\ 5),
    do: Enum.reduce(~w(jewel_bless jewel_soul jewel_chaos), p, &Engine.add_item(&2, &1, n))

  describe "C10 cấp nâng theo từng món" do
    test "dữ liệu cũ (cấp theo loại) tách thành từng món giữ nguyên cấp" do
      p = player() |> Map.put(:upgrades, %{"item_1_0" => 3, "broadsword" => 2, "potion_s" => 1})
      p = p |> Engine.add_item("broadsword", 2)
      q = Engine.split_upgrades(p)

      assert q.inv["broadsword"] == nil

      assert [%{base: "broadsword"} = b1, %{base: "broadsword"} = b2, %{base: "item_1_0"} = c] =
               q.gear

      assert q.equip.weapon == c.uid
      assert q.upgrades == %{c.uid => 3, b1.uid => 2, b2.uid => 2, "potion_s" => 1}
      assert Engine.derived(q).atk == Engine.derived(p).atk
      # chạy lại không đổi gì
      assert Engine.split_upgrades(q) == q
    end
  end

  describe "C18 khóa đồ" do
    test "khóa đồ thường tách bản riêng; đồ khóa không bán, không giao dịch, không vào máy" do
      p = player() |> Engine.add_item("broadsword")
      {%{ok: true}, p} = Engine.lock(p, "broadsword", true)
      assert p.inv["broadsword"] == nil
      [%{uid: uid, locked: true}] = p.gear
      assert Gear.resolve(hd(p.gear)).locked

      assert {%{ok: false, msg: msg}, _} = Engine.sell(p, uid)
      assert msg =~ "đang khóa"
      assert {:error, "Có món đang khóa." <> _} = TradeOffer.parse(p, %{"gear" => [uid]})

      # đồ đang mặc khóa tại chỗ
      {%{ok: true}, p} = Engine.lock(p, "item_1_0", true)
      assert Gear.locked?(p, p.equip.weapon)

      {%{ok: true}, p} = Engine.lock(p, uid, false)
      refute Gear.locked?(p, uid)
      assert {%{ok: true}, _} = Engine.sell(p, uid)
      assert {%{ok: false}, _} = Engine.lock(p, "potion_s", true)
    end
  end

  describe "D1 ép +6 → +11 bằng ngọc" do
    test "+5 → +6 chắc chắn bằng Ngọc Phúc Lành" do
      p = player() |> armed("greatsword", 5) |> jewels()
      {%{ok: true, upgrade: %{result: "success", level: 6}}, q} = Engine.upgrade(p, "weapon")
      assert Engine.upgrade_level(q, q.equip.weapon) == 6
      assert q.inv["jewel_bless"] == 4
    end

    test "+6 → +7: thành công có thông báo; thất bại tụt một cấp, mất ngọc" do
      p = player() |> armed("greatsword", 6) |> jewels()
      Rng.put_sequence([0.1])
      {r, q} = Engine.upgrade(p, "weapon")
      assert r.upgrade == %{result: "success", level: 7}
      assert r.announce =~ "Thử vừa ép thành công Đại Kiếm +7"

      Rng.put_sequence([0.9])
      {r, q2} = Engine.upgrade(p, "weapon")
      assert r.upgrade == %{result: "down", level: 5} and not Map.has_key?(r, :announce)
      assert Engine.upgrade_level(q2, q2.equip.weapon) == 5
      assert q2.inv["jewel_soul"] == 4 and q2.gold < p.gold
      assert Engine.upgrade_level(q, q.equip.weapon) == 7
    end

    test "+9 → +10 phải xác nhận; thất bại vỡ đồ, vũ khí về đồ khởi đầu" do
      p = player() |> armed("greatsword", 9) |> jewels()
      assert {%{ok: false, confirm: true}, ^p} = Engine.upgrade(p, "weapon")

      Rng.put_sequence([0.99])
      {r, q} = Engine.upgrade(p, "weapon", true)
      assert r.upgrade.result == "destroy" and r.msg =~ "vỡ"
      assert q.equip.weapon == "item_1_0" and q.gear == [] and q.upgrades == %{}
    end

    test "+10, +11 tính gấp đôi; +11 là tối đa" do
      assert Engine.effective_level(9) == 9
      assert Engine.effective_level(10) == 11
      assert Engine.effective_level(11) == 13

      p = player() |> armed("greatsword", 11) |> jewels()
      assert {%{ok: false, msg: "Đại Kiếm đã nâng cấp tối đa."}, _} = Engine.upgrade(p, "weapon")
      # Đại Kiếm tấn công 44: mỗi cấp round(44 × 0,08) = 4
      assert Engine.upgrade_bonus(p, p.equip.weapon) == 13 * 4
    end
  end

  describe "D6 cánh" do
    test "đúng lớp, đủ cấp mới mặc; tăng sát thương, giảm sát thương nhận; tháo được" do
      p = player()
      w = Gear.plain("wing_dk_1")
      wk = Gear.plain("wing_mg_1")
      p = %{p | gear: [w, wk]}
      assert {%{ok: false, msg: "Cần cấp 20."}, _} = Engine.equip(%{p | level: 10}, w.uid)
      assert {%{ok: false, msg: msg}, _} = Engine.equip(p, wk.uid)
      assert msg =~ "Đấu Sĩ"

      base = Engine.derived(p)
      {%{ok: true}, q} = Engine.equip(p, w.uid)
      d = Engine.derived(q)
      assert d.wingDmg == 0.1 and d.wingAbsorb == 0.1 and d.def == base.def + 6
      assert Engine.look(q).wing == %{cls: "dk", tier: 1}

      # mỗi cấp nâng +2 %
      d5 = Engine.derived(Map.put(q, :upgrades, %{w.uid => 5}))
      assert d5.wingDmg == 0.2 and d5.wingAbsorb == 0.2

      {%{ok: true}, q} = Engine.unequip(q, "wing")
      assert q.equip.wing == nil and Engine.derived(q) == base
    end
  end

  describe "D5 Máy Hỗn Nguyên" do
    defp wing_input(p, up) do
      g = Gear.plain("greatsword")
      p = %{p | gear: [g]} |> Map.put(:upgrades, %{g.uid => up}) |> jewels()
      {p, g.uid}
    end

    test "tỉ lệ theo cấp đồ, tối đa 60 %" do
      r = HacLong.Game.Data.chaos("wing1")
      assert Chaos.rate(r, 5) == 0.1
      assert Chaos.rate(r, 9) == 0.3
      assert Chaos.rate(r, 20) == 0.6
      assert Chaos.rate(HacLong.Game.Data.chaos("make_chaos")) == 0.7
    end

    test "thành công: ra cánh đúng lớp, báo cả server; thất bại mất hết" do
      {p, uid} = wing_input(player("elf"), 7)
      Rng.put_sequence([0.0])
      {r, q} = Chaos.combine(p, "wing1", uid)
      assert r.chaos == %{result: "success", out: "wing_elf_1"}
      assert r.announce =~ "Cánh Tiên"
      assert [%{base: "wing_elf_1", rarity: 0}] = q.gear
      assert q.gold == p.gold - 20_000 and q.inv["jewel_chaos"] == 4

      Rng.put_sequence([0.99])
      {r, q} = Chaos.combine(p, "wing1", uid)
      assert r.chaos.result == "fail" and q.gear == [] and q.upgrades == %{}
      assert q.gold == p.gold - 20_000
    end

    test "đồ chưa đủ +5, đang mặc, đang khóa, sai loại thì không nhận" do
      {p, uid} = wing_input(player(), 4)

      assert {%{ok: false, msg: "Đại Kiếm cần nâng tới +5 trở lên."}, _} =
               Chaos.combine(p, "wing1", uid)

      {p, uid} = wing_input(player(), 6)
      locked = Gear.set_locked(p, uid, true)
      assert {%{ok: false, msg: m}, _} = Chaos.combine(locked, "wing1", uid)
      assert m =~ "đang khóa"

      worn = %{p | equip: %{p.equip | weapon: uid}}

      assert {%{ok: false, msg: "Tháo Đại Kiếm ra trước đã."}, _} =
               Chaos.combine(worn, "wing1", uid)

      assert {%{ok: false}, _} = Chaos.combine(p, "wing2", uid)

      assert {%{ok: false, msg: "Chọn một món đồ để bỏ vào máy."}, _} =
               Chaos.combine(p, "wing1", nil)
    end

    test "công thức không cần đồ: Ngọc Hỗn Nguyên từ Mithril + Vảy Cổ Long" do
      p = player() |> Engine.add_item("ore_rare", 10) |> Engine.add_item("dragon_scale")
      Rng.put_sequence([0.5])
      {%{ok: true, chaos: %{result: "success"}}, q} = Chaos.combine(p, "make_chaos", nil)
      assert q.inv["jewel_chaos"] == 1 and q.inv["ore_rare"] == nil

      assert {%{ok: false, msg: "Thiếu nguyên liệu: " <> _}, _} =
               Chaos.combine(q, "make_chaos", nil)
    end
  end

  describe "D7 ngọc rơi" do
    test "chọn ngọc theo trọng số" do
      Rng.put_sequence([0.0])
      assert Engine.pick_jewel() == "jewel_bless"
      Rng.put_sequence([0.99])
      assert Engine.pick_jewel() == "jewel_soul"
    end
  end
end

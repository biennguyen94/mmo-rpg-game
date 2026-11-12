defmodule HacLong.Game.KiteTest do
  @moduledoc "DECISIONS \"Đồi Sáo Diều, Chim Lạc, Hắc Long\": thả diều, Chim Lạc, Đàn Hạc, Ông Lão, Sáo Đồng, lễ, ấp trứng."
  use ExUnit.Case, async: true

  alias HacLong.Game.{DragonEgg, Engine, Kite, Pets, Rng}
  alias HacLong.World.Maps

  setup do
    on_exit(&Rng.clear/0)
  end

  @map Kite.map_id()

  # ô đứng ở mép đồi cạnh trời và một ô trời trong tầm
  defp spot do
    m = Maps.get(@map)

    stand =
      Enum.find(
        for(y <- 0..(m.height - 1), x <- 0..(m.width - 1), do: {x, y}),
        fn {x, y} ->
          Maps.walkable?(m, x, y) and
            Enum.any?([{1, 0}, {-1, 0}, {0, 1}, {0, -1}], fn {dx, dy} ->
              Maps.sky?(m, x + dx, y + dy)
            end)
        end
      )

    {sx, sy} = stand

    sky =
      Enum.find(for(dy <- -1..-3//-1, dx <- -2..2, do: {sx + dx, sy + dy}), fn {x, y} ->
        Maps.sky?(m, x, y)
      end)

    {stand, sky}
  end

  defp flyer(at) do
    {:ok, p} = Engine.new_player("Thả Diều", "elf")
    {x, y} = at
    p |> Map.put(:pos, %{map: @map, x: x, y: y}) |> Map.put(:daily, %{})
  end

  test "thả diều ở chỗ thoáng bất kỳ, dây không giới hạn; mặc định lên giữa trời (không sát người); vướng cây thì không" do
    {stand, sky} = spot()
    assert sky != nil
    assert Kite.can_fly?(flyer(stand))
    m = Maps.get(@map)
    aim = Kite.rules().aim
    [lo, hi] = aim.rise

    # cuối đồi (xa mép trời) vẫn thả được; chạm ô trời xa tít (góc trên cùng) cũng được
    far = flyer({11, 16})
    assert Kite.check_spot(far) == :ok
    assert {%{ok: true, at: [0, 0]}, _} = Kite.fly(far, 0, {0, 0})

    # bấm nút (không chọn ô): lên giữa trời, cao hơn mép trời rise ô, cột lệch ≤ spread, không cách người quá view hàng
    for {x, y} = at <- [stand, {11, 16}, {13, 10}], now <- [0, 1, 2, 3, 4, 5] do
      {%{ok: true, at: [ax, ay]}, _} = Kite.fly(flyer(at), now)
      e = Kite.edge(m, ax)
      assert Maps.sky?(m, ax, ay) and abs(ax - x) <= aim.spread
      assert ay <= e and ((e - ay) in lo..hi or ay == y - aim.view or ay == e)
      assert y - ay >= 2, "diều không sát người: #{inspect({at, ax, ay})}"
    end

    # sát cây (viền cây bên trái)
    assert {:error, "Vướng cây" <> _} = Kite.check_spot(flyer({1, 10}))
    # ô không phải trời
    assert {%{ok: false, msg: "Chạm vào khoảng trời" <> _}, _} =
             Kite.fly(flyer(stand), 0, {5, 15})

    # khác bản đồ
    assert {:error, "Thả diều ở Đồi Sáo Diều" <> _} =
             Kite.check_spot(%{pos: %{map: "village", x: 10, y: 10}})
  end

  test "giữ dây đúng lúc gió giật thì được quà gió, +1 Phong Khí, tính việc Ông Lão; sớm / muộn thì hỏng" do
    {stand, sky} = spot()
    Rng.put_sequence([0.5, 0.0])
    {%{ok: true, wait: 5500}, p} = Kite.fly(flyer(stand), 1_000, sky)
    assert {%{ok: false, msg: "Giật dây sớm" <> _}, _} = Kite.hold(p, 6_000)
    assert {%{ok: false, msg: "Chậm tay" <> _}, _} = Kite.hold(p, 7_700)
    assert {%{ok: true, gift: "long_hac"}, p2} = Kite.hold(p, 6_900)
    assert p2.inv["long_hac"] == 1
    assert Kite.phong_khi(p2) == 1
    assert p2.daily.kite_n == 1
  end

  test "thả trúng ô Chim Lạc: Sáo Đồng tốn 1, cơ hội theo Phong Khí; giữ đúng lúc thì được thú Chim Lạc, Phong Khí về 0" do
    {stand, sky} = spot()
    p = flyer(stand) |> Engine.add_item("sao_dong") |> Kite.add_phong_khi(100)
    assert_in_delta Kite.bird_chance(p, true), Kite.rules().bird.chance * 2 * 2, 1.0e-9
    Rng.put_sequence([0.0, 0.0])
    {%{ok: true, big: true}, p} = Kite.fly(p, 0, sky, sky, nil)
    refute Map.has_key?(p.inv, "sao_dong")
    {r, p} = Kite.hold(p, Kite.rules().wait_ms |> hd())
    assert r.rare_pet == "chim_lac"
    assert "chim_lac" in p.pets and Kite.phong_khi(p) == 0

    # đã có: con mới vào túi dạng Ấn (DECISIONS "Thú thành vật phẩm")
    {r2, p2} = Kite.land_bird(p)
    assert r2.rare_pet == "chim_lac" and p2.pets == p.pets
    assert [%{base: "seal_chim_lac", xp: 0}] = Enum.filter(p2.gear, &(&1.base == "seal_chim_lac"))
  end

  test "Đàn Hạc: quà theo bảng riêng, +3 Phong Khí; Ông Lão: đủ lượt thì thưởng một lần; ghép Sáo Đồng" do
    {stand, sky} = spot()
    Rng.put_sequence([0.0, 0.0])
    {%{flock: true}, p} = Kite.fly(flyer(stand), 0, sky, nil, sky)
    {%{ok: true}, p} = Kite.hold(p, 3_000)
    assert Kite.phong_khi(p) == Kite.rules().flock.phong_khi

    assert {%{ok: false}, _} = Kite.claim_elder(p)
    full = put_in(p, [:daily, :kite_n], Kite.rules().elder.count)
    {%{ok: true}, got} = Kite.claim_elder(full)
    assert got.gold > p.gold
    assert {%{ok: false, msg: "Hôm nay lão trả công rồi" <> _}, _} = Kite.claim_elder(got)

    assert {%{ok: false}, _} = Kite.craft(p)
    rich = p |> Engine.add_item("manh_sao", 2) |> Engine.add_item("long_hac", 5)
    {%{ok: true}, made} = Kite.craft(rich)
    assert made.inv["sao_dong"] == 1 and made.inv["manh_sao"] in [nil, 0]
  end

  test "đọc / ghi cột sky" do
    assert Kite.load(nil) == %{phong_khi: 0, egg: nil, lucky: nil}

    s =
      Kite.load(%{
        "phong_khi" => 7,
        "egg" => %{"at" => 10, "kills" => 3, "boss" => true},
        "lucky" => 5
      })

    assert s == %{phong_khi: 7, egg: %{at: 10, kills: 3, boss: true}, lucky: 5}
  end

  # ---------- Hắc Long ----------

  defp ready_player do
    {:ok, p} = Engine.new_player("Rồng Tiên", "dk")
    max = Pets.xp_for(30)

    p
    |> Map.merge(%{
      pets: ["long_vuong", "chim_lac"],
      pet_xp: %{"long_vuong" => max, "chim_lac" => max},
      long_khi: 200,
      victory: true,
      pos: %{map: "altar", x: 10, y: 10},
      kills: 1000
    })
    |> Kite.add_phong_khi(200)
  end

  # Bọc Trăm Trứng còn lại từ trước (Long Phượng Hội đã bỏ): đặt thẳng vào nhân vật
  defp with_egg(p) do
    p
    |> Kite.put_sky(&%{&1 | egg: %{at: 0, kills: p.kills, boss: false}})
    |> HacLong.Game.Engine.add_item("boc_tram_trung")
  end

  test "ấp trứng: nở khi đủ quái, đủ ngày hoặc hạ Hắc Long; 10% ra Chân Thân" do
    p = with_egg(ready_player())
    assert {%{ok: false, msg: "Trứng chưa nở" <> _}, _} = DragonEgg.hatch(p, 3600)

    by_kills = %{p | kills: p.kills + DragonEgg.egg_rules().kills}
    Rng.put_sequence([0.5])
    {%{ok: true, rare_pet: "hac_long"}, h} = DragonEgg.hatch(by_kills, 3600)

    assert "hac_long" in h.pets and DragonEgg.egg(h) == nil and
             h.inv["boc_tram_trung"] in [nil, 0]

    assert "đã có Hắc Long" in DragonEgg.missing(h)

    Rng.put_sequence([0.0])
    {%{rare_pet: "hac_long_chan"}, _} = DragonEgg.hatch(p, DragonEgg.egg_rules().days * 86_400)

    boss = DragonEgg.on_final_win(p)
    assert DragonEgg.progress(boss, 0).ready
  end

  test "Hắc Long cộng chỉ số (có né), Long Huyết đánh Hắc Long / hệ Bóng Tối mạnh hơn" do
    {:ok, p} = Engine.new_player("Thử", "dk")
    p = Map.merge(p, %{pets: ["hac_long"], pet: "hac_long"})
    base = Engine.derived(Map.put(p, :pet, nil))
    d = Engine.derived(p)
    assert d.dodge > base.dodge and d.atk > base.atk
    assert Pets.trait(p, :slayer) == 0.1

    # dắt Hắc Long đánh trùm cuối: thoại riêng
    m =
      Engine.make_monster(%{id: "hac_long_boss", name: "Hắc Long", level: 35, final: true}, true)

    {_, b} = Engine.start_with_monster(Map.put(p, :hp, 100), 5, Map.put(m, :hp, m.maxHp))
    assert Enum.any?(b.battle.log, &(&1.text =~ "Đồng tộc phản bội"))

    {_, plain} =
      Engine.start_with_monster(%{p | pet: nil} |> Map.put(:hp, 100), 5, Map.put(m, :hp, m.maxHp))

    refute Enum.any?(plain.battle.log, &(&1.text =~ "Đồng tộc"))
  end
end

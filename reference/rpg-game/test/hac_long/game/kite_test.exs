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

  test "bản đồ có ô trời; phải đứng cạnh trời mới thả được" do
    {stand, sky} = spot()
    assert sky != nil
    assert Kite.near_sky?(flyer(stand))
    far = flyer({13, 15})
    refute Kite.near_sky?(far)
    assert {%{ok: false}, _} = Kite.fly(far, 0)
    # ô xa quá / không phải trời
    assert {%{ok: false, msg: "Ô đó xa quá" <> _}, _} = Kite.fly(flyer(stand), 0, {0, 19})
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

    # đã có: được Mảnh Sao
    {r2, p2} = Kite.land_bird(p)
    refute Map.has_key?(r2, :rare_pet)
    assert p2.inv["manh_sao"] == Kite.rules().bird.dupe_n
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

  @hoi %{id: 1, at: {10, 10}}

  test "Long Phượng Hội: đủ điều kiện thì nhận Bọc Trăm Trứng (mất Long Khí, Phong Khí); thiếu thì hưởng lộc một lần" do
    p = ready_player()
    assert DragonEgg.missing(p) == []
    assert {%{ok: false}, _} = DragonEgg.ritual(p, nil, 0)

    assert {%{ok: false, msg: "Hãy bước vào vòng sáng" <> _}, _} =
             DragonEgg.ritual(%{p | pos: %{p.pos | x: 1}}, @hoi, 0)

    {%{ok: true, egg: true}, q} = DragonEgg.ritual(p, @hoi, 100)
    assert q.inv["boc_tram_trung"] == 1 and q.long_khi == 0 and Kite.phong_khi(q) == 0
    assert DragonEgg.egg(q) == %{at: 100, kills: 1000, boss: false}

    poor = %{ready_player() | long_khi: 0}
    assert "Long Khí chưa đầy (0/200)" in DragonEgg.missing(poor)
    {%{ok: true}, lucky} = DragonEgg.ritual(poor, @hoi, 0)
    assert lucky.long_khi == DragonEgg.hoi_rules().lucky_qi
    assert {%{ok: false, msg: "Bạn đã hưởng lộc" <> _}, _} = DragonEgg.ritual(lucky, @hoi, 0)
  end

  test "ấp trứng: nở khi đủ quái, đủ ngày hoặc hạ Hắc Long; 10% ra Chân Thân" do
    {_, p} = DragonEgg.ritual(ready_player(), @hoi, 0)
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
  end
end

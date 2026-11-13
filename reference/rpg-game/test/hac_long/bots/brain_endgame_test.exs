defmodule HacLong.Bots.BrainEndgameTest do
  # DECISIONS "Bot cuối game": tránh chỗ vừa gục nhiều (phòng trùm, bản đồ quá mạnh), CS tối đa luyện ở vùng chuyển sinh,
  # dọn túi ở Thợ Rèn, cho thú ăn từ từ
  use ExUnit.Case, async: true

  alias HacLong.Bots.Brain
  alias HacLong.Game.{Data, Engine, Gear}
  alias HacLong.World.Maps

  @play Data.rules().bots.play
  @sell Data.rules().bots.sell
  @char Data.rules().character

  defp player(attrs \\ %{}) do
    {:ok, p} = Engine.new_player("Bot", "dk")

    p =
      Map.merge(
        p,
        Map.merge(%{level: 30, gold: 10_000_000, pos: %{map: "forest_1", x: 1, y: 1}}, attrs)
      )

    %{p | hp: Engine.derived(p).maxHp}
  end

  describe "gục nhiều ở một chỗ thì tạm tránh" do
    test "gục `avoid.deaths` lần trong `window_min` phút: tránh `hours` giờ rồi thử lại" do
      st = %{fails: %{}, avoid: %{}}
      min = 60_000
      t0 = 1_000_000

      st =
        Enum.reduce(1..(@play.avoid.deaths - 1), st, fn i, st ->
          Brain.note_death(st, "lair_boss", t0 + i * min)
        end)

      assert Brain.avoiding(st, t0 + 10 * min) == []

      st = Brain.note_death(st, "lair_boss", t0 + 10 * min)
      assert Brain.avoiding(st, t0 + 11 * min) == ["lair_boss"]
      # hết giờ tránh: đi lại
      assert Brain.avoiding(st, t0 + 10 * min + round(@play.avoid.hours * 60) * min + 1) == []
    end

    test "các lần gục cách nhau quá `window_min` phút không cộng dồn" do
      gap = (@play.avoid.window_min + 1) * 60_000

      st =
        Enum.reduce(1..(@play.avoid.deaths + 2), %{fails: %{}, avoid: %{}}, fn i, st ->
          Brain.note_death(st, "swamp_boss", i * gap)
        end)

      assert Brain.avoiding(st, 100 * gap) == []
    end

    test "phòng trùm đang tránh: không vào, đi luyện bản đồ thường (trước đây gục mãi ở phòng trùm)" do
      p = player(%{level: 7, inv: %{"potion_l" => 20}})
      assert Brain.boss_room(p) == "forest_boss"
      assert Brain.boss_room(p, ["forest_boss"]) == nil
    end
  end

  describe "chuyển sinh tối đa, cấp tối đa: luyện ở vùng chuyển sinh" do
    defp maxed do
      p = player(%{level: @char.max_level, inv: %{"potion_l" => 20, "mana_l" => 20}})
      Map.put(p, :rebirths, @char.max_rebirths)
    end

    defp realm_maps do
      Maps.ids()
      |> Enum.map(&Maps.get/1)
      |> Enum.filter(&is_integer(&1.realm))
      |> Enum.sort_by(&{&1.realm, &1.id})
    end

    defp killed(p, m),
      do:
        Map.put(
          p,
          :bestiary,
          Map.merge(p[:bestiary] || %{}, Map.new(m.spawns, &{&1.monster, 999}))
        )

    test "quá mốc 10: cần hạ lại chúa tể vùng cuối thì đi các bản đồ vùng cuối lần lượt; bản đồ vừa gục nhiều thì lùi lại" do
      p = maxed()

      # DECISIONS "Bot chuyển sinh quá 10, chọn vùng theo thang": bot chuyển sinh tiếp như người
      assert %{realm: r} = Engine.rebirth_need(p)
      assert r == @char.max_rebirths
      [m1, m2, m3 | _] = Enum.filter(realm_maps(), &(&1.realm == r))
      assert Brain.realm_target(p) == m1.id

      p = p |> killed(m1) |> killed(m2)
      assert Brain.realm_target(p) == m3.id
      assert Brain.realm_target(p, [m3.id]) == m2.id

      # bản đồ đầu vùng chúa tể cũng đang tránh: lùi về vùng hợp sức thấp hơn (không về bản đồ thường)
      assert Maps.get(Brain.realm_target(maxed(), [m1.id])).realm == r - 1
    end

    test "chuyển sinh quá 10 tới trần của bot; hết lượt trong ngày thì thôi" do
      lord = Engine.rebirth_need(maxed())
      p = maxed() |> Map.put(:bestiary, %{lord.id => 99})
      assert Brain.rebirth_ready?(p)
      cap = Data.rules().bots.max_rebirths
      refute Brain.rebirth_ready?(Map.put(p, :rebirths, cap))
      today = HacLong.Game.Daily.today()

      refute Brain.rebirth_ready?(
               Map.put(p, :daily, %{date: today, rebirths: @char.rebirth_per_day})
             )
    end

    test "chọn vùng hợp sức theo thang vùng co giãn" do
      base = Enum.to_list(1..10)
      assert Brain.ladder_realm(Map.put(maxed(), :rebirths, 25), base) == 10
      assert Brain.ladder_realm(Map.put(maxed(), :rebirths, 3), base) == 3
      ks = [10, 12, 14, 17, 19, 21, 23, 26, 28, 30]
      # CS 18: vùng cao nhất có mức ≤ 18 + ladder_margin
      assert Brain.ladder_realm(Map.put(maxed(), :rebirths, 18), ks) ==
               5 - if(Data.rules().bots.ladder_margin >= 1, do: 0, else: 1)

      assert Brain.ladder_realm(Map.put(maxed(), :rebirths, 30), ks) == 10
      assert Brain.ladder_realm(Map.put(maxed(), :rebirths, 9), ks) == 1
      # tới trần bot (không chuyển sinh nữa): luyện ở vùng hợp sức
      p = maxed() |> Map.put(:rebirths, Data.rules().bots.max_rebirths)
      assert Maps.get(Brain.realm_target(p)).realm == Brain.ladder_realm(p)
    end

    test "chưa chuyển sinh tối đa mà không cần hạ chúa tể: không đi vùng chuyển sinh" do
      assert Brain.realm_target(Map.put(maxed(), :rebirths, 0)) == nil
    end
  end

  describe "dọn túi" do
    # túi `n` món đồ trắng kém hơn đồ đang mặc (cùng loại giáp)
    defp junk_bag(p, n) do
      base = Gear.find(p, p.equip.armor).base

      Enum.reduce(1..n, p, fn i, p ->
        {p, _} = Gear.add(p, %{Gear.new(base) | uid: "#J#{i}"})
        p
      end)
    end

    test "túi gần đầy: bán đồ thừa ở Thợ Rèn; đồ khóa / đã ép / Excellent thì giữ" do
      p = junk_bag(player(), @sell.full_at)
      p = Map.put(p, :upgrades, Map.put(p[:upgrades] || %{}, "#J1", 3))
      assert {"shop", %{"act" => "sell", "id" => id}} = Brain.sell_job(p)
      refute id == "#J1"

      # còn lại chỉ món đã ép (#J1) và món Excellent (#J2), mọi món khác khóa: không bán gì
      only =
        Map.update!(p, :gear, fn gs ->
          Enum.map(gs, fn
            %{uid: "#J1"} = g -> g
            %{uid: "#J2"} = g -> Map.put(g, :exc, ["crit"])
            g -> Map.put(g, :locked, true)
          end)
        end)

      assert Brain.sell_job(only) == nil

      # ít đồ, đang luyện ngoài Làng: không về bán
      assert Brain.sell_job(junk_bag(player(), @sell.down_to + 2)) == nil
      # đang ở Làng: bán tới còn `down_to` món
      q = junk_bag(player(), @sell.down_to + 2) |> Map.put(:pos, %{map: "village", x: 20, y: 8})
      assert {"shop", %{"act" => "sell"}} = Brain.sell_job(q)

      assert Brain.sell_job(
               junk_bag(player(), @sell.down_to)
               |> Map.put(:pos, %{map: "village", x: 20, y: 8})
             ) == nil
    end

    test "chỉ toàn đồ khóa: không bán gì" do
      p = junk_bag(player(), @sell.full_at)
      p = %{p | gear: Enum.map(p.gear, &Map.put(&1, :locked, true))}
      assert Brain.sell_job(p) == nil
    end
  end

  test "cho thú ăn từ từ: chỉ khi tới lượt (`feed_due`)" do
    # có hết thú thường (không còn con nào để mua), đang dắt con mạnh nhất
    pets = for pt <- Data.pets(), !pt[:rare], do: pt.id
    p = player(%{pets: pets})
    p = Map.put(p, :pet, Enum.max_by(pets, &HacLong.Game.Pets.power(p, &1)))
    # vàng vừa đủ cho ăn, chưa đủ mua thú mạnh hơn
    keep = Data.rules().bots.forge.gold_keep_per_level * p.level
    p = %{p | gold: keep + HacLong.Game.Pets.feed_cost(p) * @play.feed_mult + 1}
    assert {"pets", %{"act" => "pet_feed"}} = Brain.pet_job(p, %{feed_due: true})
    assert Brain.pet_job(p, %{feed_due: false}) == nil
  end

  describe "dùng ngọc khôn hơn" do
    defp up(p, id, n), do: Map.put(p, :upgrades, Map.put(p[:upgrades] || %{}, id, n))

    test "món đang mặc đã ép không bị thay bằng món +0 chỉ nhỉnh hơn chút (trước đây mất trắng ngọc)" do
      p = player()
      worn = Gear.find(p, p.equip.armor)

      # cùng loại, thêm 1 dòng cộng thêm: hơn món đang mặc +0
      {p, _} = Gear.add(p, %{Gear.new(worn.base) | uid: "#NEW"} |> Map.put(:opt, 1))
      assert %{"act" => "equip", "id" => "#NEW"} = Brain.decide(p, nil)

      # món đang mặc +5: giữ
      refute match?(
               %{"act" => "equip", "id" => "#NEW"},
               Brain.decide(up(p, p.equip.armor, 5), nil)
             )
    end

    test "dồn Ngọc Ước Nguyện vào vũ khí / giáp / cánh / khiên trước các ô khác" do
      p = player(%{inv: %{"jewel_bless" => 1}})
      p = Enum.reduce(p.equip, p, fn {_s, id}, p -> if id, do: up(p, id, 2), else: p end)
      # mọi món +2: ép vũ khí / giáp trước mũ, giày…
      assert {"shop", %{"act" => "upgrade", "slot" => slot}} = Brain.forge_job(p)
      assert slot in Data.rules().bots.forge.focus_slots

      # món đáng giá đã hơn các ô khác `focus_lead` cấp: tới lượt ô khác
      lead = Data.rules().bots.forge.focus_lead
      q = Enum.reduce([:weapon, :armor], p, fn s, q -> up(q, q.equip[s], 2 + lead + 1) end)
      assert {"shop", %{"act" => "upgrade", "slot" => other}} = Brain.forge_job(q)
      refute other in ["weapon", "armor"]
    end
  end
end

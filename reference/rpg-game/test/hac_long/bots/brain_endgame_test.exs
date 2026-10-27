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

    test "bắt đầu từ bản đồ dễ nhất; hạ đủ quái thì sang bản đồ sau; bản đồ vừa gục nhiều thì lùi lại" do
      p = maxed()
      assert Engine.rebirth_need(p) == nil
      [m1, m2, m3 | _] = realm_maps()
      assert Brain.realm_target(p) == m1.id

      p = p |> killed(m1) |> killed(m2)
      assert Brain.realm_target(p) == m3.id
      assert Brain.realm_target(p, [m3.id]) == m2.id
      # bản đồ đầu tiên cũng đang tránh: luyện bản đồ thường
      assert Brain.realm_target(maxed(), [m1.id]) == nil
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
end

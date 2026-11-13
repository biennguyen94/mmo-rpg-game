defmodule HacLong.Bots.BrainHacTest do
  # DECISIONS "Bot ưu tiên rèn đồ, săn Hắc Long"
  use ExUnit.Case, async: true

  alias HacLong.Bots.Brain
  alias HacLong.Game.{Data, Engine, Pets}

  @f Data.rules().bots.forge
  @hac Data.rules().bots.hac
  @lv "long_vuong"
  @cl "chim_lac"

  defp player(attrs \\ %{}) do
    {:ok, p} = Engine.new_player("Bot", "dk")

    p =
      Map.merge(
        p,
        Map.merge(
          %{
            level: 50,
            gold: 50_000_000,
            rebirths: @hac.min_rebirths,
            pos: %{map: "forest_1", x: 1, y: 1}
          },
          attrs
        )
      )

    %{p | hp: Engine.derived(p).maxHp}
  end

  defp up(p, id, n), do: Map.put(p, :upgrades, Map.put(p[:upgrades] || %{}, id, n))

  defp maxed(p, id),
    do:
      put_in(
        p,
        [Access.key(:pet_xp, %{})],
        Map.put(p[:pet_xp] || %{}, id, Pets.xp_for(Pets.max_level(id)))
      )

  describe "rèn đồ ưu tiên" do
    test "đủ điều kiện chuyển sinh mà có ngọc, dư vàng: ép đồ trước" do
      p = player(%{inv: %{"jewel_bless" => 1, "potion_l" => 50, "mana_l" => 50}, rebirths: 0})
      assert Brain.rebirth_ready?(%{p | level: Data.rules().character.max_level})
      p = %{p | level: Data.rules().character.max_level}
      p = %{p | hp: Engine.derived(p).maxHp}
      # đứng cạnh Thợ Rèn ở Làng: ép trước, chưa đi chuyển sinh
      %{at: {x, y}} = Enum.find(HacLong.World.Maps.get("village").npcs, &(&1.role == "shop"))
      p = %{p | pos: %{map: "village", x: x, y: y + 1}}
      assert %{"act" => "upgrade"} = Brain.decide(p, nil)
      # hết ngọc: chuyển sinh
      assert Brain.forge_job(%{p | inv: %{"potion_l" => 50, "mana_l" => 50}}) == nil
      assert {"shop", %{"act" => "upgrade"}} = Brain.forge_job(p)
    end

    test "từ `chaos_from_rebirths` lần chuyển sinh, bot nào cũng ép +10 / +11 ở Máy Hỗn Nguyên" do
      p =
        player(%{inv: %{"jewel_bless" => 9, "jewel_soul" => 9, "jewel_chaos" => 9}, rebirths: 0})

      p = Enum.reduce(p.equip, p, fn {_s, id}, p -> if id, do: up(p, id, 9), else: p end)
      assert Brain.forge_job(p, %{seed: 1}) == nil

      assert {"chaos", %{"act" => "chaos_upgrade"}} =
               Brain.forge_job(%{p | rebirths: @f.chaos_from_rebirths}, %{seed: 1})
    end
  end

  describe "săn Hắc Long" do
    test "bot săn: từ min_rebirths, chưa có Hắc Long" do
      assert Brain.hac_seeker?(player())
      if @hac.min_rebirths > 0, do: refute(Brain.hac_seeker?(player(%{rebirths: 0})))
      refute Brain.hac_seeker?(player(%{pets: ["hac_long"]}))
      refute Brain.hac_seeker?(player(%{pets: ["hac_long_chan"]}))
    end

    test "Long Vương nổi: bot săn Hắc Long nào cũng đi (không chỉ bot săn rồng)" do
      p = player()
      opts = %{dragon: {5, 5}, seed: 2}
      refute Brain.chaser?(2)
      assert Brain.chasing?(p, opts)
      refute Brain.chasing?(%{p | rebirths: 0} |> Map.put(:pets, ["hac_long"]), opts)
    end

    test "Chim Lạc lượn: bot săn Hắc Long ra đồi" do
      p = player()
      assert Brain.bird_chasing?(p, %{bird: {3, 1}})
      refute Brain.bird_chasing?(Map.put(p, :pets, [@cl]), %{bird: {3, 1}})
      refute Brain.bird_chasing?(p, %{})
      # việc :chase đưa bot đi về phía Đồi Sáo Diều
      assert Brain.fish_job(p, nil, %{bird: {3, 1}, seed: 2}, :chase) != nil
    end

    test "dắt Long Vương / Chim Lạc chưa cấp tối đa thay con mạnh nhất, cho ăn rộng tay hơn" do
      p = player(%{pets: ["daemon", @lv, @cl], pet: "daemon"})
      assert Brain.hac_lead(p) == @lv
      assert {nil, %{"act" => "pet_choose", "id" => @lv}} = Brain.pet_job(p)

      p = %{p | pet: @lv}
      feed = Pets.feed_cost(p)

      rich = %{
        p
        | gold:
            Data.rules().bots.forge.gold_keep_per_level * p.level + feed * (@hac.feed_mult + 1)
      }

      assert {"pets", %{"act" => "pet_feed"}} = Brain.pet_job(rich)

      # Long Vương cấp tối đa: sang Chim Lạc
      p = maxed(p, @lv)
      assert Brain.hac_lead(p) == @cl
      assert {nil, %{"act" => "pet_choose", "id" => @cl}} = Brain.pet_job(p)
    end

    test "đủ hai con cấp tối đa: về Lão Hỗn Nguyên ghép Hắc Long" do
      p = player(%{pets: [@lv, @cl], pet: @lv}) |> maxed(@lv) |> maxed(@cl)
      assert Brain.hac_lead(p) == nil
      assert {"chaos", %{"act" => "hac_combine"}} = Brain.hac_job(p)
      refute Brain.hac_job(maxed(player(%{pets: [@lv]}), @lv))

      %{at: {x, y}} = Enum.find(HacLong.World.Maps.get("village").npcs, &(&1.role == "chaos"))

      # dưới cấp tối đa: không đi chuyển sinh trước; hết vàng: không mua vé sự kiện đang mở (tùy giờ chạy test)
      p = %{
        p
        | level: 45,
          gold: 0,
          pos: %{map: "village", x: x, y: y + 1},
          inv: %{"potion_l" => 50, "mana_l" => 50}
      }

      assert %{"act" => "hac_combine"} = Brain.decide(p, nil)

      {%{ok: true}, p2} = HacLong.Game.DragonEgg.combine(p)
      refute Brain.hac_seeker?(p2)
    end
  end
end

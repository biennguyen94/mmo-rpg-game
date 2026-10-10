defmodule HacLong.Game.DataRulesTest do
  # Phase 1: dữ liệu tách file, RULES, kiểm dữ liệu lúc biên dịch, từ cấm, vị trí lưu hỏng.
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, DataCheck, Engine, Names}
  alias HacLong.World
  alias HacLong.World.Maps

  describe "dữ liệu tách file (priv/game_data/)" do
    test "mỗi khóa lớn nằm ở đúng một file, ghép lại đủ cả" do
      files = Path.wildcard(Application.app_dir(:hac_long, "priv/game_data/*.json"))

      keys =
        Enum.flat_map(files, fn f -> f |> File.read!() |> Jason.decode!() |> Map.keys() end)

      assert Enum.sort(keys) ==
               ~w(BOSS_DROPS CHAOS CLASSES EVENTS FURNITURE ITEMS ITEM_PICK JEWELS PETS QUESTS RECIPES RULES SHOP SIDE_MONSTERS UPGRADE ZONES)

      assert map_size(Data.classes()) == 4
      assert Data.item("potion_s").heal_pct > 0
      assert Data.item("mana_s").mana_pct > 0
      assert Data.rules().character.max_level == Engine.max_level()
    end

    test "dữ liệu hiện tại không có lỗi tham chiếu" do
      assert DataCheck.errors(Data.check_input()) == []
    end
  end

  describe "kiểm dữ liệu (J2)" do
    setup do
      %{d: Data.check_input()}
    end

    test "món trong cửa hàng không có → lỗi có tên file và id", %{d: d} do
      d = %{d | shop: d.shop ++ ["kiem_go_nham"]}
      assert [msg] = DataCheck.errors(d)
      assert msg =~ "shop.json" and msg =~ "kiem_go_nham"
      assert_raise CompileError, ~r/kiem_go_nham/, fn -> DataCheck.run!(d) end
    end

    test "công thức, rơi trùm, nhiệm vụ, máy ghép trỏ tới món không có", %{d: d} do
      [r | rs] = d.recipes
      [q | qs] = d.quests
      [c | cs] = d.chaos

      d = %{
        d
        | recipes: [%{r | out: "bình_lạ"} | rs],
          boss_drops: Map.put(d.boss_drops, "golden_dragon", "relic_x"),
          quests: [put_in(q.reward.items, %{"vang_ao" => 1}) | qs],
          chaos: [%{c | items: %{"ngoc_ao" => 1}} | cs]
      }

      errs = Enum.join(DataCheck.errors(d), "\n")

      for {file, id} <- [
            {"recipes.json", "bình_lạ"},
            {"zones.json", "relic_x"},
            {"quests.json", "vang_ao"},
            {"chaos.json", "ngoc_ao"}
          ] do
        assert errs =~ ~r/#{file}.*#{id}/
      end
    end

    test "kỹ năng có effect lạ, cánh của lớp không có", %{d: d} do
      dk = d.classes["dk"]
      [s | ss] = dk.skills
      d = %{d | classes: Map.put(d.classes, "dk", %{dk | skills: [%{s | effect: "bay"} | ss]})}
      d = %{d | items: Map.put(d.items, "wing_x", %{slot: "wing", cls: "summoner"})}
      errs = Enum.join(DataCheck.errors(d), "\n")
      assert errs =~ ~r/classes.json.*"bay"/
      assert errs =~ ~r/items.json.*wing_x.*summoner/
    end

    test "bản đồ: NPC role lạ, bán món không có", %{d: d} do
      v = Maps.get("village")
      [n | ns] = v.npcs
      bad = %{v | npcs: [%{n | role: "bay_lung_tung", stock: ["mon_ao"]} | ns]}
      errs = Enum.join(DataCheck.map_errors(%{"village" => bad}, d), "\n")
      assert errs =~ ~r/maps\/village.json.*bay_lung_tung/
      assert errs =~ ~r/maps\/village.json.*mon_ao/
    end
  end

  describe "RULES (J1, A3, B2, E7): số giữ nguyên như trước khi chuyển" do
    test "EXP lên cấp, giá bán lại, bình máu theo cấp" do
      assert Engine.xp_to_next(1) == 40
      assert Engine.xp_to_next(10) == round(25 * :math.pow(10, 1.75) + 15)
      price = Data.item("broadsword").price
      assert Engine.sell_price("broadsword") == floor(price * 0.4)
      assert Data.potion_for(1) == "potion_s"
      assert Data.potion_for(9) == "potion_m"
      assert Data.potion_for(35) == "potion_l"
    end

    test "chỉ số chiến đấu theo Nhanh nhẹn đọc từ RULES.combat" do
      {:ok, p} = Engine.new_player("Thử", "elf")
      d = Engine.derived(p)
      c = Data.rules().combat
      assert d.crit == min(c.crit.max, c.crit.base + p.stats.agi * c.crit.per_agi)
      assert p.gold == Data.rules().character.start_gold
      assert p.inv == Data.rules().character.start_items
    end
  end

  describe "từ cấm trong tên (B9)" do
    test "không phân biệt hoa thường, dấu, số kiểu 4dm1n" do
      for n <- [
            "Admin",
            "aDmIn Pro",
            "4dm1n",
            "GM",
            "GM01",
            "Quản Trị",
            "Đụ Má",
            "vcl",
            "Hệ Thống"
          ] do
        assert Names.banned?(n), n
        assert {:error, _} = Names.validate(n)
      end
    end

    test "tên thường không bị chặn (khớp nguyên từ)" do
      for n <- [
            "Hắc Long",
            "Thiên Long",
            "Dương Quá",
            "Bích Hà",
            "Cường",
            "Hoàng Dũng",
            "Gió Mây"
          ] do
        refute Names.banned?(n), n
        assert {:ok, ^n} = Names.validate(n)
      end
    end

    test "tên và ký hiệu bang cũng lọc" do
      assert {:error, msg} = HacLong.Guilds.create(1, "Hội Admin", "HA", %{gold: 0}, nil)
      assert msg =~ "không được dùng"
      assert {:error, msg} = HacLong.Guilds.create(1, "Bang Hiền", "GM", %{gold: 0}, nil)
      assert msg =~ "không được dùng"
    end
  end

  describe "vị trí lưu không đi được (B11)" do
    test "ô đi được thì giữ nguyên" do
      pos = %{map: "village", x: 6, y: 4}
      assert World.valid_pos(pos) == pos
    end

    test "ô tường của bản đồ còn tồn tại → điểm vào của chính bản đồ đó" do
      entry = Maps.entry("village")
      assert %{map: "village"} = entry
      assert Maps.walkable?(Maps.get("village"), entry.x, entry.y)
      assert World.valid_pos(%{map: "village", x: 0, y: 0}) == entry
      assert World.valid_pos(%{map: "village", x: 999, y: 3}) == entry
    end

    test "bản đồ vùng không có đá dịch chuyển → chỗ đứng khi qua cổng vào" do
      assert %{map: "forest_1", x: x, y: y} = World.valid_pos(%{map: "forest_1", x: 0, y: 0})
      assert Maps.walkable?(Maps.get("forest_1"), x, y)
    end

    test "bản đồ không còn → về Nhà" do
      assert World.valid_pos(%{map: "map_da_xoa", x: 3, y: 3}) == Maps.home_spawn()
    end
  end
end

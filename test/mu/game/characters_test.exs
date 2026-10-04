defmodule Mu.Game.CharactersTest do
  use Mu.DataCase, async: false

  alias Mu.Game.{Character, Characters, Config, Data, Stats}

  test "tạo DK đúng chỉ số KB_CONFIG §2 và §4.1" do
    account = create_account()
    assert {:ok, %Character{} = c} = Characters.create(account, %{"name" => "Knight01"})

    assert c.class == "DK"
    assert {c.strength, c.agility, c.vitality, c.energy} == {28, 20, 25, 10}
    assert c.level == 1 and c.experience == 0 and c.free_stat_points == 0
    # hpMax = 110 + 0×3 + 25×3 = 185; mpMax = 20 + 0×1 + 10×1 = 30
    assert c.hp_current == 185
    assert c.mana_current == 30
    assert c.zen == 0
    assert c.map_id == "lorencia"
    # đứng ở playerSpawn, trong safe zone (G8)
    map = Mu.World.Maps.get("lorencia")
    assert {c.position_x, c.position_y} == map.player_spawn
    assert Mu.World.Maps.safe?(map, c.position_x, c.position_y)
    assert c.version == 0

    view = Characters.player_view(c)

    assert %{hpMax: 185, mpMax: 30, attackMin: 4, attackMax: 7, defense: 5, cooldownMs: 990} =
             view.view

    assert view.view.skills == ["basic_attack"] and view.view.expRequired == 100
    assert view.hp == 185

    stored = Repo.get!(Character, c.id)
    assert stored.account_id == account.id
    assert stored.name == "Knight01"
  end

  test "class bỏ trống = DK; DW/ELF tạo được (P2-M2); class lạ bị từ chối; MG khóa tới khi có nhân vật cấp 20 (P3-M5)" do
    assert Config.get(["newCharacter", "defaultClass"]) == "DK"
    assert Enum.sort(Map.keys(Data.classes())) == ["DK", "DW", "ELF", "MG"]

    account = create_account()
    assert {:ok, %{class: "DK"} = dk} = Characters.create(account, %{"name" => "Abcd1"})

    for cls <- ["dk", "XX"] do
      assert {:error, :invalid_class} =
               Characters.create(create_account(), %{"name" => "Zzzz1", "class" => cls})
    end

    assert {:error, :class_locked} =
             Characters.create(account, %{"name" => "Glad01", "class" => "MG"})

    assert %{id: "MG", locked: true, unlockLevel: 20} =
             Enum.find(Characters.creatable_classes(account.id), &(&1.id == "MG"))

    # cấp 19 chưa đủ, cấp 20 thì mở
    Repo.update!(Ecto.Changeset.change(dk, level: 19))

    assert {:error, :class_locked} =
             Characters.create(account, %{"name" => "Glad01", "class" => "MG"})

    Repo.update!(Ecto.Changeset.change(Repo.get!(Character, dk.id), level: 20))

    assert %{locked: false} =
             Enum.find(Characters.creatable_classes(account.id), &(&1.id == "MG"))

    assert {:ok, %{class: "MG"}} =
             Characters.create(account, %{"name" => "Glad01", "class" => "MG"})
  end

  test "P3-M5: MG cấp 1 — 26 mỗi stat, KB_CONFIG §2 (MG), mặc sẵn sword_t0, 7 điểm / cấp, chỉ số phép §4.1" do
    account = create_account()
    {:ok, dk} = Characters.create(account, %{"name" => "Lvl20dk"})
    Repo.update!(Ecto.Changeset.change(dk, level: 20))
    {:ok, mg} = Characters.create(account, %{"name" => "Glad02", "class" => "MG"})

    assert {mg.strength, mg.agility, mg.vitality, mg.energy, mg.level} == {26, 26, 26, 26, 1}
    # HP 110 + 26×3, MP 60 + 26×2
    assert {mg.hp_current, mg.mana_current} == {188, 112}

    assert [%{template_id: "sword_t0", location: "EQUIPMENT", slot: 5}] =
             Mu.Game.Items.load(mg.id)

    v = Characters.player_view(mg, Mu.Game.Items.load(mg.id)).view
    sword = Data.item("sword_t0")

    # vật lý STR/6..STR/4 + kiếm; phép ENE/4 + kiếm; tốc độ AGI/15 và AGI/20 + kiếm
    assert v.attackMin == div(26, 6) + sword["attackMin"]
    assert v.attackMax == div(26, 4) + sword["attackMax"]
    assert v.attackMaxMagic == div(26, 4) + sword["attackMax"]
    assert v.attackSpeed == div(26, 15) + sword["speed"]
    assert v.attackSpeedMagic == div(26, 20) + sword["speed"]
    assert v.defense == div(26, 5)

    # 7 điểm mỗi cấp
    assert Mu.Game.Stats.earned_points("MG", 3) - Mu.Game.Stats.earned_points("MG", 1) == 14
    # class khác không có chỉ số phép
    assert Characters.player_view(dk).view.attackMaxMagic == nil
  end

  test "P2-M2: DW / ELF cấp 1 đúng chỉ số KB_CONFIG §2 + §4.1, mặc sẵn đồ khởi đầu (P2-3)" do
    {:ok, dw} = Characters.create(create_account(), %{"name" => "Wizard1", "class" => "DW"})
    {:ok, elf} = Characters.create(create_account(), %{"name" => "Fairy1", "class" => "ELF"})
    {:ok, dk} = Characters.create(create_account(), %{"name" => "Knight9", "class" => "DK"})

    for {c, tpl} <- [{dw, "staff_t0"}, {elf, "bow_t0"}] do
      assert [%{template_id: ^tpl, location: "EQUIPMENT", slot: 5}] = Mu.Game.Items.load(c.id)
    end

    assert Mu.Game.Items.load(dk.id) == []

    dwv = Characters.player_view(dw, Mu.Game.Items.load(dw.id))
    elfv = Characters.player_view(elf, Mu.Game.Items.load(elf.id))

    # DW: HP 80+15×2, MP 60+30×2; atk ENE/9..ENE/4 + gậy 3–6; def AGI/5; tầm 1 (staff)
    assert {dw.hp_current, dw.mana_current} == {110, 120}

    assert Map.take(dwv.view, [:hpMax, :mpMax, :attackMin, :attackMax, :defense, :attackRange]) ==
             %{hpMax: 110, mpMax: 120, attackMin: 6, attackMax: 13, defense: 3, attackRange: 1}

    # ELF: HP 90+20×2, MP floor(40+15×1.5); atk AGI/7+STR/14 .. AGI/4+STR/8 + cung 2–5; tầm 5 (bow)
    assert {elf.hp_current, elf.mana_current} == {130, 62}

    assert Map.take(elfv.view, [:attackMin, :attackMax, :defense, :defenseRate, :attackRange]) ==
             %{attackMin: 7, attackMax: 14, defense: 2, defenseRate: 8, attackRange: 5}
  end

  test "luật tên §18: 4–10 ký tự ASCII chữ/số" do
    account = create_account()

    for bad <- ["abc", "abcdefghijk", "Trần1", "ab_cd", "ab cd", "abcd!", "", nil, 1234] do
      assert {:error, :invalid_name} = Characters.create(account, %{"name" => bad}),
             inspect(bad)
    end

    assert {:ok, %{name: "Ab12"}} = Characters.create(account, %{"name" => " Ab12 "})
  end

  test "tên unique không phân biệt hoa thường" do
    {_, _} = create_character("Hero01")

    assert {:error, :name_taken} =
             Characters.create(create_account(), %{"name" => "hERO01"})
  end

  test "mỗi tài khoản tối đa 4 nhân vật (account.maxCharacters, Q13 / P3-3)" do
    assert Config.get(["account", "maxCharacters"]) == 4
    account = create_account()
    for i <- 1..4, do: assert({:ok, _} = Characters.create(account, %{"name" => "Many#{i}x"}))
    assert {:error, :character_limit} = Characters.create(account, %{"name" => "Fifth1"})
    assert length(Characters.list(account.id)) == 4
  end

  test "hai request tạo song song cho cùng tài khoản (còn 1 chỗ): chỉ một thành công" do
    account = create_account()
    for i <- 1..3, do: {:ok, _} = Characters.create(account, %{"name" => "Pre#{i}xx"})

    results =
      1..5
      |> Enum.map(fn i ->
        Task.async(fn -> Characters.create(account, %{"name" => "Para#{i}x"}) end)
      end)
      |> Enum.map(&Task.await(&1, 10_000))

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :character_limit})) == 4
  end

  test "get_owned: chỉ nhân vật của chính tài khoản" do
    {a, c} = create_character()
    other = create_account()
    assert %Character{} = Characters.get_owned(a.id, c.id)
    assert Characters.get_owned(other.id, c.id) == nil
    assert Characters.get_owned(a.id, "khong-phai-uuid") == nil
    assert Characters.get_owned(a.id, nil) == nil
  end

  test "Stats đọc hệ số từ classes.json" do
    assert Stats.hp_max("DK", 1, 25) == 185
    assert Stats.hp_max("DK", 10, 25) == 185 + 9 * 3
    assert Stats.mp_max("DK", 10, 15) == 20 + 9 + 15
    assert Stats.earned_points("DK", 10) == 45
  end
end

defmodule Mu.Game.CharactersPositionTest do
  use Mu.DataCase, async: true

  alias Mu.Game.Characters

  test "save_position tăng version (optimistic lock); bản cũ ghi đè bị chặn" do
    {_, c} = create_character()
    assert {:ok, c2} = Characters.save_position(c, 20, 30)
    assert c2.version == c.version + 1
    assert {:ok, ^c2} = Characters.save_position(c2, 20, 30)

    assert_raise Ecto.StaleEntryError, fn -> Characters.save_position(c, 21, 30) end
    stored = Repo.get!(Mu.Game.Character, c.id)
    assert {stored.position_x, stored.position_y} == {20, 30}
  end

  test "P5-M1: vũ khí khởi đầu +3 → player.view Dmg +9 (items.levelBonus.WEAPON.attack 3)" do
    # DW mặc sẵn staff_t0 (DK không có đồ khởi đầu, MG khóa với tài khoản mới)
    {_, c} = create_character(nil, "DW")
    items = Mu.Game.Items.load(c.id)
    v0 = Characters.player_view(c, items).view
    weapon = Enum.find(items, &(&1.template_id == "staff_t0"))
    import Ecto.Query, only: [from: 2]
    Mu.Repo.update_all(from(i in Mu.Game.Item, where: i.id == ^weapon.id), set: [item_level: 3])
    items = Mu.Game.Items.load(c.id)
    v3 = Characters.player_view(c, items).view
    per = Mu.Game.Config.get(["items", "levelBonus", "WEAPON", "attack"])
    assert {v3.attackMin, v3.attackMax} == {v0.attackMin + 3 * per, v0.attackMax + 3 * per}

    assert Enum.find(Characters.player_view(c, items).equipment, &(&1.templateId == "staff_t0")).level ==
             3
  end
end

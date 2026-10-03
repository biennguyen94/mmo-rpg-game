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

  test "class bỏ trống = DK; DW/ELF tạo được (P2-M2); MG và class lạ bị từ chối" do
    assert Config.get(["newCharacter", "defaultClass"]) == "DK"
    assert Enum.sort(Map.keys(Data.classes())) == ["DK", "DW", "ELF"]

    assert {:ok, %{class: "DK"}} = Characters.create(create_account(), %{"name" => "Abcd1"})

    for cls <- ["MG", "dk", "XX"] do
      assert {:error, :invalid_class} =
               Characters.create(create_account(), %{"name" => "Zzzz1", "class" => cls})
    end
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

  test "mỗi tài khoản 1 nhân vật (account.maxCharacters, Q13)" do
    assert Config.get(["account", "maxCharacters"]) == 1
    account = create_account()
    assert {:ok, _} = Characters.create(account, %{"name" => "First1"})
    assert {:error, :character_limit} = Characters.create(account, %{"name" => "Second1"})
    assert length(Characters.list(account.id)) == 1
  end

  test "hai request tạo song song cho cùng tài khoản: chỉ một thành công" do
    account = create_account()

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
end

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
    assert c.version == 0

    view = Characters.player_view(c)
    assert view.view == %{hpMax: 185, mpMax: 30}
    assert view.hp == 185

    stored = Repo.get!(Character, c.id)
    assert stored.account_id == account.id
    assert stored.name == "Knight01"
  end

  test "class bỏ trống = class mặc định; class khác DK bị từ chối (Phase 1)" do
    assert Config.get(["newCharacter", "class"]) == "DK"
    assert Map.keys(Data.classes()) == ["DK"]

    assert {:ok, %{class: "DK"}} =
             Characters.create(create_account(), %{"name" => "Abcd1", "class" => "DK"})

    for cls <- ["DW", "ELF", "MG", "dk", "XX"] do
      assert {:error, :invalid_class} =
               Characters.create(create_account(), %{"name" => "Zzzz1", "class" => cls})
    end
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

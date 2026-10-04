defmodule MuWeb.AdminChannelTest do
  @moduledoc "DEC-187: `Mu.Admin.give_exp/3`, `set_level/3` khi offline (ghi DB) và online (qua Session)."
  use MuWeb.ChannelCase

  alias Mu.{Admin, Repo}
  alias Mu.Game.{Character, Engine}
  alias MuWeb.GameChannel

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  test "offline: tặng EXP lên cấp liên tiếp (+5 điểm / cấp, HP đầy), set_level, lỗi, log" do
    {_a, c} = create_character()
    name = c.name

    # cấp 1 → 2 cần 100, 2 → 3 cần 283: 400 EXP → cấp 3, dư 17
    assert {:ok, %{level_before: 1, level: 3, experience: 17, exp: 400, online: false}} =
             Admin.give_exp(String.downcase(name), 400, "test")

    db = Repo.get!(Character, c.id)
    assert {db.level, db.experience, db.free_stat_points} == {3, 17, 10}
    assert db.hp_current == Engine.derived(db, []).hp_max
    assert db.version > c.version

    assert {:ok, %{level: 10, experience: 0}} = Admin.set_level(name, 10, "ticket 1")
    assert Repo.get!(Character, c.id).free_stat_points == 45

    assert {:error, :bad_level} = Admin.set_level(name, 10)
    assert {:error, :bad_level} = Admin.set_level(name, Engine.max_level() + 1)
    assert {:error, :bad_amount} = Admin.give_exp(name, 0)
    assert {:error, :bad_amount} = Admin.give_exp(name, "100")
    assert {:error, :no_character} = Admin.give_exp("Khongco1", 100)

    # cấp tối đa: EXP về 0, không vượt
    assert {:ok, %{level: 30, experience: 0}} = Admin.give_exp(name, 10_000_000)

    assert [
             %{action: "GIVE_EXP", detail: %{"exp" => 10_000_000}},
             %{action: "SET_LEVEL", reason: "ticket 1", detail: %{"level" => 10}},
             %{action: "GIVE_EXP", detail: %{"level_before" => 1, "level" => 3}}
           ] = Admin.log(name)
  end

  test "online: cộng ngay trong game (event player), lưu DB, vào lại không mất" do
    {a, c} = create_character()
    {:ok, _, _socket} = join_game(a, c)

    assert {:ok, %{level: 2, online: true}} = Admin.give_exp(c.name, 150)
    assert_push "player", %{level: 2, experience: 50, freeStatPoints: 5}
    assert %{level: 2, experience: 50} = Repo.get!(Character, c.id)

    assert {:ok, %{level: 5, experience: 0}} = Admin.set_level(c.name, 5)
    assert_push "player", %{level: 5, experience: 0}
  end

  test "DEC-188: tặng đồ +N / option, Zen, chỉ số — offline và online, audit sạch" do
    {a, c} = create_character()
    name = c.name

    assert {:ok, _} = Admin.give_item(name, "staff_t1", level: 11, option: 4, reason: "admin")
    assert {:ok, _} = Admin.give_item(name, "wing_soul", level: 11)
    assert {:ok, _} = Admin.give_item(name, "jewel_bless", quantity: 20)
    assert {:error, :bad_option} = Admin.give_item(name, "wing_soul", option: 1)
    assert {:error, :bad_level} = Admin.give_item(name, "ring_hp_t0", level: 1)
    assert {:error, :bad_level} = Admin.give_item(name, "staff_t1", level: 12)
    assert {:error, :bad_quantity} = Admin.give_item(name, "staff_t1", level: 1, quantity: 2)
    assert {:error, :unknown_item} = Admin.give_item(name, "abc")

    items = Mu.Game.Items.load(c.id)
    assert %{item_level: 11, option_level: 4} = Enum.find(items, &(&1.template_id == "staff_t1"))
    assert %{item_level: 11, option_level: 0} = Enum.find(items, &(&1.template_id == "wing_soul"))
    assert %{quantity: 20} = Enum.find(items, &(&1.template_id == "jewel_bless"))

    assert {:ok, %{zen: 1_000_000}} = Admin.add_zen(name, 1_000_000, "admin")
    assert {:ok, %{zen: 999_000}} = Admin.add_zen(name, -1000)
    assert {:error, "NOT_ENOUGH_ZEN"} = Admin.add_zen(name, -10_000_000)

    assert {:ok, %{energy: 510, free_stat_points: 5}} =
             Admin.add_stats(name, %{energy: 500, free_stat_points: 5})

    assert {:error, :bad_stats} = Admin.add_stats(name, %{zen: 1})
    db = Repo.get!(Character, c.id)
    assert db.hp_current == Engine.derived(db, []).hp_max

    # online: túi / Zen / chỉ số đẩy ngay
    {:ok, _, _socket} = join_game(a, c)
    assert {:ok, _} = Admin.give_item(name, "hp_potion_small", quantity: 5)
    assert_push "player", %{inventory: inv}
    assert Enum.any?(inv, &(&1.templateId == "hp_potion_small"))
    assert {:ok, %{zen: 1_000_000}} = Admin.add_zen(name, 1000)
    assert_push "player", %{zen: 1_000_000}
    assert {:ok, %{vitality: 125}} = Admin.add_stats(name, %{vitality: 100})
    assert_push "player", %{vitality: 125}

    assert Mu.Audit.run().problems == []
    assert length(Admin.log(name)) == 9
  end
end

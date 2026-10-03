defmodule Mu.Game.ConfigTest do
  use ExUnit.Case, async: true

  alias Mu.Game.{Config, Data}

  test "config có nguồn gốc (KB_00_RULES §2) và giá trị đã chốt" do
    all = Config.all()
    assert all["sourceType"] == "CONFIG"
    assert Map.has_key?(all, "version")
    assert all["verified"] == false
    # Phase 1 = 10; Phase 2 = 30 (P2-2)
    assert Config.get(["game", "maxLevel"]) == 30
    assert Config.get(["server", "simulationHz"]) == 20
    assert Config.get(["auth", "wsTicketTtlSeconds"]) == 30
    assert Config.get(["session", "singleLoginPerAccount"]) == true
  end

  test "khóa thiếu thì raise (không có giá trị ẩn trong code)" do
    assert_raise ArgumentError, fn -> Config.get(["game", "khongco"]) end
  end

  test "mọi class có sourceType/version/verified" do
    for {_, c} <- Data.classes(), key <- ~w(sourceType version verified) do
      assert Map.has_key?(c, key)
    end
  end

  test "mọi act của KB_TECHNICAL §5 (+ act hộp thư P2-13) có nhóm rate-limit" do
    acts =
      ~w(move_to attack skill pickup equip unequip move_item split drop use_item npc_open buy sell alloc chat) ++
        ~w(mail_list mail_claim mail_delete)

    assert Enum.sort(Mu.Game.Commands.acts()) == Enum.sort(acts)
  end
end

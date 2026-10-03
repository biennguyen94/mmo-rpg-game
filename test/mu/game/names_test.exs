defmodule Mu.Game.NamesTest do
  use ExUnit.Case, async: true

  alias Mu.Game.Names

  test "hợp lệ" do
    assert {:ok, "Abcd"} = Names.validate("Abcd")
    assert {:ok, "A123456789"} = Names.validate("A123456789")
    assert {:ok, "Abcd"} = Names.validate("  Abcd ")
  end

  test "không hợp lệ" do
    for bad <- ["Abc", "A1234567890", "Ábcd", "ab-cd", "ab_cd", "ab\ncd", nil, :atom] do
      assert {:error, :invalid_name} = Names.validate(bad), inspect(bad)
    end
  end

  test "danh sách từ cấm mặc định rỗng (G22)" do
    assert Mu.Game.Config.get(["names", "bannedWords"]) == []
  end
end

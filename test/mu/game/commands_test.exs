defmodule Mu.Game.CommandsTest do
  use ExUnit.Case, async: true

  alias Mu.Game.{Commands, Config}

  test "phong bì lệnh" do
    assert {:ok, "move_to", "r1"} = Commands.envelope(%{"act" => "move_to", "rid" => "r1"})
    assert {:error, "r1", "FORBIDDEN"} = Commands.envelope(%{"act" => "fly", "rid" => "r1"})
    assert {:error, nil, "FORBIDDEN"} = Commands.envelope(%{"act" => "move_to"})
    assert {:error, nil, "FORBIDDEN"} = Commands.envelope(%{"act" => "move_to", "rid" => ""})

    assert {:error, nil, "FORBIDDEN"} =
             Commands.envelope(%{"act" => "move_to", "rid" => String.duplicate("x", 65)})

    assert {:error, nil, "FORBIDDEN"} = Commands.envelope(%{"act" => "move_to", "rid" => 1})
    assert {:error, nil, "FORBIDDEN"} = Commands.envelope("rác")
  end

  test "nhóm rate-limit theo P8" do
    assert {"move", 10, 1000} = Commands.category("move_to")
    assert {"combat", 10, 1000} = Commands.category("skill")
    assert {"item", 5, 1000} = Commands.category("buy")
    assert {"alloc", 5, 1000} = Commands.category("alloc")
    assert {"chat", 5, 5_000} = Commands.category("chat")
  end

  test "chuỗi vi phạm liên tục ≥ kickAfterMs thì kick" do
    kick = Config.get(["rateLimit", "cmd", "kickAfterMs"])
    assert kick == 5000

    {:ok, s} = Commands.violation(nil, 0, 1000)
    # vi phạm mỗi 900ms: vẫn một chuỗi
    {s, _} =
      Enum.reduce(1..5, {s, 0}, fn i, {s, _} ->
        {:ok, s} = Commands.violation(s, i * 900, 1000)
        {s, i}
      end)

    assert {:kick, _} = Commands.violation(s, 5400, 1000)
  end

  test "nghỉ lâu hơn một cửa sổ thì chuỗi bắt đầu lại" do
    {:ok, s} = Commands.violation(nil, 0, 1000)
    {:ok, s} = Commands.violation(s, 4000, 1000)
    assert s == {4000, 4000}
    assert {:ok, _} = Commands.violation(s, 4500, 1000)
  end
end

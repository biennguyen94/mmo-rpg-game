defmodule HacLong.Bots.BrainFitTest do
  # DECISIONS "Bot chọn bãi theo sức thật", "Bot chơi theo phiên"
  use ExUnit.Case, async: true

  alias HacLong.Bots.{Bot, Brain}
  alias HacLong.Game.{Data, Engine}
  alias HacLong.World.Maps

  defp player(attrs) do
    {:ok, p} = Engine.new_player("Bot", "dw")
    p = Map.merge(p, Map.merge(%{level: 50, gold: 1_000_000}, attrs))
    %{p | hp: Engine.derived(p).maxHp}
  end

  defp realm_map(r), do: Maps.get("realm_" <> String.pad_leading("#{r}", 2, "0"))

  test "bot yếu (CS cao, đồ +0): không đánh nổi vùng chuyển sinh, lùi về bản đồ thường" do
    weak = player(%{rebirths: 12})
    refute Brain.fit?(weak, realm_map(1))
    assert Brain.realm_target(weak) == nil
  end

  test "bot mạnh: đánh nổi vùng thấp; bản đồ thường luôn đánh nổi" do
    strong =
      player(%{rebirths: 3, stats: %{str: 600, agi: 600, vit: 800, ene: 1200}})

    assert Brain.fit?(strong, realm_map(1))
    assert Brain.fit?(player(%{}), Maps.get("forest_1"))
  end

  test "gục rải rác ở nhiều bản đồ cùng một vùng: tránh cả vùng" do
    n = Data.rules().bots.play.avoid.deaths
    maps = ["realm_02", "realm_02_2", "realm_02_3", "realm_02_4"] |> Enum.take(n)

    st =
      Enum.reduce(Enum.with_index(maps), %{fails: %{}, avoid: %{}}, fn {m, i}, st ->
        Brain.note_death(st, m, 1_000 + i)
      end)

    assert "realm:2" in Brain.avoiding(st, 2_000)
    refute "realm_02" in Brain.avoiding(st, 2_000)
  end

  test "chỉ thoát game lúc rảnh" do
    p = player(%{pos: %{map: "forest_1", x: 1, y: 1}})
    assert Bot.leave_ok?(p, -1)
    refute Bot.leave_ok?(%{p | battle: %{over: false}}, -1)
    assert Bot.leave_ok?(%{p | battle: %{over: true}}, -1)
    refute Bot.leave_ok?(%{p | pos: %{p.pos | map: "tower"}}, -1)
    assert Bot.leave_ok?(nil, -1)
  end
end

defmodule HacLong.FleeHpTest do
  @moduledoc "Phase 1: bỏ chạy rồi đánh lại thì quái vẫn dở máu (hồi dần), không đầy lại ngay."
  use ExUnit.Case, async: false

  alias HacLong.World.MapServer

  @map "forest_1"

  setup do
    MapServer.clear_monsters(@map)
    :ok
  end

  test "nhả quái giữ phần trăm máu; đánh lại nhận máu đó" do
    m = MapServer.put_monster(@map, "bat", {3, 3})
    {:engage, _} = MapServer.step(@map, 1, {m.x, m.y}, true)
    MapServer.hp(@map, m.id, 40)
    :ok = MapServer.release(@map, 1, m.id)

    snap = Enum.find(MapServer.snapshot(@map).monsters, &(&1.id == m.id))
    assert snap.hp >= 40 and snap.hp < 50

    {:engage, again} = MapServer.step(@map, 2, {m.x, m.y}, true)
    assert again.hp >= 40 and again.hp < 50
  end
end

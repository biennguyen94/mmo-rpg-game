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

  test "tháp / sự kiện: bỏ chạy thì quái giữ % máu, đánh lại tiếp từ đó" do
    alias HacLong.Game.Tower
    m = %{id: 7, kind: "bat", name: "Dơi", level: 5, x: 1, y: 1, elite: false}
    q = Tower.battle_monster(m)

    p = %{
      tower: %{monsters: [m]},
      battle: %{
        over: true,
        result: "fled",
        encounter: %{tower: 7},
        monster: %{q | hp: div(q.maxHp, 4)}
      }
    }

    [kept] = Tower.keep_hp(p).tower.monsters
    assert kept.hp_pct == 25

    p2 = Tower.resume_hp(%{battle: %{monster: q}}, kept)
    assert p2.battle.monster.hp == round(q.maxHp * 0.25)

    # thắng / chưa bỏ chạy thì không đổi
    assert Tower.keep_hp(put_in(p.battle.result, "win")) == put_in(p.battle.result, "win")
    assert Tower.resume_hp(%{battle: %{monster: q}}, m).battle.monster.hp == q.maxHp
  end
end

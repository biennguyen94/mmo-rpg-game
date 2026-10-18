defmodule HacLong.Game.EventScaleTest do
  @moduledoc "Quái sự kiện mạnh theo số lần chuyển sinh người đánh (`RULES.event_scale`, `Engine.scale_event/1`)."
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, DevilSquare, Engine}

  @r Data.rules().event_scale

  defp hero(rb) do
    {:ok, p} = Engine.new_player("Sk", "dk")
    p = Map.merge(p, %{level: 50, rebirths: rb})
    q = DevilSquare.battle_monster(%{kind: "ghoul", name: "Ma Cà Rồng", level: 48, elite: false})
    {%{ok: true}, p} = Engine.start_with_monster(p, 0, q)
    p
  end

  test "chưa chuyển sinh: giữ nguyên; k lần: máu / thủ / công / thưởng nhân theo RULES" do
    base = hero(0)
    assert Engine.scale_event(base) == base

    m0 = base.battle.monster
    m = Engine.scale_event(hero(5)).battle.monster
    assert m.maxHp == round(m0.maxHp * (1 + 5 * @r.hp_per_rebirth))
    assert m.hp == m.maxHp
    assert m.def == round(m0.def * (1 + 5 * @r.hp_per_rebirth))
    assert m.atk == round(m0.atk * (1 + 5 * @r.atk_per_rebirth))
    assert m.xp == round(m0.xp * (1 + 5 * @r.reward_per_rebirth))
  end

  test "không quá số lần chuyển sinh tối đa" do
    m10 = Engine.scale_event(hero(10)).battle.monster
    m99 = Engine.scale_event(hero(99)).battle.monster
    assert m10.maxHp == m99.maxHp
  end
end

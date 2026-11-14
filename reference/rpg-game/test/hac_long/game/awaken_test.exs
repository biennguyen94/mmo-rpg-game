defmodule HacLong.Game.AwakenTest do
  # DECISIONS "Trùm Thức Tỉnh theo sức người đánh"
  use ExUnit.Case, async: true

  alias HacLong.Game.{Awaken, Data, Engine}

  @cfg Data.rules().awaken.bosses.secret

  defp in_battle(m) do
    {:ok, p} = Engine.new_player("Thu", "dk")
    p = %{p | level: 50, hp: 9999}
    {_, p} = Engine.start_with_monster(p, 0, Map.put(m, :hp, m.maxHp))
    p
  end

  defp boss, do: Engine.make_monster(Data.side_monster(Data.rules().secret.boss), true)

  test "người thường (cần nhiều lượt): bản thường" do
    p = in_battle(boss())
    assert Awaken.turns(p, p.battle.monster) > Data.rules().awaken.trigger_turns
    assert Awaken.maybe(p, "secret") == p
  end

  test "đủ mạnh (hạ trong vài lượt): Thức Tỉnh — máu / công / thưởng nhân thêm, một lần, có dòng nhật ký" do
    b = boss()
    weak = %{b | maxHp: 50, def: 0}
    p = in_battle(weak)
    q = Awaken.maybe(p, "secret")
    m = q.battle.monster
    assert m.awakened
    assert m.maxHp == round(50 * @cfg.hp) and m.hp == m.maxHp
    assert m.atk == round(b.atk * @cfg.atk)
    assert m.xp == round(b.xp * @cfg.reward)
    assert String.ends_with?(m.name, Data.rules().awaken.suffix)
    assert List.last(q.battle.log).text =~ "thức tỉnh"
    # gọi lại không nhân thêm
    assert Awaken.maybe(q, "secret") == q
  end

  test "trùm không bật Thức Tỉnh: không đổi; vật phẩm thêm của trùm đêm" do
    p = in_battle(%{boss() | maxHp: 50, def: 0})
    assert Awaken.maybe(p, "khong_co") == p
    assert Awaken.items("secret") == @cfg.items
  end
end

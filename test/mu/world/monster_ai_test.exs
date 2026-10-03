defmodule Mu.World.MonsterAiTest do
  use ExUnit.Case, async: true

  alias Mu.Game.Data
  alias Mu.World.MonsterAi

  @tpl Data.monster("spider")

  defp spider(attrs \\ %{}) do
    Map.merge(
      %{
        id: "m_1",
        tpl: @tpl,
        x: 10,
        y: 10,
        home: {10, 10},
        hp: 30,
        hp_max: 30,
        state: "idle",
        target: nil,
        path: [],
        next_attack_at: 0,
        damage_by: %{}
      },
      attrs
    )
  end

  defp ctx(players, attrs \\ %{}) do
    Map.merge(
      %{
        now: 1000,
        players: players,
        walkable?: fn x, y -> x in 0..40 and y in 0..40 end,
        cooldown_ms: 1000
      },
      attrs
    )
  end

  defp p(x, y, attrs \\ %{}), do: Map.merge(%{x: x, y: y, alive?: true, safe?: false}, attrs)

  test "IDLE: aggro người gần nhất trong aggroRange 5 (Chebyshev)" do
    assert @tpl["aggroRange"] == 5
    {m, []} = MonsterAi.think(spider(), ctx(%{"a" => p(15, 12), "b" => p(13, 13)}))
    assert {m.state, m.target} == {"chase", "b"}
    assert m.path != []

    {m, []} = MonsterAi.think(spider(), ctx(%{"a" => p(16, 10)}))
    assert {m.state, m.target} == {"idle", nil}
  end

  test "không aggro người đã chết hoặc đứng trong safe zone (G14)" do
    players = %{"a" => p(11, 10, %{alive?: false}), "b" => p(12, 10, %{safe?: true})}
    {m, []} = MonsterAi.think(spider(), ctx(players))
    assert m.state == "idle"
  end

  test "trong attackRange: đứng lại, đánh theo baseCooldownMs (G5)" do
    m = spider(%{state: "chase", target: "a", path: [{11, 11}]})
    {m, [{:attack, "a"}]} = MonsterAi.think(m, ctx(%{"a" => p(11, 11)}))
    assert {m.state, m.path, m.next_attack_at} == {"attack", [], 2000}

    {m, []} = MonsterAi.think(m, ctx(%{"a" => p(11, 11)}, %{now: 1900}))
    {_m, [{:attack, "a"}]} = MonsterAi.think(m, ctx(%{"a" => p(11, 11)}, %{now: 2000}))
  end

  test "mục tiêu chạy ra khỏi tầm: đuổi theo" do
    m = spider(%{state: "attack", target: "a"})
    {m, []} = MonsterAi.think(m, ctx(%{"a" => p(13, 10)}))
    assert m.state == "chase"
    assert List.last(m.path) == {13, 10}
  end

  test "RETURN khi vượt leashRange 12, mất mục tiêu, mục tiêu vào safe zone: hồi đầy HP, bỏ aggro" do
    assert @tpl["leashRange"] == 12
    far = spider(%{state: "chase", target: "a", x: 23, y: 10, hp: 5, damage_by: %{"a" => 25}})

    for {m, players} <- [
          {far, %{"a" => p(24, 10)}},
          {spider(%{state: "chase", target: "a", hp: 5, x: 12}), %{}},
          {spider(%{state: "attack", target: "a", hp: 5, x: 12}),
           %{"a" => p(13, 10, %{safe?: true})}},
          {spider(%{state: "attack", target: "a", hp: 5, x: 12}),
           %{"a" => p(13, 10, %{alive?: false})}}
        ] do
      {m, []} = MonsterAi.think(m, ctx(players))
      assert {m.state, m.target, m.hp, m.damage_by} == {"return", nil, 30, %{}}
      assert List.last(m.path) == {10, 10}
    end
  end

  test "RETURN về tới chỗ sinh thì IDLE; đang về không nhận aggro" do
    m = MonsterAi.start_return(spider())
    {m, []} = MonsterAi.think(m, ctx(%{"a" => p(11, 10)}))
    assert m.state == "idle"

    m = MonsterAi.start_return(spider(%{x: 14}))
    m = MonsterAi.hit(m, "a", 5)
    assert {m.state, m.target} == {"return", nil}
  end

  test "bị đánh: đổi mục tiêu sang người gây nhiều sát thương nhất (G15)" do
    m = spider() |> MonsterAi.hit("a", 5)
    assert {m.state, m.target} == {"chase", "a"}
    m = m |> MonsterAi.hit("b", 4) |> MonsterAi.hit("b", 3)
    assert m.target == "b"
    assert MonsterAi.top_damager(m) == "b"
  end

  test "A* hết ngân sách: bước thẳng nếu gần hơn" do
    walls = fn x, y -> x in 0..60 and y in 0..60 and not (x == 12 and y in 0..60) end
    m = spider(%{state: "chase", target: "a"})

    # mục tiêu bên kia bức tường dài: không có đường trong 32 ô, ô kề thẳng là tường
    {m, []} = MonsterAi.think(m, ctx(%{"a" => p(14, 10)}, %{walkable?: walls}))
    assert {m.state, m.path} == {"chase", [{11, 10}]}
  end
end

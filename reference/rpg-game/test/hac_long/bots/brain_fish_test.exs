defmodule HacLong.Bots.BrainFishTest do
  # DECISIONS "Bot câu cá, bot try hard"
  use ExUnit.Case, async: true

  alias HacLong.Bots.Brain
  alias HacLong.Game.{Data, Engine}
  alias HacLong.World.Maps

  @lake "long_vuong_lake"
  @tryhard Data.rules().bots.tryhard.every
  @chase Data.rules().bots.fish.chase_every
  @reach Data.rules().fishing.dragon.reach

  defp lake, do: Maps.get(@lake)

  # bot cấp đủ vào hồ, đứng ở ô `at` của hồ
  defp angler({x, y}) do
    {:ok, p} = Engine.new_player("Bot", "dk")
    p = %{p | level: 40, gold: 0, inv: %{}}
    %{p | hp: Engine.derived(p).maxHp} |> Map.put(:pos, %{map: @lake, x: x, y: y})
  end

  # ô đứng câu và một ô nước trong tầm câu của nó
  defp spot do
    m = lake()
    stand = hd(Brain.stand_tiles(m))
    {sx, sy} = stand

    water =
      for dx <- -@reach..@reach,
          dy <- -@reach..@reach,
          Maps.water?(m, sx + dx, sy + dy),
          do: {sx + dx, sy + dy}

    {stand, hd(water)}
  end

  # seed bot thường, không săn rồng
  defp plain_seed, do: Enum.find(1..100, &(not Brain.chaser?(&1)))

  test "bot try hard và bot săn rồng chọn theo seed" do
    assert Brain.tryhard?(@tryhard)
    refute Brain.tryhard?(@tryhard + 1)
    assert Brain.chaser?(@tryhard)
    assert Brain.chaser?(@chase)
    refute Brain.chaser?(plain_seed())
  end

  test "Long Vương nổi: bot săn rồng đứng trong tầm câu thì thả trúng ô Ngài" do
    {stand, {wx, wy} = water} = spot()
    p = angler(stand)

    assert %{"act" => "fish_cast", "x" => ^wx, "y" => ^wy} =
             Brain.decide(p, nil, %{seed: @tryhard, dragon: water})

    # bot thường không bỏ việc đi săn
    refute match?(
             %{"act" => "fish_cast"},
             Brain.decide(p, nil, %{seed: plain_seed(), dragon: water})
           )

    # đã có Long Vương thì nhường người khác
    owned = Map.put(p, :pets, ["long_vuong"])

    refute match?(
             %{"act" => "fish_cast"},
             Brain.decide(owned, nil, %{seed: @tryhard, dragon: water})
           )
  end

  test "Long Vương nổi mà bot ở xa: đi về hồ" do
    {_stand, water} = spot()
    p = %{angler({0, 0}) | pos: %{map: "village", x: 12, y: 8}}
    cmd = Brain.fish_job(p, nil, %{seed: @tryhard, dragon: water}, :chase)
    assert cmd != nil and cmd["act"] in ["travel", "move"]

    # chưa đủ cấp vào hồ thì thôi
    low = %{p | level: 5}
    assert Brain.fish_job(low, nil, %{seed: @tryhard, dragon: water}, :chase) == nil
  end

  # chạy lệnh bot (đi bộ qua World.move) tới khi bot thả câu; trả {ô đứng, lệnh thả}
  defp walk_to_cast(p, opts, snap \\ nil, n \\ 200) do
    case Brain.fish_job(p, snap, opts, :idle) do
      %{"act" => "fish_cast"} = cmd ->
        {{p.pos.x, p.pos.y}, cmd}

      %{"act" => "move", "dir" => dir} when n > 0 ->
        {_r, p} = HacLong.World.move(p, -1, dir, true)
        walk_to_cast(p, opts, snap, n - 1)

      other ->
        flunk("lệnh lạ: #{inspect(other)}")
    end
  end

  test "lượt ra hồ: mỗi bot đi tới chỗ câu riêng (theo seed, tránh ô có người) rồi thả câu; đã thả câu thì đứng chờ giật" do
    {stand, _} = spot()
    p = angler(stand)
    stands = Brain.stand_tiles(lake())

    spots =
      for seed <- [2, 4, 6, 8, 10, 12] do
        {at, cmd} = walk_to_cast(p, %{fishing: true, seed: seed})
        refute Map.has_key?(cmd, "x")
        assert at in stands
        at
      end

    # không dồn một ô (trước đây con nào cũng về ô gần nhất)
    assert length(Enum.uniq(spots)) >= 3

    # ô định tới đã có người khác đứng: chọn ô khác
    [mine] = Brain.spread(stands, p, stand, 1, nil)
    snap = %{players: [%{id: 99, x: elem(mine, 0), y: elem(mine, 1)}], monsters: []}
    assert [other] = Brain.spread(stands, p, stand, 1, snap)
    assert other != mine

    # đang câu ở ô trống: ở lại
    fishing = Map.put(p, :fishing, %{bite: 0, pos: p.pos})
    assert Brain.spread(stands, fishing, stand, 1, nil) == [stand]

    assert Brain.fish_job(p, nil, %{fishing: false}, :idle) == nil

    waiting = Map.put(p, :fishing, %{bite: 0, pos: p.pos})
    assert Brain.decide(waiting, nil, %{fishing: true, reeling: true}) == nil
  end

  test "bot seed lẻ dùng lượt ra hồ để ra Đồi Sáo Diều thả diều: tới mép đồi rồi thả, Chim Lạc đang lượn thì thả trúng ô nó" do
    assert Brain.kiter?(1) and not Brain.kiter?(2)
    hill = Maps.get(HacLong.Game.Kite.map_id())
    [stand | _] = Brain.sky_stands(hill)
    p = angler(stand) |> Map.put(:pos, %{map: hill.id, x: elem(stand, 0), y: elem(stand, 1)})

    walk = fn walk, p, opts, n ->
      case Brain.fish_job(p, nil, opts, :idle) do
        %{"act" => "kite_fly"} = c ->
          {p, c}

        %{"act" => "move", "dir" => d} when n > 0 ->
          walk.(walk, elem(HacLong.World.move(p, -1, d, true), 1), opts, n - 1)

        other ->
          flunk("lệnh lạ: #{inspect(other)}")
      end
    end

    {at, cmd} = walk.(walk, p, %{fishing: true, seed: 1}, 200)
    assert {at.pos.x, at.pos.y} in Brain.sky_stands(hill)
    refute Map.has_key?(cmd, "x")

    # Chim Lạc đang lượn trong tầm: thả trúng ô nó
    {sx, sy} = stand

    bird =
      Enum.find(HacLong.SkyEvent.spots(), fn {x, y} -> max(abs(x - sx), abs(y - sy)) <= 3 end)

    {_, c2} = walk.(walk, p, %{fishing: true, seed: 1, bird: bird}, 200)
    assert {c2["x"], c2["y"]} == bird
    # ở hồ: đi sang đồi
    lake_p = angler(stand)
    assert %{"act" => act} = Brain.fish_job(lake_p, nil, %{fishing: true, seed: 3}, :idle)
    assert act in ["travel", "move"]
  end

  test "lượt ra hồ, có Đàn Cá Vàng: thả trúng ô đàn cá" do
    {stand, {wx, wy} = water} = spot()
    p = angler(stand)

    assert %{"act" => "fish_cast", "x" => ^wx, "y" => ^wy} =
             Brain.fish_job(p, nil, %{fishing: true, school: water}, :idle)
  end

  test "câu đủ cá ở hồ trong ngày thì nhận việc Ông Lão" do
    {stand, _} = spot()
    n = Data.rules().fishing.elder.count
    p = angler(stand) |> Map.put(:daily, %{lake_n: n})
    assert %{"act" => "elder_claim"} = Brain.fish_job(p, nil, %{fishing: true}, :idle)
  end

  test "Long Vương nổi: bot săn rồng bỏ dở Tháp Vô Tận, không bỏ Quảng Trường Quỷ" do
    {_stand, water} = spot()

    tower = %{
      tiles: ["#####", "#...#", "#.<.#", "#####"],
      exit: [2, 2],
      stairs: [3, 1],
      monsters: [%{x: 3, y: 1, kind: "x"}],
      floor: 3
    }

    p = angler({0, 0}) |> Map.merge(%{tower: tower, pos: %{map: "tower", x: 2, y: 1}})
    opts = %{seed: @tryhard, dragon: water}
    assert %{"act" => "move", "dir" => "down"} = Brain.decide(p, nil, opts)

    # bot thường thì đánh tiếp
    refute match?(%{"dir" => "down"}, Brain.decide(p, nil, %{opts | seed: plain_seed()}))

    ds = put_in(p, [:tower, :ds], %{waves: 5})
    refute match?(%{"dir" => "down"}, Brain.decide(ds, nil, opts))
  end
end

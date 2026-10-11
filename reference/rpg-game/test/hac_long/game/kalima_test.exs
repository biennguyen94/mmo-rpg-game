defmodule HacLong.Game.KalimaTest do
  @moduledoc "Kalima (B-21): Dấu Ấn Kundun → Bản Đồ Thất Lạc, Kalima 1–7 theo cấp, hạ quái → Kundun → thưởng."
  use HacLongWeb.ChannelCase

  alias HacLong.Game.{Chaos, Characters, Data, Engine, Kalima, Rng, Tower}

  @r Kalima.rules()

  setup do
    on_exit(fn -> Rng.clear() end)
    :ok
  end

  defp player(level \\ 32) do
    {:ok, p} = Engine.new_player("Thử", "dk")
    %{p | level: level, gold: 100_000}
  end

  defp inside(level \\ 32) do
    p = player(level) |> Engine.add_item(@r.ticket)
    {%{ok: true}, p} = Kalima.enter(p)
    p
  end

  defp win(p, m) do
    b = %{over: true, result: "win", encounter: %{tower: m.id}, log: []}
    Tower.after_battle(%{p | battle: b}) |> Map.put(:battle, nil)
  end

  test "Kalima 1–7 theo cấp nhân vật" do
    assert Kalima.tier(@r.min_level - 1) == nil
    assert Kalima.tier(@r.min_level).n == 1
    assert Kalima.tier(32) == %{n: 3, level: 32}
    assert Kalima.tier(50).n == 7
    assert length(@r.tiers) == 7
  end

  test "ghép 5 Dấu Ấn Kundun ở Máy Hỗn Nguyên ra Bản Đồ Thất Lạc" do
    p = player() |> Engine.add_item(@r.mark, 5)
    {%{ok: true}, p} = Chaos.combine(p, "lost_map", nil)
    assert p.inv[@r.ticket] == 1 and not Map.has_key?(p.inv, @r.mark)
  end

  test "vào: cần cấp, Bản Đồ Thất Lạc; quái cấp theo Kalima" do
    {%{ok: false, msg: m}, _} = Kalima.enter(player())
    assert m =~ "Bản Đồ Thất Lạc"

    {%{ok: false}, _} = Kalima.enter(player(@r.min_level - 1) |> Engine.add_item(@r.ticket))

    p = inside()
    assert p.pos.map == Tower.map_id() and p.tower.kal.n == 3 and p.tower.kal.stage == "guards"
    assert length(p.tower.monsters) == @r.guards
    assert Enum.all?(p.tower.monsters, &(&1.level == 32 and &1.role == "guard"))
    refute Map.has_key?(p.inv, @r.ticket)
  end

  test "hạ hết quái → Kundun → thắng: vàng, ngọc, đồ; bước tiếp về Làng" do
    p =
      Enum.reduce(inside().tower.monsters, inside(), fn _, p -> win(p, hd(p.tower.monsters)) end)

    assert p.tower.kal.stage == "boss" and p.tower.kal.killed == @r.guards
    [boss] = p.tower.monsters
    assert boss.name == @r.boss.name and boss.elite and boss.level == 32 + @r.boss.add_level
    assert Kalima.battle_monster(boss).kal

    g0 = p.gold
    n0 = length(Map.get(p, :gear) || [])
    p = win(p, boss)
    assert p.tower.kal.done and p.gold > g0
    assert length(Map.get(p, :gear) || []) == n0 + 1

    {%{ok: true}, out} = Kalima.leave(p)
    assert out.tower == nil and out.pos.map == "village"
  end

  test "tự ra giữa chừng: thưởng theo số quái đã hạ" do
    p = inside()
    p = win(p, hd(p.tower.monsters))
    {%{ok: true, msg: m}, out} = Kalima.leave(p)
    assert m =~ "hạ 1 quái" and out.tower == nil and out.gold > p.gold
  end

  test "Dấu Ấn Kundun rơi từ quái thường cấp ≥ min_level" do
    assert Kalima.mark_chance(%{level: @r.mark_drop.min_level}) == @r.mark_drop.chance
    assert Kalima.mark_chance(%{level: 1}) == 0
    assert Kalima.mark_chance(%{level: 40, tower: true}) == 0
  end

  test "lưu / nạp lại đang đánh trong Kalima (trạng thái kal và trận có cờ kal / bc / ds)" do
    user = create_user()
    p = inside()
    [m | _] = p.tower.monsters

    {%{ok: true}, p} =
      Engine.start_with_monster(p, Data.zone_count() - 1, Kalima.battle_monster(m))

    p = put_in(p.battle[:encounter], %{tower: m.id})
    Characters.save!(user.id, p, "TEST")

    q = Characters.load(user.id)
    assert q.tower.kal.n == 3 and q.tower.kal.stage == "guards"
    assert q.battle.monster.kal
  end
end

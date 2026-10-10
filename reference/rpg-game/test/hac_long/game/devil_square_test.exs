defmodule HacLong.Game.DevilSquareTest do
  @moduledoc "Quảng Trường Quỷ (Phase 18 M1, docs/EVENTS_PHASE18.md)."
  use ExUnit.Case, async: false

  alias HacLong.Game.{DevilSquare, Engine, Rng, Tower}

  @r DevilSquare.rules()

  setup do
    on_exit(fn ->
      Rng.clear()
      Application.delete_env(:hac_long, :devil_square_always_open)
    end)

    :ok
  end

  defp player(attrs \\ %{}) do
    {:ok, p} = Engine.new_player("Thử", "dk")
    Map.merge(%{p | level: 40, gold: 100_000}, attrs)
  end

  # giờ Việt Nam hh:mm hôm nay → DateTime UTC
  defp vn(h, m), do: DateTime.new!(~D[2026-10-10], Time.new!(h, m, 0)) |> DateTime.add(-7 * 3600)

  test "lịch: mở ở các mốc lệch offset, cho vào trong entry_minutes phút" do
    open_h = @r.offset_hours
    assert DevilSquare.open?(vn(open_h, 0))
    assert DevilSquare.open?(vn(open_h, @r.entry_minutes - 1))
    refute DevilSquare.open?(vn(open_h, @r.entry_minutes))
    refute DevilSquare.open?(vn(open_h + 1, 0))
    assert DevilSquare.open?(vn(open_h + @r.every_hours, 5))
    # lần mở tiếp theo sau lúc đóng
    assert DevilSquare.next_open(vn(open_h, 30)) ==
             DateTime.to_unix(vn(open_h + @r.every_hours, 0))
  end

  test "mua vé, vào: cần cấp, vé, đang mở; mỗi đợt một lần" do
    now = vn(@r.offset_hours, 1)
    p = player()
    {%{ok: false}, _} = DevilSquare.enter(%{p | level: @r.min_level - 1}, now)
    {%{ok: false, msg: m}, _} = DevilSquare.enter(p, now)
    assert m =~ "Vé"
    {%{ok: false}, _} = DevilSquare.enter(p, vn(@r.offset_hours + 1, 0))

    {%{ok: true}, p} = DevilSquare.buy_ticket(p)
    assert p.gold == 100_000 - @r.ticket_price and p.inv[@r.ticket] == 1

    {%{ok: true}, q} = DevilSquare.enter(p, now)
    assert q.pos.map == Tower.map_id() and q.tower.floor == 1
    assert q.tower.ds.level == DevilSquare.tier_level(40)
    assert length(q.tower.monsters) == hd(@r.waves).count
    refute Map.has_key?(q.inv, @r.ticket)

    # cùng đợt: không vào lại được (dù có vé)
    q2 = %{q | tower: nil} |> Engine.add_item(@r.ticket)
    {%{ok: false, msg: m}, _} = DevilSquare.enter(q2, now)
    assert m =~ "đã vào"
  end

  test "thắng cộng điểm; hết quái thì sang đợt sau; đợt cuối có trùm; qua hết thì có món đồ" do
    now = vn(@r.offset_hours, 1)
    {_, p} = DevilSquare.buy_ticket(player())
    {_, p} = DevilSquare.enter(p, now)
    # đồng hồ giả của test ở quá khứ: cho lượt còn hạn so với giờ thật
    p = put_in(p.tower.ds.ends_at, DateTime.to_unix(DateTime.utc_now()) + 600)

    win = fn p, m ->
      b = %{over: true, result: "win", encounter: %{tower: m.id}}
      Tower.after_battle(%{p | battle: b}) |> Map.put(:battle, nil)
    end

    clear = fn p -> Enum.reduce(p.tower.monsters, p, &win.(&2, &1)) end

    p = clear.(p)
    assert p.tower.ds.score == hd(@r.waves).count * @r.score.monster
    {%{ok: true}, p} = DevilSquare.climb(p)
    assert p.tower.floor == 2

    p =
      Enum.reduce(3..length(@r.waves), clear.(p), fn _, p ->
        {%{ok: true}, p} = DevilSquare.climb(p)
        clear.(p)
      end)

    last = List.last(@r.waves)
    assert p.tower.floor == length(@r.waves)
    score = p.tower.ds.score
    assert score > 0

    {%{ok: true, msg: msg}, done} = DevilSquare.climb(p)
    assert done.tower == nil and done.pos.map == "village"
    assert msg =~ "qua hết" and msg =~ "#{score} điểm"
    assert done.ds_result == %{score: score, level: p.tower.ds.level}
    assert done.daily.ds_best == score
    assert length(done.gear) == length(p.gear) + 1
    assert done.gold > p.gold
    assert last.boss
  end

  test "gục ngã / hết giờ / tự rời: kết thúc, vẫn nhận thưởng theo điểm" do
    now = vn(@r.offset_hours, 1)
    {_, p} = DevilSquare.buy_ticket(player())
    {_, p} = DevilSquare.enter(p, now)
    p = put_in(p.tower.ds.score, 10)

    lost =
      Tower.after_battle(%{
        p
        | battle: %{over: true, result: "lose", encounter: %{tower: 1}, log: []}
      })

    assert lost.tower == nil and lost.ds_result.score == 10
    assert Enum.any?(lost.battle.log, &(&1.text =~ "gục ngã"))

    assert DevilSquare.expired?(p, DateTime.from_unix!(p.tower.ds.ends_at))
    {%{ok: true, msg: m}, q} = DevilSquare.finish(p, "hết giờ")
    assert m =~ "hết giờ" and q.tower == nil and q.gold > p.gold
  end

  test "thưởng theo điểm: vàng / kinh nghiệm tỉ lệ điểm, ngọc mỗi jewel_every điểm" do
    r0 = DevilSquare.reward(42, 0, false)
    assert r0.gold == 0 and r0.items == %{} and r0.gear == nil
    r = DevilSquare.reward(42, @r.reward.jewel_every * 2, false)
    assert Enum.sum(Map.values(r.items)) == 2

    assert r.gold ==
             round(Engine.base_gold(42) * @r.reward.gold_per_point * @r.reward.jewel_every * 2)
  end

  test "vé rơi từ quái thường cấp cao, không rơi trong tháp / đấu trường" do
    assert DevilSquare.ticket_chance(%{level: 35}) == @r.ticket_drop.chance
    assert DevilSquare.ticket_chance(%{level: 10}) == 0
    assert DevilSquare.ticket_chance(%{level: 40, tower: true}) == 0
    assert DevilSquare.ticket_chance(%{level: 40, pvp: true}) == 0
  end
end

defmodule HacLong.Game.AutoHuntCfgTest do
  @moduledoc "Tự đánh kiểu MU Helper: phạm vi săn, cách dùng kỹ năng, lọc đồ theo loại, lưu cài đặt."
  use ExUnit.Case, async: true

  alias HacLong.Game.{AutoHunt, Commands, Data, Engine, Gear}

  @r Data.rules().auto

  defp player(attrs \\ %{}) do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Thợ Săn", "cls" => "dk"})

    p
    |> Map.merge(%{pos: %{map: "forest_1", x: 13, y: 16}, inv: %{"potion_s" => 5}})
    |> Map.merge(attrs)
  end

  defp on(p, c) do
    {%{ok: true}, p} = AutoHunt.configure(p, Map.merge(%{"on" => true, "target" => "level"}, c))
    p
  end

  defp snap(monsters), do: %{monsters: monsters, players: [], nodes: []}
  defp bat(id, x, y), do: %{id: id, kind: "bat", x: x, y: y, boss: false, busy: false}

  defp fight(p, boss?) do
    {_, f} =
      Engine.start_with_monster(
        p,
        0,
        Engine.make_monster(%{level: 1, id: "bat", name: "Dơi"}, boss?)
      )

    Map.put(f, :auto, p.auto) |> Map.put(:mp, 999)
  end

  test "bật: lưu cài đặt theo nhân vật (chuỗi), phạm vi / kỹ năng / lọc sai thì về mặc định" do
    p =
      on(player(), %{"range" => 8, "skills" => "boss", "loot" => "pick", "keep" => ["exc", "zzz"]})

    assert %{range: 8, origin: [13, 16], skills: "boss", loot: "pick", keep: ["exc"]} = p.auto

    assert %{
             "range" => 8,
             "skills" => "boss",
             "loot" => "pick",
             "keep" => ["exc"],
             "target" => "level"
           } =
             p.auto_cfg

    bad = on(player(), %{"range" => 7, "skills" => "x", "loot" => "y"})
    assert %{range: 0, skills: "all", loot: "all"} = bad.auto
    assert bad.auto.range == @r.range_default
  end

  test "'good' cũ = lọc theo mặc định" do
    p = on(player(), %{"loot" => "good"})
    assert p.auto.loot == "pick" and p.auto.keep == @r.keep_default
  end

  test "phạm vi: chỉ đánh quái trong N ô quanh chỗ bật, hết quái thì về chỗ bật rồi đứng chờ" do
    p = on(player(), %{"range" => 4})
    # quái xa 10 ô: không đi tới, đang ở chỗ bật thì chờ
    assert :wait = AutoHunt.decide(p, snap([bat(1, 13, 6)]))
    # quái trong phạm vi: đi tới
    assert {:cmd, %{"act" => "move", "dir" => "up"}} = AutoHunt.decide(p, snap([bat(1, 13, 14)]))
    # đã đi xa chỗ bật, không còn quái trong phạm vi: quay về
    away = %{p | pos: %{p.pos | x: 15}}

    assert {:cmd, %{"act" => "move", "dir" => "left"}} =
             AutoHunt.decide(away, snap([bat(1, 13, 6)]))
  end

  test "kỹ năng: basic chỉ đánh thường, boss chỉ dùng kỹ năng với trùm, all dùng kỹ năng" do
    basic = on(player(), %{"skills" => "basic"})
    assert {:cmd, %{"act" => "attack"}} = AutoHunt.decide(fight(basic, false), nil)

    boss = on(player(), %{"skills" => "boss"})
    assert {:cmd, %{"act" => "attack"}} = AutoHunt.decide(fight(boss, false), nil)
    assert {:cmd, %{"act" => "skill"}} = AutoHunt.decide(fight(boss, true), nil)

    all = on(player(), %{"skills" => "all"})
    assert {:cmd, %{"act" => "skill"}} = AutoHunt.decide(fight(all, false), nil)
  end

  test "kỹ năng buff tung trước" do
    p = on(player(%{level: 30}), %{"skills" => "all"})
    p = Map.put(p, :skill_set, ["twisting_slash", "falling_slash", "greater_fortitude"])

    assert {:cmd, %{"act" => "skill", "skill" => "greater_fortitude"}} =
             AutoHunt.decide(fight(p, false), nil)
  end

  test "lọc đồ theo loại tích chọn; ngọc, nhẫn, cánh luôn giữ" do
    p = player()
    plain = Gear.resolve(Gear.new("item_1_0"))
    refute AutoHunt.good?(p, %{plain | exc: ["dmg"]}, ["luck"])
    assert AutoHunt.good?(p, %{plain | exc: ["dmg"]}, ["exc"])
    assert AutoHunt.good?(p, %{plain | anc: true}, ["anc"])
    assert AutoHunt.good?(p, %{plain | skill: true}, ["luck"])
    assert AutoHunt.good?(p, plain, ["cls"])
    refute AutoHunt.good?(p, plain, [])
    assert AutoHunt.good?(p, %{plain | slot: "ring"}, [])
  end
end

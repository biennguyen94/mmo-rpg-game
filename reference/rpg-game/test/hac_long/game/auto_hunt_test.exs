defmodule HacLong.Game.AutoHuntTest do
  @moduledoc "Phase 4 (B-31): quyết định của tự đánh (hàm thuần)."
  use ExUnit.Case, async: true

  alias HacLong.Game.{AutoHunt, Commands, Engine, Gear}

  defp player(attrs \\ %{}) do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Thợ Săn", "cls" => "dk"})

    # đồ khởi đầu đang mặc là món riêng: giữ chúng, thêm món của test vào sau
    attrs = if attrs[:gear], do: %{attrs | gear: Gear.list(p) ++ attrs.gear}, else: attrs

    p
    |> Map.merge(%{pos: %{map: "forest_1", x: 13, y: 16}, inv: %{"potion_s" => 5}})
    |> Map.merge(attrs)
  end

  defp on(p, c \\ %{}) do
    {%{ok: true}, p} = AutoHunt.configure(p, Map.merge(%{"on" => true, "target" => "level"}, c))
    p
  end

  defp snap(monsters, players \\ []), do: %{monsters: monsters, players: players, nodes: []}
  defp bat(x, y), do: %{id: 1, kind: "bat", x: x, y: y, boss: false, busy: false}

  test "bật: kiểm tra bản đồ, quái chọn, kẹp % theo RULES.auto" do
    p = player()
    {r, p2} = AutoHunt.configure(p, %{"on" => true, "target" => "bat", "hp" => 999, "mp" => -5})
    assert r.ok
    assert %{map: "forest_1", target: "bat", hp: 90, mp: 0, loot: "all"} = p2.auto

    assert {%{ok: false}, _} = AutoHunt.configure(p, %{"on" => true, "target" => "dragon"})

    home = player(%{pos: %{map: "home", x: 2, y: 2}})
    assert {%{ok: false}, _} = AutoHunt.configure(home, %{"on" => true, "target" => "level"})

    assert {%{ok: true}, off} = AutoHunt.configure(p2, %{"on" => false})
    refute Map.has_key?(off, :auto)
  end

  test "ngoài trận: đi tới quái hợp chọn lựa; quái khác loại thì bỏ qua" do
    p = on(player(), %{"target" => "bat"})
    assert {:cmd, %{"act" => "move", "dir" => "up"}} = AutoHunt.decide(p, snap([bat(13, 15)]))

    jackal = %{bat(13, 15) | kind: "jackal"}
    assert {:cmd, %{"act" => "move"} = c} = AutoHunt.decide(p, snap([jackal]))
    refute c["confirm"] && c["dir"] == "up"
  end

  test "đánh tất cả: mọi loại quái trên bản đồ, kể cả quái cao cấp hơn mình" do
    p = on(player(), %{"target" => "all"})
    assert p.auto.target == "all"
    strong = %{bat(13, 15) | kind: "jackal"}
    assert {:cmd, %{"act" => "move", "dir" => "up"}} = AutoHunt.decide(p, snap([strong]))
  end

  test "dừng khi có người tên đỏ, hết bình máu, rời bản đồ" do
    p = on(player())
    red = %{id: 9, name: "Sát Thủ", red: true, x: 1, y: 1}
    assert {:stop, "Có người tên đỏ" <> _} = AutoHunt.decide(p, snap([], [red]))

    assert {:stop, "Hết bình máu" <> _} = AutoHunt.decide(%{p | inv: %{}}, snap([]))

    moved = %{p | pos: %{p.pos | map: "forest_2"}}
    assert {:stop, "Đã rời bản đồ" <> _} = AutoHunt.decide(moved, snap([]))
  end

  test "máu dưới ngưỡng: uống bình (ngoài trận dùng 'use', trong trận 'potion')" do
    p = on(player(), %{"hp" => 50})
    max = Engine.derived(p).maxHp
    low = %{p | hp: div(max, 4)}
    assert {:cmd, %{"act" => "use", "id" => "potion_s"}} = AutoHunt.decide(low, snap([]))

    {_, fight} =
      Engine.start_with_monster(
        low,
        0,
        Engine.make_monster(%{level: 1, id: "bat", name: "Dơi"}, false)
      )

    fight = Map.put(fight, :auto, low.auto)
    assert {:cmd, %{"act" => "potion"}} = AutoHunt.decide(fight, nil)

    assert {:stop, "Hết bình máu" <> _} = AutoHunt.decide(%{fight | inv: %{}}, nil)
  end

  test "trận xong: thắng thì hủy đồ thường (lọc 'good') rồi rời trận; thua thì tắt" do
    g = Gear.new("item_1_0")
    p = on(player(%{gear: [g]}), %{"loot" => "good"})

    won = %{
      p
      | battle: %{over: true, result: "win", reward: %{gear_ids: [g.uid]}, log: [], monster: %{}}
    }

    # cùng loại với vũ khí đang mặc, không dòng nào: đồ thường
    refute AutoHunt.good?(won, Gear.resolve(g))
    uid = g.uid
    assert {:cmd, %{"act" => "discard", "id" => ^uid}} = AutoHunt.decide(won, nil)

    keep_all = put_in(won.auto.loot, "all")
    assert {:cmd, %{"act" => "leave"}} = AutoHunt.decide(keep_all, nil)

    lost = put_in(won.battle.result, "lose")
    assert {:stop, "Bạn đã gục" <> _} = AutoHunt.decide(lost, nil)
  end

  test "lọc 'good' giữ đồ Excellent / May mắn / nhiều dòng" do
    p = player()
    plain = Gear.resolve(Gear.new("item_1_0"))
    assert AutoHunt.good?(p, %{plain | exc: ["dmg"]})
    assert AutoHunt.good?(p, %{plain | luck: true})
    assert AutoHunt.good?(p, %{plain | opt: 2})
  end
end

defmodule HacLong.LeaderboardTest do
  use HacLong.DataCase, async: false

  alias HacLong.{Accounts, Leaderboard}
  alias HacLong.Game.{Characters, Commands}

  defp hero(name, attrs, cls \\ "elf") do
    {:ok, user} = Accounts.register(%{"username" => name, "password" => "matkhau1"})
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => cls})
    Characters.save!(user.id, Map.merge(p, attrs))
    user
  end

  test "xếp theo cấp, số quái đã hạ và ai hạ Hắc Long trước" do
    early = ~U[2026-10-01 10:00:00Z]
    a = hero("anna", %{level: 20, xp: 5, kills: 300})

    b =
      hero("binh", %{
        level: 20,
        xp: 90,
        kills: 100,
        victory: true,
        victory_at: DateTime.add(early, 60)
      })

    c = hero("chi_", %{level: 35, xp: 0, kills: 50, victory: true, victory_at: early})
    d = hero("dung", %{level: 3, xp: 0, kills: 900})

    assert Enum.map(Leaderboard.top(:level), & &1.name) == ~w(chi_ binh anna dung)
    assert Enum.map(Leaderboard.top(:kills), & &1.name) == ~w(dung anna binh chi_)
    assert Enum.map(Leaderboard.top(:dragon), & &1.name) == ~w(chi_ binh)
    assert Leaderboard.top(:tower) == []
    hero("thapcao", %{tower_best: 42})
    hero("thapthap", %{tower_best: 7})
    assert Enum.map(Leaderboard.top(:tower), & &1.tower_best) == [42, 7]
    assert [%{rank: 1}, %{rank: 2} | _] = Leaderboard.top(:level)
    assert length(Leaderboard.top(:level, 2)) == 2

    assert Leaderboard.level_rank(c.id) == 1
    assert Leaderboard.level_rank(b.id) == 2
    assert Leaderboard.level_rank(a.id) == 3
    assert Leaderboard.level_rank(d.id) == 4
    assert Leaderboard.level_rank(-1) == nil
  end

  test "bảng theo lớp (H14): chỉ người cùng lớp, hạng trong lớp; boards gom đủ bảng" do
    hero("elf1", %{level: 30})
    e2 = hero("elf2", %{level: 10})
    k1 = hero("kiem1", %{level: 20}, "dk")
    hero("kiem2", %{level: 25}, "dk")

    assert Enum.map(Leaderboard.top({:class, "dk"}), & &1.name) == ~w(kiem2 kiem1)
    assert Enum.map(Leaderboard.top({:class, "elf"}), & &1.name) == ~w(elf1 elf2)
    assert Leaderboard.top({:class, "mg"}) == []

    assert Leaderboard.me(k1.id) == %{level: 3, class: 2, cls: "dk"}
    assert Leaderboard.me(e2.id) == %{level: 4, class: 2, cls: "elf"}
    assert Leaderboard.me(-1) == nil

    b = Leaderboard.boards()
    assert Map.keys(b.class) |> Enum.sort() == ~w(dk dw elf mg)
    assert Enum.map(b.class["dk"], & &1.name) == ~w(kiem2 kiem1)
    assert Enum.all?(~w(level kills dragon tower guild guild_boss arena)a, &Map.has_key?(b, &1))
  end

  test "cache: trong chu kỳ trả bảng cũ, hết chu kỳ thì đọc lại" do
    Application.put_env(:hac_long, :leaderboard_cache, true)
    Leaderboard.clear()

    on_exit(fn ->
      Application.put_env(:hac_long, :leaderboard_cache, false)
      Leaderboard.clear()
    end)

    hero("som", %{level: 5})
    first = Leaderboard.boards(1000)
    hero("muon", %{level: 50})
    assert Leaderboard.boards(1010) == first
    refresh = HacLong.Game.Data.rules().leaderboard.refresh_s
    assert hd(Leaderboard.boards(1000 + refresh).level).name == "muon"
  end
end

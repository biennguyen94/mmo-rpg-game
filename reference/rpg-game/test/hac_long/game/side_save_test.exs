defmodule HacLong.Game.SideSaveTest do
  # Phase 15a / 16: nhân vật đang đánh ở bản đồ phụ lưu rồi nạp lại được (trận có `place`, `theme`)
  use HacLong.DataCase, async: false

  alias HacLong.Accounts
  alias HacLong.Game.{Characters, Commands, Data, Engine}

  test "lưu và nạp trận ở bản đồ phụ" do
    {:ok, user} = Accounts.register(%{"username" => "sideguy", "password" => "matkhau1"})
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Người Đi", "cls" => "dk"})
    p = %{p | pos: %{map: "side_02", x: 3, y: 8}, visited: ["side_01", "side_02"]}

    {%{ok: true}, p} =
      Engine.start_side_encounter(p, Data.side_monster("wild_hog"), "Đồng Cỏ Xanh 2", "forest")

    Characters.save!(user.id, p)

    q = Characters.load(user.id)

    assert q.battle.place == "Đồng Cỏ Xanh 2" and q.battle.theme == "forest" and
             q.battle.zone == nil

    assert q.battle.monster.id == "wild_hog"
    assert q.visited == ["side_01", "side_02"]
  end

  test "nhân vật lưu giữa trận đánh người (bản sao có hào quang, chuyển sinh, bình đã uống) nạp lại được" do
    {:ok, user} = Accounts.register(%{"username" => "slayguy", "password" => "matkhau1"})
    {_, a} = Commands.run(nil, %{"act" => "create", "name" => "Người Đánh", "cls" => "dk"})
    {_, b} = Commands.run(nil, %{"act" => "create", "name" => "Người Bị", "cls" => "elf"})
    b = Map.put(b, :rebirths, 3)
    {_, p} = Engine.start_with_monster(a, 0, HacLong.Slay.opponent(b, 2))
    p = p |> put_in([:battle, :pots_used], 1) |> put_in([:battle, :pot_at], 0)
    # khóa lạ chưa có atom (sinh lúc chạy): giữ chuỗi, không crash
    odd = "zz_moi_#{System.unique_integer([:positive])}"
    p = put_in(p, [:battle, :monster, :look], Map.put(p.battle.monster.look, odd, 1))

    Characters.save!(user.id, p)
    q = Characters.load(user.id)

    assert Map.has_key?(q.battle.monster.look, :aura)
    assert q.battle.monster.rebirths == 3
    assert q.battle.pots_used == 1 and q.battle.pot_at == 0
    assert q.battle.monster.look[odd] == 1
  end
end

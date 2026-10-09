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
end

defmodule HacLong.Game.AncAnnounceTest do
  # docs/FX_PLAN.md đợt 4: rơi đồ Thần thì báo cả server
  use ExUnit.Case, async: true

  alias HacLong.Game.{Engine, Gear, Session}

  test "thắng trận nhặt được đồ Thần: một dòng báo; đồ thường hoặc chưa xong trận: không" do
    {:ok, p} = Engine.new_player("Than", "dk")
    anc = %{Gear.new("item_8_33") | uid: "#ANC"} |> Map.put(:anc, true)
    plain = %{Gear.new("item_8_33") | uid: "#PLN"}
    {p, _} = Gear.add(p, anc)
    {p, _} = Gear.add(p, plain)
    old = %{p | battle: %{over: false}}
    done = fn ids -> %{p | battle: %{over: true, reward: %{gear_ids: ids}}} end

    assert [line] = Session.anc_announce(old, done.(["#ANC", "#PLN"]))
    assert line =~ "Than vừa nhặt được" and line =~ "Đồ Thần"
    assert Session.anc_announce(old, done.(["#PLN"])) == []
    assert Session.anc_announce(done.(["#ANC"]), done.(["#ANC"])) == []
  end
end

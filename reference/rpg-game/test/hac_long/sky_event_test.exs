defmodule HacLong.SkyEventTest do
  @moduledoc "DECISIONS \"Đồi Sáo Diều, Chim Lạc, Hắc Long\": Chim Lạc / Đàn Hạc / sao băng / Long Phượng Hội (tiến trình)."
  use HacLong.DataCase, async: false

  alias HacLong.SkyEvent
  alias HacLong.World.Maps

  test "Chim Lạc, Đàn Hạc hiện ở ô trời thả tới được, khác ô nhau; bay đi khi có người cảm hóa; báo mọi người" do
    spots = SkyEvent.spots()
    m = Maps.get(HacLong.Game.Kite.map_id())
    assert spots != [] and Enum.all?(spots, fn {x, y} -> Maps.sky?(m, x, y) end)

    Phoenix.PubSub.subscribe(HacLong.PubSub, SkyEvent.topic())
    %{bird: [x, y], birdLeft: left} = SkyEvent.summon(:bird)
    assert {x, y} in spots and left > 0
    assert_receive {:sky, %{bird: [^x, ^y]}}
    %{flock: [fx, fy]} = SkyEvent.summon(:flock)
    assert {fx, fy} != {x, y}
    assert SkyEvent.tiles() == {{x, y}, {fx, fy}}
    SkyEvent.fly_away()
    assert_receive {:sky, %{bird: nil}}
  end

  test "mưa sao băng: rơi ở ô đi được của đồi; ai nhặt trước được, nhặt lại thì không còn" do
    %{stars: stars} = SkyEvent.summon(:meteor)
    assert length(stars) >= HacLong.Game.Kite.rules().meteor.count
    [[x, y] | _] = stars
    assert Maps.walkable?(Maps.get(HacLong.Game.Kite.map_id()), x, y)
    assert SkyEvent.take_star({x, y}) == :ok
    assert SkyEvent.take_star({x, y}) == :error
  end
end

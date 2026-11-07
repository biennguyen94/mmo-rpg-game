defmodule HacLong.World.WeatherTest do
  # DECISIONS "Bản đồ đẹp hơn" (B5): thời tiết chung cả server, đổi theo giờ
  use ExUnit.Case, async: true

  alias HacLong.Game.Data
  alias HacLong.World.{Maps, Weather}

  test "vùng theo nền bản đồ; Làng, hồ riêng; tháp / sự kiện không có thời tiết" do
    assert Weather.region(Maps.get("village")) == "village"
    assert Weather.region(Maps.get("long_vuong_lake")) == "lake"
    assert Weather.region(Maps.get("forest_1")) == "forest"
    assert Weather.region(Maps.get("mountain_1")) == "mountain"
    assert Weather.region(Maps.get("tower")) == nil
  end

  test "cùng mốc giờ, cùng vùng thì như nhau; trong khoảng slot_min phút không đổi" do
    t = ~U[2026-11-07 10:05:00Z]
    m = Maps.get("forest_1")
    assert Weather.kind(m, t) == Weather.kind(Maps.get("forest_2"), t)
    assert Weather.kind(m, t) == Weather.kind(m, DateTime.add(t, 40 * 60))
  end

  test "bốc theo trọng số: mọi loại trong bảng, tỉ lệ gần trọng số" do
    for {region, opts} <- Data.rules().weather.regions do
      r = to_string(region)
      kinds = Enum.map(opts, &hd/1)
      total = opts |> Enum.map(&Enum.at(&1, 1)) |> Enum.sum()
      picks = for s <- 1..4000, do: Weather.pick(r, s)
      assert Enum.all?(picks, &(&1 in kinds))

      for [k, w] <- opts do
        share = Enum.count(picks, &(&1 == k)) / 4000
        assert_in_delta share, w / total, 0.04, "#{r} #{k}"
      end
    end
  end
end

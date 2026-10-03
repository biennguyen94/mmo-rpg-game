defmodule Mu.Game.RngUlidTest do
  use ExUnit.Case, async: true

  alias Mu.Game.Rng
  alias Mu.Ulid

  test "Rng: cùng seed cùng dãy; int gồm hai đầu; weighted theo trọng số" do
    seq = fn seed ->
      Enum.map_reduce(1..20, Rng.new(seed), fn _, r -> Rng.int(r, 8, 14) end) |> elem(0)
    end

    assert seq.(1) == seq.(1)
    refute seq.(1) == seq.(2)

    {all, _} = Enum.map_reduce(1..2000, Rng.new(5), fn _, r -> Rng.int(r, 8, 14) end)
    assert Enum.min(all) == 8 and Enum.max(all) == 14

    {picks, _} =
      Enum.map_reduce(1..4000, Rng.new(9), fn _, r -> Rng.weighted(r, [{:a, 3}, {:b, 1}]) end)

    assert_in_delta Enum.count(picks, &(&1 == :a)) / 4000, 0.75, 0.03
    assert {false, _} = Rng.chance(Rng.new(1), 0)
    assert {true, _} = Rng.chance(Rng.new(1), 1)
  end

  test "ULID: 26 ký tự Crockford, mã hóa đúng spec, sắp theo thời gian, không trùng" do
    assert Ulid.generate(0, <<0::80>>) == String.duplicate("0", 26)

    assert Ulid.generate(
             281_474_976_710_655,
             <<255, 255, 255, 255, 255, 255, 255, 255, 255, 255>>
           ) ==
             "7" <> String.duplicate("Z", 25)

    # ví dụ trong spec: 1469918176385 → "01ARYZ6S41"
    assert String.starts_with?(Ulid.generate(1_469_918_176_385, <<0::80>>), "01ARYZ6S41")
    a = Ulid.generate(1000)
    b = Ulid.generate(2000)
    assert a < b
    assert Ulid.valid?(a)
    refute Ulid.valid?("01ARYZ6S41IIIIIIIIIIIIIIII")
    ids = for _ <- 1..5000, do: Ulid.generate()
    assert length(Enum.uniq(ids)) == 5000
  end
end

defmodule Mu.Game.PvpTest do
  @moduledoc "P4-M1: bảng quyết định PvP / PK / tự vệ (hàm thuần, P4-2 / P4-3)."
  use ExUnit.Case, async: true

  alias Mu.Game.{Config, Pvp}

  defp pl(cid, attrs \\ %{}),
    do:
      Map.merge(
        %{
          character_id: cid,
          level: 10,
          x: 40,
          y: 31,
          pk_points: 0,
          rights: %{},
          aggressor_until: nil
        },
        attrs
      )

  test "trạng thái theo điểm (pk.warningAt 1, murdererAt 2)" do
    assert {Config.get(["pk", "warningAt"]), Config.get(["pk", "murdererAt"])} == {1, 2}
    assert Enum.map([0, 1, 2, 7], &Pvp.state/1) == ~w(NORMAL WARNING MURDERER MURDERER)
  end

  test "đánh được: cả hai cấp ≥ 6, ngoài safe zone, không phải chính mình" do
    out = fn _, _ -> false end
    assert :ok = Pvp.check_attack(pl("a"), pl("b"), out)
    assert {:error, "INVALID_TARGET"} = Pvp.check_attack(pl("a"), pl("a"), out)
    assert {:error, "REQUIREMENT_NOT_MET"} = Pvp.check_attack(pl("a", %{level: 5}), pl("b"), out)
    assert {:error, "REQUIREMENT_NOT_MET"} = Pvp.check_attack(pl("a"), pl("b", %{level: 5}), out)
    # một trong hai đứng trong safe zone
    in_town = fn x, _ -> x < 25 end
    assert {:error, "FORBIDDEN"} = Pvp.check_attack(pl("a", %{x: 20}), pl("b"), in_town)
    assert {:error, "FORBIDDEN"} = Pvp.check_attack(pl("a"), pl("b", %{x: 20}), in_town)
  end

  test "tự vệ: A đánh B (NORMAL) → B được đánh trả A 30 s, A là kẻ gây sự; đòn của A làm mới; B đánh trả không thành kẻ gây sự" do
    {a, b} = Pvp.on_hit(pl("a"), pl("b"), 1_000)
    assert a.aggressor_until == 31_000
    assert b.rights == %{"a" => 31_000}
    assert Pvp.retaliating?(b, a, 30_999)
    refute Pvp.retaliating?(b, a, 31_000)

    {a, b} = Pvp.on_hit(a, b, 20_000)
    assert {a.aggressor_until, b.rights["a"]} == {50_000, 50_000}

    # B đánh trả: không sinh quyền cho A, B không thành kẻ gây sự
    {b2, a2} = Pvp.on_hit(b, a, 21_000)
    assert {b2.aggressor_until, a2.rights} == {nil, %{}}
  end

  test "đánh / giết WARNING hoặc MURDERER không sinh tự vệ, không tính PK" do
    for pts <- [1, 2] do
      {a, v} = Pvp.on_hit(pl("a"), pl("v", %{pk_points: pts}), 0)
      assert {a.aggressor_until, v.rights} == {nil, %{}}
      assert Pvp.pk_gain(pl("a"), pl("v", %{pk_points: pts}), 0) == 0
    end
  end

  test "PK: giết NORMAL +1; giết khi đang tự vệ không tính" do
    assert Pvp.pk_gain(pl("a"), pl("b"), 0) == 1
    b = pl("b", %{rights: %{"a" => 30_000}})
    assert Pvp.pk_gain(b, pl("a"), 10_000) == 0
    assert Pvp.pk_gain(b, pl("a"), 30_000) == 1
  end

  test "rơi đồ theo trạng thái nạn nhân: NORMAL 0, WARNING 0,1, MURDERER 0,5; sát thương × 0,5, tối thiểu 1" do
    assert Enum.map([0, 1, 5], &Pvp.drop_chance/1) == [0, 0.1, 0.5]
    assert Enum.map([0, 1, 2, 9], &Pvp.damage/1) == [0, 1, 1, 4]
  end

  test "giảm 1 điểm mỗi 60 phút từ last_pk_at; mốc dời theo số lần giảm; hết điểm thì nil" do
    t0 = ~U[2026-10-03 00:00:00.000000Z]
    at = fn min -> DateTime.add(t0, min * 60, :second) end
    assert Pvp.decay(0, t0, at.(999)) == {0, nil}
    assert Pvp.decay(2, t0, at.(59)) == {2, t0}
    assert Pvp.decay(2, t0, at.(61)) == {1, at.(60)}
    assert Pvp.decay(3, t0, at.(150)) == {1, at.(120)}
    assert Pvp.decay(2, t0, at.(500)) == {0, nil}
    # dữ liệu cũ thiếu mốc: bắt đầu đếm từ bây giờ
    assert Pvp.decay(2, nil, at.(5)) == {2, at.(5)}
  end
end

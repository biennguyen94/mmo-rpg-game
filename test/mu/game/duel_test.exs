defmodule Mu.Game.DuelTest do
  @moduledoc "P4-M2: trạng thái duel thuần (mời, nhận, từ chối, hủy, hết giờ, đi xa) + quan hệ trong Pvp."
  use ExUnit.Case, async: true

  alias Mu.Game.{Config, Duel, Pvp}

  test "config duel (P4-4)" do
    assert Config.get(["duel"]) == %{
             "requestRange" => 10,
             "inviteSeconds" => 30,
             "maxSeconds" => 180,
             "maxDistance" => 20
           }
  end

  test "mời → nhận: hai mục đối xứng; lời mời dùng một lần; hết hạn 30 s" do
    {:ok, d} = Duel.request(Duel.new(), "a", "b", 0)
    assert {:error, "INVALID_TARGET"} = Duel.accept(d, "b", "a", 30_000, {0, 0})
    {:ok, d2} = Duel.accept(d, "b", "a", 29_999, {5, 5})
    assert {Duel.opponent(d2, "a"), Duel.opponent(d2, "b")} == {"b", "a"}
    assert %{ends_at: 209_999, center: {5, 5}} = d2.active["a"]
    assert {:error, "INVALID_TARGET"} = Duel.accept(d2, "b", "a", 1, {0, 0})
    # đang duel không mời / được mời thêm
    assert {:error, "FORBIDDEN"} = Duel.request(d2, "c", "a", 0)
    assert {:error, "FORBIDDEN"} = Duel.request(d2, "a", "c", 0)
    assert {:error, "INVALID_TARGET"} = Duel.request(d2, "c", "c", 0)
  end

  test "từ chối, hủy lời mời, kết thúc, hết giờ, bỏ lời mời hết hạn" do
    {:ok, d} = Duel.request(Duel.new(), "a", "b", 0)
    {:ok, d} = Duel.request(d, "a", "c", 0)
    {:ok, d1} = Duel.decline(d, "b", "a", 10)
    assert {:error, "INVALID_TARGET"} = Duel.decline(d1, "b", "a", 10)
    {d2, tos} = Duel.cancel_requests(d, "a")
    assert Enum.sort(tos) == ["b", "c"]
    assert {:error, "INVALID_TARGET"} = Duel.accept(d2, "c", "a", 1, {0, 0})

    {:ok, d3} = Duel.accept(d, "b", "a", 0, {0, 0})
    assert Duel.expired(d3, 179_999) == []
    assert Duel.expired(d3, 180_000) == [{"a", "b"}]
    assert {d4, "b"} = Duel.finish(d3, "a")
    assert d4.active == %{}
    assert Duel.prune(d, 30_000).requests == %{}
  end

  test "cách nhau quá 20 ô: người xa điểm bắt đầu hơn thua" do
    {:ok, d} = Duel.request(Duel.new(), "a", "b", 0)
    {:ok, d} = Duel.accept(d, "b", "a", 0, {10, 10})
    near = %{"a" => {9, 10}, "b" => {29, 10}}
    assert Duel.too_far(d, &near[&1]) == []
    far = %{"a" => {9, 10}, "b" => {31, 10}}
    assert Duel.too_far(d, &far[&1]) == [{"b", "a"}]
  end

  test "Pvp theo quan hệ: duel không tự vệ / không PK; cùng nhóm và người ngoài duel bị chặn" do
    pl = fn cid ->
      %{
        character_id: cid,
        level: 10,
        x: 40,
        y: 31,
        pk_points: 0,
        rights: %{},
        aggressor_until: nil
      }
    end

    out = fn _, _ -> false end
    assert :ok = Pvp.check_attack(pl.("a"), pl.("b"), out, :duel)
    assert {:error, "FORBIDDEN"} = Pvp.check_attack(pl.("a"), pl.("b"), out, :party)
    assert {:error, "FORBIDDEN"} = Pvp.check_attack(pl.("a"), pl.("b"), out, :blocked)
    assert {pl.("a"), pl.("b")} == Pvp.on_hit(pl.("a"), pl.("b"), 0, :duel)
    assert Pvp.pk_gain(pl.("a"), pl.("b"), 0, :duel) == 0
  end
end

defmodule HacLong.RealmLadderTest do
  @moduledoc "Thang vùng co giãn theo server (DECISIONS \"Thang vùng co giãn theo server\")."
  use HacLong.DataCase, async: false

  alias HacLong.RealmLadder
  alias HacLong.Game.{Commands, Data, Engine}
  alias HacLong.World
  alias HacLong.World.{Maps, MapServer}

  @r Data.rules().realms
  @l @r.ladder
  @base Enum.to_list(1..10)

  setup do
    on_exit(fn -> RealmLadder.put(@base) end)
    :ok
  end

  test "mẫu ít người: giữ thang cũ" do
    assert {@base, []} = RealmLadder.compute(List.duplicate(20, @l.min_sample - 1), @base)
  end

  test "server mới (đa số chuyển sinh thấp): thang gốc" do
    sample = for i <- 1..100, do: rem(i, 6)
    {ks, _} = RealmLadder.compute(sample, @base)
    assert ks == @base
  end

  test "server lâu năm: dời lên theo phân vị, mỗi lần tối đa ±max_step, vùng sau ≥ vùng trước + 1, không dưới gốc" do
    sample = for i <- 0..199, do: 8 + rem(i * 7, 23)
    {ks1, targets} = RealmLadder.compute(sample, @base)
    assert length(targets) == 10
    # một lần chỉ dời tối đa max_step
    assert Enum.all?(Enum.zip(ks1, @base), fn {k, b} -> k - b <= @l.max_step and k >= b end)
    assert Enum.chunk_every(ks1, 2, 1, :discard) |> Enum.all?(fn [a, b] -> b >= a + 1 end)

    # tính lại nhiều ngày thì hội tụ về mục tiêu (vẫn giữ bậc tăng dần)
    ks =
      Enum.reduce(1..20, ks1, fn _, prev -> elem(RealmLadder.compute(sample, prev), 0) end)

    for {k, {t, i}} <- Enum.zip(ks, Enum.with_index(targets, 1)), do: assert(k >= max(t, i))
    assert hd(ks) == max(1, hd(targets))
    assert Enum.chunk_every(ks, 2, 1, :discard) |> Enum.all?(fn [a, b] -> b >= a + 1 end)
  end

  test "người chơi rời đi (mẫu yếu đi): thang hạ dần, không dưới gốc" do
    high = Enum.to_list(21..30)
    sample = for i <- 1..50, do: rem(i, 4)
    {ks, _} = RealmLadder.compute(sample, high)
    assert Enum.zip(ks, high) |> Enum.all?(fn {k, h} -> k >= h - @l.max_step end)
    ks = Enum.reduce(1..30, ks, fn _, prev -> elem(RealmLadder.compute(sample, prev), 0) end)
    assert ks == @base
  end

  test "đặt tay: vùng đặt tay theo số quản trị (không dưới gốc)" do
    sample = for i <- 1..100, do: rem(i, 6)
    {ks, _} = RealmLadder.compute(sample, @base, %{3 => 7, 5 => 1})
    assert Enum.at(ks, 2) == 7 and Enum.at(ks, 4) == 5
  end

  test "đường cong: tới mức 10 như vùng cũ, sau 10 dốc riêng" do
    for k <- [1, 5, 10] do
      assert_in_delta RealmLadder.curve(k, :hp), 1 + @r.mult_per_realm * k, 1.0e-9
      assert_in_delta RealmLadder.curve(k, :atk), 1 + @r.atk_mult_per_realm * k, 1.0e-9
    end

    assert_in_delta RealmLadder.curve(20, :hp),
                    1 + @r.mult_per_realm * 10 + @l.hp_after * 10,
                    1.0e-9
  end

  test "quái: thang gốc giữ nguyên; dời thang thì mạnh lên; người tụt hậu bị đánh nhẹ hơn" do
    spec = Data.side_monster("r1_fire_elemental")
    assert RealmLadder.adjust(spec, 1, 1, @base) == spec

    ks = [12 | Enum.to_list(13..21)]
    up = RealmLadder.adjust(spec, 1, 12, ks)
    assert up.mult > spec.mult and up.atk_mult > spec.atk_mult and up.level == spec.level + 110
    assert up.ladder == 12

    weak = RealmLadder.adjust(spec, 1, 1, ks)
    assert weak.mult == up.mult and weak.atk_mult < up.atk_mult

    lord = Data.side_monster("r1_" <> "hell_hound") || spec
    assert RealmLadder.adjust(lord, 1, 12, ks).mult >= up.mult * 0.9
  end

  test "vào trận ở vùng chuyển sinh: quái mạnh theo thang" do
    uid = System.unique_integer([:positive])
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Thang Vùng", "cls" => "dk"})
    p = p |> Map.put(:level, 50) |> Map.put(:rebirths, 12)
    map = Maps.get("realm_01")
    MapServer.clear_monsters("realm_01")
    on_exit(fn -> MapServer.leave("realm_01", uid) end)

    {x, y} =
      hd(
        for yy <- 2..(map.height - 3),
            xx <- 2..(map.width - 3),
            Maps.walkable?(map, xx, yy) and Maps.walkable?(map, xx + 1, yy) and
              Maps.portal_at(map, xx, yy) == nil and Maps.portal_at(map, xx + 1, yy) == nil,
            do: {xx, yy}
      )

    kind = hd(map.spawns).monster

    fight = fn ->
      MapServer.clear_monsters("realm_01")
      MapServer.put_monster("realm_01", kind, {x + 1, y})
      p = %{p | pos: %{map: "realm_01", x: x, y: y}}
      World.enter(p, uid)
      {%{ok: true}, f} = World.move(p, uid, "right", true)
      MapServer.leave("realm_01", uid)
      f.battle.monster
    end

    base_m = fight.()
    RealmLadder.put([12 | Enum.to_list(13..21)])
    up_m = fight.()
    assert up_m.maxHp > base_m.maxHp and up_m.atk > base_m.atk
    assert Engine.derived(p).maxHp > 0
  end

  test "lấy mẫu: mỗi tài khoản một nhân vật, cấp đủ, không bot; ít người thì giữ thang" do
    mk = fn lv, cs, role ->
      {:ok, u} =
        HacLong.Accounts.register(%{
          "username" => "lad#{System.unique_integer([:positive])}",
          "password" => "matkhau1"
        })

      if role,
        do:
          Repo.update!(Ecto.Changeset.change(Repo.get!(HacLong.Accounts.User, u.id), role: role))

      {_, p} =
        Commands.run(nil, %{
          "act" => "create",
          "name" => "L#{System.unique_integer([:positive]) |> rem(100_000)}",
          "cls" => "dk"
        })

      HacLong.Game.Characters.save!(u.id, %{p | level: lv} |> Map.put(:rebirths, cs), "TEST")
    end

    before = RealmLadder.recompute().sample
    mk.(45, 12, nil)
    mk.(45, 15, nil)
    # dưới cấp, bot: không tính
    mk.(20, 30, nil)
    mk.(45, 30, "bot")
    st = RealmLadder.recompute()
    assert st.sample == before + 2
    assert st.ks == @base
  end
end

defmodule HacLong.Game.Ancient15gTest do
  @moduledoc """
  Phase 15g (docs/ITEMS_PHASE15B.md §10): đồ Bộ Thần.
  """
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine, Gear, Rng}

  setup do
    on_exit(&Rng.clear/0)
    :ok
  end

  @anc Data.rules().ancient
  # bộ Đồng (bậc 2) của Kiếm Sĩ
  @bronze ~w(item_7_0 item_8_0 item_9_0 item_10_0 item_11_0)

  defp player(cls) do
    {:ok, p} = Engine.new_player("Thử", cls)
    %{p | level: 20}
  end

  defp wear_all(p, gs) do
    Enum.reduce(gs, p, fn g, p ->
      {p, :kept} = Gear.add(p, g)
      {%{ok: true}, p} = Engine.equip(p, g.uid)
      p
    end)
  end

  defp piece(base, i, anc?) do
    g = %{Gear.new(base, 1, %{}) | uid: "#P#{i}"}
    if anc?, do: Map.put(g, :anc, true), else: g
  end

  test "rơi: chỉ món bộ giáp bốc đồ Thần, theo loại quái; vũ khí / đấu trường không" do
    armor = Gear.new("item_8_0", 1, %{})
    Rng.put_sequence([0.0])
    assert %{anc: true} = Gear.ancient(armor, %{boss: true})

    Rng.put_sequence([0.99])
    refute Map.has_key?(Gear.ancient(armor, %{boss: true}), :anc)

    sword = Gear.new("item_0_3", 1, %{})
    assert Gear.ancient(sword, %{boss: true}) == sword
    assert Gear.ancient(armor, %{pvp: true}) == armor
    assert Gear.anc_chance(%{elite: true}) == @anc.chance.elite
  end

  test "món Thần: phòng thủ +piece_def_pct, giá × price_mult, lưu / nạp" do
    g = Gear.new("item_8_0", 1, %{})
    a = Map.put(g, :anc, true)
    base_def = Data.item("item_8_0").def
    assert Gear.resolve(a).def == round(base_def * (1 + @anc.piece_def_pct))
    assert Gear.resolve(a).anc and not Gear.resolve(g).anc
    assert Gear.price(a) == Gear.price(g) * @anc.price_mult

    [l] = a |> Jason.encode!() |> Jason.decode!() |> List.wrap() |> Gear.load()
    assert l.anc
  end

  test "thưởng Bộ Thần theo số món Thần cùng bộ, cộng dồn các mức" do
    p = player("dk")
    [b2, b3, full] = @anc.bonus

    two = wear_all(p, for({b, i} <- Enum.with_index(@bronze), do: piece(b, i, i < 2)))
    assert %{have: 2, need: 5, atk_pct: a2, def_pct: 0} = Engine.ancient_bonus(two)
    assert a2 == b2.atk_pct

    three = wear_all(p, for({b, i} <- Enum.with_index(@bronze), do: piece(b, i, i < 3)))
    assert Engine.ancient_bonus(three).def_pct == b3.def_pct

    all = wear_all(p, for({b, i} <- Enum.with_index(@bronze), do: piece(b, i, true)))
    ab = Engine.ancient_bonus(all)
    assert ab.atk_pct == b2.atk_pct + full.atk_pct and ab.hp == full.hp
    assert ab.def_pct == b3.def_pct + full.def_pct

    none = wear_all(p, for({b, i} <- Enum.with_index(@bronze), do: piece(b, i, false)))
    assert Engine.ancient_bonus(none).name == nil

    # máu và tấn công tăng thật
    assert Engine.derived(all).maxHp > Engine.derived(none).maxHp
    assert Engine.derived(all).atk > Engine.derived(none).atk
  end
end

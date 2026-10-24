defmodule HacLong.Game.StatEffectTest do
  @moduledoc """
  Mọi chỉ số ở bảng Nhân vật có tác dụng thật trong trận (anh hỏi 2026-10-24): cánh (% sát thương, % hấp thụ, bỏ qua phòng thủ,
  dòng máu / MP), Excellent (chí mạng, giảm sát thương, né, phản sát thương) — so sát thương khi bật / tắt từng chỉ số.
  """
  use ExUnit.Case, async: true

  alias HacLong.Admin
  alias HacLong.Arena
  alias HacLong.Game.{Commands, Engine, Gear, Rng}

  setup do
    on_exit(&Rng.clear/0)
  end

  defp op(p, name, params) do
    {:ok, f} = Admin.build(name, params)
    {:ok, p, _} = f.(p)
    p
  end

  defp hero do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Thu", "cls" => "dk"})

    p =
      p
      |> op("set_level", %{"level" => 50})
      |> op("add_stats", %{"str" => 400, "agi" => 100, "vit" => 200})

    %{p | pet: nil}
  end

  defp wear(p, args) do
    p = op(p, "give_gear", args)
    g = List.last(Gear.bag(p))
    {%{ok: true}, p} = Commands.run(p, %{"act" => "equip", "id" => g.uid})
    p
  end

  @dummy %{
    id: "dummy",
    name: "Bù nhìn",
    level: 50,
    atk: 2000,
    def: 800,
    maxHp: 100_000_000,
    hp: 100_000_000,
    crit: 0.0,
    dodge: 0.0,
    xp: 0,
    gold: 0,
    boss: false,
    elite: false,
    special: nil,
    on_hit: nil,
    element: nil
  }

  # một đòn thường (số ngẫu nhiên cố định: trúng, không chí mạng, đòn giữa khoảng) → {gây, nhận}
  defp exchange(p, m \\ @dummy) do
    {_, q} = Engine.start_with_monster(%{p | hp: 1_000_000_000}, 1, m)
    q = put_in(q.battle.monster, Map.merge(q.battle.monster, m))
    Rng.put_sequence(List.duplicate(0.5, 40))
    {_, q2} = Engine.act(q, "attack", nil)
    {m.hp - q2.battle.monster.hp, 1_000_000_000 - q2.hp}
  end

  test "cánh: % sát thương tăng đòn gây, % hấp thụ giảm đòn nhận; ép +11 mạnh hơn +0" do
    base = hero()
    {g0, t0} = exchange(base)
    w0 = wear(base, %{"base" => "wing_dk_3"})
    w11 = wear(base, %{"base" => "wing_dk_3", "up" => 11})
    {g1, t1} = exchange(w0)
    {g2, t2} = exchange(w11)
    d = Engine.derived(w11)
    assert d.wingDmg > Engine.derived(w0).wingDmg and d.wingAbsorb > Engine.derived(w0).wingAbsorb
    assert g1 > g0 and g2 > g1
    assert t1 < t0 and t2 < t1
  end

  test "dòng cánh: bỏ qua phòng thủ tăng đòn gây; máu / MP tăng máu / MP tối đa" do
    base = wear(hero(), %{"base" => "wing_dk_3", "up" => 11})
    ign = wear(hero(), %{"base" => "wing_dk_3", "up" => 11, "wopt" => "ignore_def"})
    assert Engine.derived(ign).ignoreDef > 0
    assert elem(exchange(ign), 0) > elem(exchange(base), 0)

    hp = wear(hero(), %{"base" => "wing_dk_3", "up" => 11, "wopt" => "hp"})
    mp = wear(hero(), %{"base" => "wing_dk_3", "up" => 11, "wopt" => "mp"})
    assert Engine.derived(hp).maxHp > Engine.derived(base).maxHp
    assert Engine.derived(mp).maxMp > Engine.derived(base).maxMp
  end

  test "Excellent giảm sát thương làm đòn nhận nhỏ hơn" do
    base = wear(hero(), %{"base" => "item_8_33"})
    red = wear(hero(), %{"base" => "item_8_33", "exc" => ["dmg_red"]})
    assert Engine.derived(red).excAbsorb > 0
    assert elem(exchange(red), 1) < elem(exchange(base), 1)
  end

  test "đánh bản sao người (đồ sát, PK cược): cánh hấp thụ của đối thủ giảm đòn, phản sát thương của đối thủ đánh lại" do
    me = hero()
    foe = wear(hero(), %{"base" => "item_8_33", "exc" => ["reflect"]})
    plain = Arena.opponent(hero(), 2)
    clone = Arena.opponent(foe, 2)
    assert clone.reflect > 0

    {_, q} = Engine.start_with_monster(%{me | hp: 1_000_000}, 1, clone)
    Rng.put_sequence(List.duplicate(0.5, 40))
    {_, q2} = Engine.act(put_in(q, [:battle, :live], true), "attack", nil)
    assert q2.hp < 1_000_000
    assert Enum.any?(q2.battle.log, &(&1.text =~ "phản lại"))

    # cánh của đối thủ: bản sao nhận ít hơn
    winged = Arena.opponent(wear(hero(), %{"base" => "wing_dk_3", "up" => 11}), 2)
    assert winged.taken < plain.taken
  end
end

defmodule HacLong.Game.PvpCrossTest do
  @moduledoc """
  Đồ sát: hiệu ứng chéo giữa hai người (DECISIONS "Đồ sát: hiệu ứng chéo"). Mỗi bên đánh bản sao của bên kia;
  choáng / suy yếu / độc đặt lên bản sao chuyển sang người kia, đòn vào người kia đi qua thủ thế / khiên / bất tử /
  Long Vương của họ.
  """
  use ExUnit.Case, async: true

  alias HacLong.{Admin, Arena}
  alias HacLong.Game.{Commands, Engine, Rng}

  defp hero(name, cls, pet? \\ false) do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => cls})
    p = %{p | level: 40, stats: Map.new(p.stats, fn {k, v} -> {k, v * 4} end), pet: nil}
    p = HacLong.Game.Mastery.maxed(p)

    if pet? do
      {:ok, f} = Admin.build("give_pet", %{"id" => "long_vuong", "level" => 20})
      {:ok, p, _} = f.(p)
      p
    else
      p
    end
  end

  # `p` trong trận đồ sát với bản sao `foe`
  defp in_fight(p, foe, uid) do
    {_, p} = Engine.start_with_monster(%{p | mp: 9_999}, 1, Arena.opponent(foe, uid))
    put_in(p, [:battle, :live], true)
  end

  defp with_fx(p, list),
    do: put_in(p, [:battle, :effects], %{player: list, monster: []})

  test "choáng đặt lên bản sao chuyển sang người kia: mất lượt, rồi kháng choáng stun_immune lượt" do
    a = hero("Choang", "dk")
    b = hero("Bia", "dk")
    pa = in_fight(a, b, 2)
    pb = in_fight(b, a, 1)

    Rng.put_sequence([0.3])
    {_, pa} = Engine.act(pa, "skill", "falling_slash")
    {pa, debuffs} = Engine.pvp_take_debuffs(pa)
    assert [%{id: "stun"}] = debuffs
    # đã tách khỏi trận người đánh
    refute Enum.any?(pa.battle.effects.monster, &(&1.id == "stun"))

    pb = Engine.pvp_receive(pb, debuffs)
    assert Engine.stunned?(pb)
    {_, pb} = Engine.act(pb, "attack")
    assert List.last(pb.battle.log).text == "💫 Bạn bị choáng, mất một lượt."
    refute Engine.stunned?(pb)

    # vừa thoát choáng: người đánh ngắm thấy đối thủ đang kháng, choáng không vào
    pa = pa |> put_in([:battle, :cds], []) |> Engine.pvp_aim(pb)
    {_, pa} = Engine.act(pa, "skill", "falling_slash")
    assert List.last(Enum.filter(pa.battle.log, &(&1.kind == "info"))).text =~ "kháng được"
    {_, debuffs} = Engine.pvp_take_debuffs(pa)
    refute Engine.stunned?(Engine.pvp_receive(pb, debuffs))
  end

  test "suy yếu chuyển sang người kia: đòn của họ yếu đi; độc trừ máu đầu lượt của họ" do
    a = hero("Yeu", "dk")
    b = in_fight(hero("Manh", "dk"), a, 1) |> put_in([:battle, :monster, :dodge], 0.0)

    hit = fn p ->
      Rng.put_sequence([0.99])
      {_, p2} = Engine.act(p, "attack")
      p.battle.monster.hp - p2.battle.monster.hp
    end

    full = hit.(b)
    weak = hit.(Engine.pvp_receive(b, [%{id: "weaken", turns: 2, power: 0.3}]))
    assert weak < full

    p = Engine.pvp_receive(b, [%{id: "poison", turns: 3, power: 40}])
    p = Engine.pvp_turn_start(p)
    assert p.hp == b.hp - 40
    assert List.last(p.battle.log).text =~ "Bạn mất 40 máu vì trúng độc"
  end

  test "đòn vào người bị đánh đi qua thủ thế, khiên, bất tử, Long Vương của họ" do
    v0 = Engine.pvp_victim(hero("Thu", "dk"), nil, 1000)
    assert {%{hp: 900}, 100} = Engine.pvp_defend(v0, 100)

    # Long Vương: Vảy Rồng giảm sát thương nhận
    v = Engine.pvp_victim(hero("Thu", "dk", true), nil, 1000)
    assert {%{hp: hp}, real} = Engine.pvp_defend(v, 100)
    assert real < 100 and hp == 1000 - real
    v = v0

    {g, real} = Engine.pvp_defend(with_fx(v, [%{id: "guard", turns: 2, power: 0.5}]), 100)
    assert real == 50 and g.hp == 950

    {sh, real} = Engine.pvp_defend(with_fx(v, [%{id: "shield", turns: 3, power: 80}]), 100)
    assert real == 20 and sh.hp == 980
    assert Engine.pvp_fx(sh).effects == []

    # bất tử trước, Long Vương sau (mỗi trận một lần)
    {u, _} = Engine.pvp_defend(with_fx(v, [%{id: "undying", turns: 3, power: 0.3}]), 5000)
    assert u.hp > 0 and Engine.pvp_fx(u).effects == []
    v = Engine.pvp_victim(hero("Thu", "dk", true), nil, 1000)
    {r1, _} = Engine.pvp_defend(v, 5000)
    assert r1.hp > 0 and Engine.pvp_fx(r1).pet_revived
    {r2, _} = Engine.pvp_defend(r1, 99_999)
    assert r2.hp <= 0
  end

  test "đánh người: mỗi trận chỉ được cứu một lần (Bất Tử hoặc Long Vương), dùng lại Bất Tử không cứu thêm" do
    v = Engine.pvp_victim(hero("Mot", "dk", true), nil, 1000)
    undying = [%{id: "undying", turns: 3, power: 0.3}]

    # Bất Tử cứu trước, sau đó Long Vương không cứu nữa
    {u, _} = Engine.pvp_defend(with_fx(v, undying), 5000)
    assert u.hp > 0 and Engine.pvp_fx(u).pet_revived
    {u2, _} = Engine.pvp_defend(u, 99_999)
    assert u2.hp <= 0

    # đã được cứu: dùng lại Bất Tử cũng không cứu
    {u3, _} = Engine.pvp_defend(put_in(u, [:battle, :effects, :player], undying), 99_999)
    assert u3.hp <= 0
  end

  test "đánh người: bình máu hồi × potion_mult, mỗi potion_cd lượt uống một lần; đánh quái giữ nguyên" do
    r = Engine.pvp_rules()
    a = hero("Binh", "dk") |> Map.put(:inv, %{"potion_l" => 5})
    low = fn p -> %{p | hp: 100} end

    pvp = in_fight(a, hero("Kia", "dk"), 2) |> low.()
    {_, pvp1} = Engine.act(pvp, "potion")
    # cùng đối thủ nhưng bỏ cờ `pvp`: như đánh quái
    mob = Map.put(Arena.opponent(hero("Kia", "dk"), 2), :pvp, nil)
    {_, pve} = Engine.start_with_monster(%{a | mp: 9_999}, 1, mob)
    {_, pve1} = Engine.act(low.(pve), "potion")

    healed = fn p ->
      t = Enum.find(p.battle.log, &(&1.text =~ "Bạn uống")).text
      [_, n] = Regex.run(~r/hồi (\d+) máu/u, t)
      String.to_integer(n)
    end

    assert healed.(pvp1) == round(healed.(pve1) * r.potion_mult)

    # vừa uống: chờ đủ potion_cd lượt
    assert {%{ok: false, msg: msg}, _} = Engine.act(low.(pvp1), "potion")
    assert msg =~ "dùng lại sau #{r.potion_cd - 1} lượt"

    later =
      Enum.reduce(1..(r.potion_cd - 1), pvp1, fn _, p ->
        elem(Engine.act(p |> put_in([:battle, :cds], []), "attack"), 1)
      end)

    assert {%{ok: true}, _} = Engine.act(low.(later), "potion")
    # đánh quái: uống liền được
    assert {%{ok: true}, _} = Engine.act(low.(pve1), "potion")

    # tối đa potion_max bình mỗi trận
    full = put_in(pvp1, [:battle, :pots_used], r.potion_max) |> put_in([:battle, :pot_at], -99)
    assert {%{ok: false, msg: msg}, _} = Engine.act(low.(full), "potion")
    assert msg =~ "chỉ uống được #{r.potion_max} bình"
  end

  test "đánh người: hồi máu từ kỹ năng × heal_mult (đánh quái giữ nguyên)" do
    a = hero("Hoi", "elf") |> Map.put(:inv, %{})
    foe = hero("Kia", "dk")
    healed = fn p -> p.battle.log |> Enum.find(&(&1.text =~ "hồi")) |> Map.fetch!(:text) end

    amount = fn t ->
      [_, n] = Regex.run(~r/hồi (\d+) máu/u, t)
      String.to_integer(n)
    end

    pvp = in_fight(a, foe, 2) |> Map.put(:hp, 10)
    mob = Map.put(Arena.opponent(foe, 2), :pvp, nil)
    {_, pve} = Engine.start_with_monster(%{a | mp: 9_999, hp: 10}, 1, mob)

    Rng.put_sequence([0.5])
    {_, pvp1} = Engine.act(pvp, "skill", "heal")
    Rng.put_sequence([0.5])
    {_, pve1} = Engine.act(pve, "skill", "heal")

    assert amount.(healed.(pvp1)) == round(amount.(healed.(pve1)) * Engine.pvp_rules().heal_mult)
  end

  test "trạng thái trận qua lại: pvp_fx / pvp_put_fx / pvp_victim giữ hiệu ứng, kháng choáng, Long Vương đã cứu" do
    p = in_fight(hero("Fx", "elf"), hero("Kia", "dw"), 2)

    fx = %{
      effects: [%{id: "guard", turns: 2, power: 0.2}],
      turn: 5,
      pstun_free: 8,
      pet_revived: true
    }

    q = Engine.pvp_put_fx(p, fx)
    assert Engine.pvp_fx(q) == %{fx | turn: p.battle.turn}
    v = Engine.pvp_victim(hero("Fx", "elf"), fx, 321)
    assert v.hp == 321 and Engine.pvp_fx(v) == fx
  end

  test "ảnh bộ của người bị đánh làm bản sao của họ né nhiều hơn (có trần)" do
    p = in_fight(hero("Ngam", "dk"), hero("Ne", "elf"), 2)
    base = p.battle.monster.dodge
    foe = Engine.pvp_victim(hero("Ne", "elf"), nil, 100)
    assert Engine.pvp_aim(p, foe).battle.monster.dodge == base

    foe = with_fx(foe, [%{id: "evade", turns: 2, power: 0.2}])
    aimed = Engine.pvp_aim(p, foe)
    assert aimed.battle.monster.dodge > base
    # hết buff: về né gốc
    assert Engine.pvp_aim(aimed, Engine.pvp_victim(hero("Ne", "elf"), nil, 100)).battle.monster.dodge ==
             base
  end
end

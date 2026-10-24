# Dựng nhân vật tối đa đúng công thức ADMIN_GUIDE §6 (+ set_mastery tối đa), mô phỏng đồ sát như server.
defmodule Max do
  alias HacLong.Admin
  alias HacLong.Game.{Commands, Engine, Gear, Mastery}

  @exc_w ~w(atk_pct crit heal_kill mp_kill atk_lvl ar_pct)
  @exc_a ~w(hp_pct dmg_red gold_pct mp_pct reflect def_rate)
  @set %{
    "dk" => {"item_0_19", "item_0_19", ~w(item_7_33 item_8_33 item_9_33 item_10_33 item_11_33)},
    "dw" => {"item_5_11", "item_5_11", ~w(item_7_30 item_8_30 item_9_30 item_10_30 item_11_30)},
    "elf" => {"item_4_24", nil, ~w(item_7_31 item_8_31 item_9_31 item_10_31 item_11_31)},
    "mg" => {"item_0_28", "item_0_28", ~w(item_8_29 item_9_29 item_10_29 item_11_29)}
  }
  @share %{
    "dk" => [{"str", 0.45}, {"agi", 0.2}, {"vit", 0.25}, {"ene", 0.1}],
    "dw" => [{"ene", 0.5}, {"agi", 0.2}, {"vit", 0.2}, {"str", 0.1}],
    "elf" => [{"agi", 0.45}, {"str", 0.2}, {"vit", 0.25}, {"ene", 0.1}],
    "mg" => [{"str", 0.4}, {"ene", 0.25}, {"agi", 0.2}, {"vit", 0.15}]
  }

  def op(p, name, params) do
    {:ok, f} = Admin.build(name, params)
    {:ok, p, _} = f.(p)
    p
  end

  def build(cls, opts \\ []) do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Max#{cls}", "cls" => cls})
    {weapon, left, set} = @set[cls]
    left = if opts[:shield], do: nil, else: left
    full = %{"opt" => 4, "luck" => true, "up" => 11}

    p =
      p
      |> op("set_rebirths", %{"n" => 10})
      |> op("set_level", %{"level" => 50})
      |> op("set_tower", %{"floor" => 100})
      |> op("reset_stats", %{})

    total = p.points
    add = Map.new(@share[cls], fn {k, r} -> {k, floor(total * r)} end)
    {first, _} = hd(@share[cls])
    add = Map.update!(add, first, &(&1 + total - Enum.sum(Map.values(add))))
    p = p |> op("add_stats", add) |> op("add_points", %{"n" => -total})
    p = op(p, "give_gear", Map.merge(full, %{"base" => weapon, "skill" => true, "exc" => @exc_w}))
    p = Enum.reduce(set, p, &op(&2, "give_gear", Map.merge(full, %{"base" => &1, "exc" => @exc_a})))

    p =
      p
      |> op("give_gear", Map.merge(full, %{"base" => "item_13_24", "exc" => @exc_a}))
      |> op("give_gear", Map.merge(full, %{"base" => "item_13_24", "exc" => @exc_a}))
      |> op("give_gear", Map.merge(full, %{"base" => "item_13_27", "exc" => @exc_w}))
      |> op("give_gear", Map.merge(full, %{"base" => "wing_#{cls}_3", "wopt" => "ignore_def"}))

    p = Enum.reduce(Gear.bag(p), p, fn g, p -> elem(Commands.run(p, %{"act" => "equip", "id" => g.uid}), 1) end)

    p =
      cond do
        left ->
          p = op(p, "give_gear", Map.merge(full, %{"base" => left, "skill" => true, "exc" => @exc_w}))
          g = Enum.find(Gear.bag(p), &(&1.base == left))
          {r, p} = Commands.run(p, %{"act" => "equip", "id" => g.uid, "hand" => "left"})
          true = r.ok
          p

        opts[:shield] && cls != "elf" ->
          p = op(p, "give_gear", Map.merge(full, %{"base" => "item_6_18", "exc" => @exc_a}))
          g = Enum.find(Gear.bag(p), &(&1.base == "item_6_18"))
          elem(Commands.run(p, %{"act" => "equip", "id" => g.uid}), 1)

        true ->
          p
      end

    p =
      p
      |> op("give_pet", %{"id" => "long_vuong", "level" => 20})
      |> op("set_mastery", %{"lv" => Mastery.max()})
      |> op("give_item", %{"id" => "potion_l", "count" => 500})
      |> op("give_item", %{"id" => "mana_l", "count" => 500})
    %{p | hp: Engine.derived(p).maxHp} |> Map.put(:mp, Engine.derived(p).maxMp)
  end
end

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

  @doc """
  DS-6: nhân vật ĐỒ GIỐNG HỆT NHAU theo mốc chuyển sinh `k` (mọi lớp cùng hồ sơ): cấp 50, k lần chuyển sinh, điểm chia
  như công thức admin, bộ đồ tốt nhất của lớp (như build/2) với +N ≈ 1.1k (tối đa +11), dòng cộng thêm k/2 (tối đa 4),
  May mắn từ k ≥ 2, Excellent ⌈k/2⌉ dòng (tối đa 6), cánh cấp 1 (k 1–3) / 2 (4–6) / 3 (7+), tháp 10 + 5k, thông thạo
  6 + k (tối đa 10), không thú cưng. Trả {nhân vật, món mặc không được (yêu cầu chỉ số)}.
  """
  def tier(cls, k) do
    prof = %{
      rebirths: k,
      up: min(11, round(k * 1.1)),
      opt: min(4, div(k, 2)),
      luck: k >= 2,
      exc: min(6, div(k + 1, 2)),
      wing: cond do
        k >= 7 -> 3
        k >= 4 -> 2
        k >= 1 -> 1
        true -> nil
      end,
      tower: min(100, 10 + 5 * k),
      mastery: min(Mastery.max(), 6 + k),
      pet: false,
      potions: true
    }

    gen(cls, prof)
  end

  def build(cls, opts \\ []) do
    {p, _} =
      gen(cls, %{
        rebirths: 10,
        up: 11,
        opt: 4,
        luck: true,
        exc: 6,
        wing: 3,
        tower: 100,
        mastery: Mastery.max(),
        pet: true,
        potions: true,
        shield: opts[:shield]
      })

    p
  end

  defp gen(cls, prof) do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Max#{cls}", "cls" => cls})
    {weapon, left, set} = @set[cls]
    left = if prof[:shield], do: nil, else: left
    full = %{"up" => prof.up, "luck" => prof.luck} |> then(&if(prof.opt > 0, do: Map.put(&1, "opt", prof.opt), else: &1))
    exc_w = Enum.take(@exc_w, prof.exc)
    exc_a = Enum.take(@exc_a, prof.exc)

    p =
      p
      |> op("set_rebirths", %{"n" => prof.rebirths})
      |> op("set_level", %{"level" => 50})
      |> op("set_tower", %{"floor" => prof.tower})
      |> op("reset_stats", %{})

    total = p.points
    add = Map.new(@share[cls], fn {k, r} -> {k, floor(total * r)} end)
    {first, _} = hd(@share[cls])
    add = Map.update!(add, first, &(&1 + total - Enum.sum(Map.values(add))))
    p = p |> op("add_stats", add) |> op("add_points", %{"n" => -total})
    p = op(p, "give_gear", Map.merge(full, %{"base" => weapon, "skill" => true, "exc" => exc_w}))
    p = Enum.reduce(set, p, &op(&2, "give_gear", Map.merge(full, %{"base" => &1, "exc" => exc_a})))

    p =
      p
      |> op("give_gear", Map.merge(full, %{"base" => "item_13_24", "exc" => exc_a}))
      |> op("give_gear", Map.merge(full, %{"base" => "item_13_24", "exc" => exc_a}))
      |> op("give_gear", Map.merge(full, %{"base" => "item_13_27", "exc" => exc_w}))

    p =
      if prof.wing,
        do:
          op(
            p,
            "give_gear",
            Map.merge(full, %{"base" => "wing_#{cls}_#{prof.wing}"})
            # cánh cấp 1 không có dòng phụ
            |> then(&if(prof.wing >= 2, do: Map.put(&1, "wopt", "ignore_def"), else: &1))
          ),
        else: p

    {p, fails} =
      Enum.reduce(Gear.bag(p), {p, []}, fn g, {p, f} ->
        {r, p2} = Commands.run(p, %{"act" => "equip", "id" => g.uid})
        if r[:ok] == false, do: {p, ["#{g.base}: #{r[:msg]}" | f]}, else: {p2, f}
      end)

    p =
      cond do
        left ->
          p = op(p, "give_gear", Map.merge(full, %{"base" => left, "skill" => true, "exc" => exc_w}))
          g = Enum.find(Gear.bag(p), &(&1.base == left))
          {r, p2} = Commands.run(p, %{"act" => "equip", "id" => g.uid, "hand" => "left"})
          if r[:ok] == false, do: p, else: p2

        prof[:shield] && cls != "elf" ->
          p = op(p, "give_gear", Map.merge(full, %{"base" => "item_6_18", "exc" => exc_a}))
          g = Enum.find(Gear.bag(p), &(&1.base == "item_6_18"))
          elem(Commands.run(p, %{"act" => "equip", "id" => g.uid}), 1)

        true ->
          p
      end

    p = if prof.pet, do: op(p, "give_pet", %{"id" => "long_vuong", "level" => 20}), else: p

    p =
      p
      |> op("set_mastery", %{"lv" => prof.mastery})
      |> op("give_item", %{"id" => "potion_l", "count" => 500})
      |> op("give_item", %{"id" => "mana_l", "count" => 500})

    {%{p | hp: Engine.derived(p).maxHp} |> Map.put(:mp, Engine.derived(p).maxMp), fails}
  end
end

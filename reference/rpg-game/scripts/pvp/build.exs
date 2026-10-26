# Dựng nhân vật tối đa đúng công thức ADMIN_GUIDE §6 (+ set_mastery tối đa), mô phỏng đồ sát như server.
defmodule Max do
  alias HacLong.Admin
  alias HacLong.Game.{Commands, Data, Engine, Gear, Mastery}

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

  @profile Path.join(__DIR__, "tier_profile.json")
  @wear ~w(weapon helm armor pants gloves boots ring pendant)

  @doc """
  DS-6: nhân vật ĐỒ NGANG NHAU theo mốc chuyển sinh `k` (mọi lớp cùng một hồ sơ, `scripts/pvp/tier_profile.json`, tạo
  bằng `scripts/pvp/profile.exs` từ hành trình chơi thật): cấp 50, k lần chuyển sinh, điểm chia như công thức admin;
  mỗi ô mặc món tốt nhất CỦA LỚP có cấp đồ ≤ cấp trong hồ sơ (vũ khí / giáp / trang sức), ép +up, opt dòng cộng thêm,
  May mắn, exc dòng Excellent, cánh bậc wing +wing_up, tháp, thông thạo, thú cưng như hồ sơ. Mốc có `"max": true`
  (mặc định mốc 10) dùng nhân vật tối đa `build/2`. Kiếm Sĩ / Phù Thủy / Đấu Sĩ
  cầm 2 vũ khí 1 tay (như `build/2`), Tiên Nữ 1 vũ khí. Trả {nhân vật, món mặc không được}.
  """
  def tier(cls, k) do
    tiers = profile()["tiers"]
    row = tiers[to_string(k)] || tiers[tiers |> Map.keys() |> Enum.max_by(&String.to_integer/1)]

    # "max": true (mốc cuối, DS-7): người chơi ở lâu và lên dần tới đồ tối đa → dùng nhân vật tối đa (build/2)
    if row["max"], do: {build(cls), []}, else: tier_gen(cls, k, row)
  end

  def profile, do: @profile |> File.read!() |> Jason.decode!()

  # các món của lớp ở ô `slot` có cấp đồ ≤ `lv`, tốt nhất trước (bỏ đồ cũ không có bậc)
  defp picks(cls, slot, lv, hands) do
    Data.items()
    |> Enum.filter(fn {_, i} ->
      i[:slot] == slot and i[:tier] != nil and cls in (i[:classes] || []) and
        (i[:level] || 0) <= max(lv, 1) and
        (hands == nil or i[:hands] == hands)
    end)
    |> Enum.sort_by(fn {_, i} -> {-(i[:atkMax] || i[:def] || 0), -(i[:level] || 0)} end)
    |> Enum.map(&elem(&1, 0))
  end

  # thử mặc lần lượt các món, giữ món đầu tiên mặc được
  defp wear(p, ids, params, hand \\ nil) do
    Enum.reduce_while(ids, {p, :none}, fn id, {p, _} ->
      p2 = op(p, "give_gear", Map.put(params, "base", id))
      g = Enum.find(Gear.bag(p2), &(&1.base == id))

      cmd =
        %{"act" => "equip", "id" => g.uid}
        |> then(&if(hand, do: Map.put(&1, "hand", hand), else: &1))

      {r, p3} = Commands.run(p2, cmd)
      if r[:ok] == false, do: {:cont, {p, :none}}, else: {:halt, {p3, id}}
    end)
  end

  defp tier_gen(cls, k, r) do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Max#{cls}", "cls" => cls})

    p =
      p
      |> op("set_rebirths", %{"n" => k})
      |> op("set_level", %{"level" => 50})
      |> op("set_tower", %{"floor" => r["tower"]})
      |> op("reset_stats", %{})

    total = p.points
    add = Map.new(@share[cls], fn {s, x} -> {s, floor(total * x)} end)
    {first, _} = hd(@share[cls])
    add = Map.update!(add, first, &(&1 + total - Enum.sum(Map.values(add))))
    p = p |> op("add_stats", add) |> op("add_points", %{"n" => -total})

    base =
      %{"up" => r["up"], "luck" => r["luck"]}
      |> then(&if(r["opt"] > 0, do: Map.put(&1, "opt", r["opt"]), else: &1))

    exc_w = Enum.take(@exc_w, r["exc"])
    exc_a = Enum.take(@exc_a, r["exc"])
    dual = cls in Data.rules().dual_wield.classes

    lv = %{
      "weapon" => r["weapon_level"],
      "ring" => r["jewel_level"],
      "pendant" => r["jewel_level"]
    }

    {p, fails} =
      Enum.reduce(@wear, {p, []}, fn slot, {p, f} ->
        l = lv[slot] || r["armor_level"]
        exc = if slot in ~w(weapon pendant), do: exc_w, else: exc_a
        params = Map.merge(base, %{"exc" => exc, "skill" => slot == "weapon" and r["skill"]})
        ids = picks(cls, slot, l, if(slot == "weapon" and dual, do: 1))
        # nhẫn: 2 ô
        n = if slot == "ring", do: 2, else: 1

        Enum.reduce(1..n, {p, f}, fn _, {p, f} ->
          case wear(p, ids, params) do
            {p, :none} ->
              {p, if(ids == [], do: f, else: ["#{slot}: không mặc được" | f])}

            {p, id} ->
              {if(slot == "weapon" and dual, do: elem(wear(p, [id], params, "left"), 0), else: p),
               f}
          end
        end)
      end)

    p =
      if r["wing"] > 0 do
        wp = Map.merge(base, %{"up" => r["wing_up"], "base" => "wing_#{cls}_#{r["wing"]}"})
        wp = if r["wing"] >= 2, do: Map.put(wp, "wopt", "ignore_def"), else: wp
        p = op(p, "give_gear", wp)
        g = Enum.find(Gear.bag(p), &(&1.base == wp["base"]))
        elem(Commands.run(p, %{"act" => "equip", "id" => g.uid}), 1)
      else
        p
      end

    p = if r["pet"], do: op(p, "give_pet", %{"id" => r["pet"], "level" => 20}), else: p

    p =
      p
      |> op("set_mastery", %{"lv" => min(Mastery.max(), r["mastery"])})
      |> op("give_item", %{"id" => "potion_l", "count" => 500})
      |> op("give_item", %{"id" => "mana_l", "count" => 500})

    {%{p | hp: Engine.derived(p).maxHp} |> Map.put(:mp, Engine.derived(p).maxMp), fails}
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

    full =
      %{"up" => prof.up, "luck" => prof.luck}
      |> then(&if(prof.opt > 0, do: Map.put(&1, "opt", prof.opt), else: &1))

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

    p =
      Enum.reduce(set, p, &op(&2, "give_gear", Map.merge(full, %{"base" => &1, "exc" => exc_a})))

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
          p =
            op(
              p,
              "give_gear",
              Map.merge(full, %{"base" => left, "skill" => true, "exc" => exc_w})
            )

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

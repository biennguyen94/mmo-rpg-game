defmodule Mu.Game.Simulator do
  @moduledoc """
  Mô phỏng một DK đánh Spider liên tục bằng chính `Mu.Game.Engine` (không qua MapServer), để
  kiểm tra cân bằng (`KB_TECH_STACK §8`). Khung báo cáo học từ `HacLong.Game.Simulator`;
  vòng mô phỏng viết mới theo thời gian thực (cooldown, tỉ lệ trúng).

  Giả định của mô phỏng (chỉ để đo, không phải luật game):
  - Đánh từng con một; giữa hai con đi bộ `walk_ms`. Spider đánh mỗi `baseCooldownMs` (G5).
  - Không hồi máu tự nhiên (G9). Dùng HP potion (`effect.hp`) khi HP < `potion_below` × max,
    cách nhau `potionCooldownMs`; đếm số potion cần (không giới hạn túi).
  - Chết: tính 1 lần chết, hồi đầy, cộng `playerRespawnSeconds` + `walk_ms`.
  - Cộng điểm theo `strategy`: `"str"`, `"agi"`, `"vit"`, `"ene"` (dồn hết) hoặc `"balanced"`.
  - `class`: DK/DW/ELF (mặc định `newCharacter.defaultClass`); đánh xa thì Spider tới chậm hơn.
  - `equipment`: danh sách template (vd. bộ đồ t0 từ `data/items/phase1.json`) để so Q14.
  """

  alias Mu.Game.{Config, Data, Drops, Engine, Rng}

  @milestones [2, 5, 10, 20, 30]

  @defaults %{
    strategy: "balanced",
    walk_ms: 2000,
    potion_below: 0.4,
    equipment: [],
    class: nil,
    # P2-M4: "spider" (mặc định) hoặc "auto" = quái cấp cao nhất ≤ cấp nhân vật (quái mọi map)
    monster: "spider",
    # P2-M4: true = đồ t0 (full) dưới cấp 10, t1 từ cấp 10 (bỏ qua `equipment`)
    gear_progress: false,
    # P2-M4: true = DW dùng skill đánh mạnh nhất đã học còn đủ mana (hồi MP theo combat.mpRegen)
    use_skills: false,
    max_kills: 5000
  }

  @doc "Chạy `runs` lần (seed 1..runs), trả kết quả trung bình."
  def run(runs, opts \\ %{}) do
    opts = Map.merge(@defaults, opts)
    results = for seed <- 1..runs, do: once(seed, opts)

    avg = fn f -> Enum.sum(Enum.map(results, f)) / runs end

    %{
      runs: runs,
      opts:
        Map.delete(opts, :equipment)
        |> Map.put(:equipment, Enum.map(opts.equipment, & &1["templateId"])),
      milestones:
        for lv <- @milestones, into: %{} do
          reached = Enum.filter(results, &Map.has_key?(&1.at, lv))
          n = max(length(reached), 1)

          {lv,
           %{
             reached: length(reached),
             kills: Enum.sum(Enum.map(reached, & &1.at[lv].kills)) / n,
             minutes: Enum.sum(Enum.map(reached, & &1.at[lv].ms)) / n / 60_000,
             potions: Enum.sum(Enum.map(reached, & &1.at[lv].potions)) / n,
             deaths: Enum.sum(Enum.map(reached, & &1.at[lv].deaths)) / n
           }}
        end,
      zen: avg.(& &1.zen),
      items: avg.(& &1.items),
      # P5-M1: jewel rơi (Bless / Soul / Life) và số jewel mỗi giờ săn
      jewels: avg.(& &1.jewels),
      jewels_per_hour: avg.(&(&1.jewels / max(&1.t, 1) * 3_600_000)),
      damage_taken_per_kill: avg.(&(&1.damage_taken / max(&1.kills, 1))),
      hit_rate: avg.(&(&1.hits / max(&1.swings, 1)))
    }
  end

  @doc "Một lần mô phỏng với `seed`."
  def once(seed, opts) do
    opts = Map.merge(@defaults, opts)
    c = start_character(opts.class)
    potion = potion_heal()

    st = %{
      strategy: opts.strategy,
      rng: Rng.new(seed),
      c: c,
      hp: Engine.derived(c, opts.equipment).hp_max,
      mp: Engine.derived(c, opts.equipment).mp_max,
      t: 0,
      kills: 0,
      potions: 0,
      deaths: 0,
      zen: 0,
      items: 0,
      jewels: 0,
      damage_taken: 0,
      hits: 0,
      swings: 0,
      at: %{}
    }

    loop(st, opts, potion)
  end

  defp loop(st, opts, potion) do
    if st.c.level >= Engine.max_level() or st.kills >= opts.max_kills,
      do: st,
      else: st |> fight(opts, potion) |> loop(opts, potion)
  end

  # một trận với một quái, theo thời gian (ms)
  defp fight(st, opts, potion) do
    spider = pick_monster(st.c.level, opts.monster)
    m = Engine.monster_stats(spider)
    combat = Config.get(["combat"])
    opts = if opts.gear_progress, do: %{opts | equipment: progress_gear(st.c)}, else: opts
    d = Engine.derived(st.c, opts.equipment)
    # đi bộ giữa hai con: MP vẫn hồi (P2-M3)
    mp = min(d.mp_max, st.mp + Engine.mp_regen(st.c.energy, opts.walk_ms))
    st = %{st | t: st.t + opts.walk_ms, mp: mp}

    # đánh xa (P2-5): Spider phải đi thêm (tầm người chơi − tầm Spider) ô mới đánh được
    approach_ms = max(d.attack_range - spider["attackRange"], 0) * 1000 / spider["moveSpeed"]
    m_first = st.t + round(approach_ms) + combat["baseCooldownMs"]
    duel(st, opts, potion, d, m, spider, spider["hp"], st.t, m_first, 0)
  end

  defp duel(st, opts, potion, d, m, spider, mhp, p_next, m_next, potion_ready) do
    combat = Config.get(["combat"])

    cond do
      mhp <= 0 ->
        win(st, spider)

      st.hp <= 0 ->
        respawn = Config.get(["combat", "playerRespawnSeconds"]) * 1000
        %{st | deaths: st.deaths + 1, hp: d.hp_max, t: st.t + respawn}

      # dùng potion khi máu thấp
      st.hp < opts.potion_below * d.hp_max and st.t >= potion_ready ->
        st = %{st | hp: min(d.hp_max, st.hp + potion), potions: st.potions + 1}

        duel(
          st,
          opts,
          potion,
          d,
          m,
          spider,
          mhp,
          p_next,
          m_next,
          st.t + combat["potionCooldownMs"]
        )

      p_next <= m_next ->
        {mult, cd, cost, ds} = attack_choice(st, d, opts)
        mp = min(d.mp_max, st.mp - cost + Engine.mp_regen(st.c.energy, cd))
        st = %{st | t: p_next, mp: mp}
        {res, rng} = Engine.roll_attack(st.rng, ds, m, mult)
        st = %{st | rng: rng, swings: st.swings + 1, hits: st.hits + if(res.hit, do: 1, else: 0)}

        duel(
          st,
          opts,
          potion,
          d,
          m,
          spider,
          mhp - res.dmg,
          p_next + cd,
          m_next,
          potion_ready
        )

      true ->
        st = %{st | t: m_next}
        {res, rng} = Engine.roll_attack(st.rng, m, d)
        st = %{st | rng: rng, hp: st.hp - res.dmg, damage_taken: st.damage_taken + res.dmg}

        duel(
          st,
          opts,
          potion,
          d,
          m,
          spider,
          mhp,
          p_next,
          m_next + combat["baseCooldownMs"],
          potion_ready
        )
    end
  end

  defp win(st, spider) do
    {drop, rng} = Drops.roll(st.rng, spider["id"])
    exp = Engine.exp_gain(spider["experience"], st.c.level, spider["level"])
    {c, levels} = Engine.add_exp(st.c, exp)
    c = allocate(c, st.strategy)

    st = %{
      st
      | rng: rng,
        c: c,
        kills: st.kills + 1,
        zen: st.zen + drop.zen,
        items: st.items + length(drop.items),
        jewels: st.jewels + Enum.count(drop.items, &(Data.item(&1)["type"] == "JEWEL"))
    }

    # lên cấp hồi đầy (G10)
    st =
      if levels > 0,
        do: %{st | hp: Engine.derived(c).hp_max, mp: Engine.derived(c).mp_max},
        else: st

    Enum.reduce(@milestones, st, fn lv, st ->
      if c.level >= lv and not Map.has_key?(st.at, lv),
        do:
          put_in(st.at[lv], %{kills: st.kills, ms: st.t, potions: st.potions, deaths: st.deaths}),
        else: st
    end)
  end

  # quái để đánh: Spider, hoặc (auto) quái cấp cao nhất ≤ cấp nhân vật
  defp pick_monster(_level, "spider"), do: Data.monster("spider")

  defp pick_monster(level, "auto") do
    Data.monsters()
    |> Map.values()
    |> Enum.filter(&(&1["level"] <= max(level, 2)))
    |> Enum.max_by(& &1["level"])
  end

  defp pick_monster(_level, id), do: Data.monster(id)

  # {hệ số, cooldown ms, mana, chỉ số}: đánh thường, hoặc skill đánh một mục tiêu mạnh nhất (hệ
  # số × đòn tối đa — MG: skill phép dùng chỉ số phép, P3-M5) đã học, đủ mana
  defp attack_choice(st, d, %{use_skills: true}) do
    Engine.skills(st.c)
    |> Enum.map(&Data.skill/1)
    |> Enum.filter(
      &(&1["classes"] != nil and &1["targetType"] == "SINGLE" and st.mp >= &1["manaCost"])
    )
    |> Enum.max_by(&(&1["damageMultiplier"] * Engine.for_skill(d, &1).attack_max), fn -> nil end)
    |> case do
      nil ->
        {1.0, d.cooldown_ms, 0, d}

      sk ->
        ds = Engine.for_skill(d, sk)
        {sk["damageMultiplier"], Engine.skill_cooldown_ms(sk, ds), sk["manaCost"], ds}
    end
  end

  defp attack_choice(_st, d, _opts), do: {1.0, d.cooldown_ms, 0, d}

  defp progress_gear(c) do
    if c.level >= 10, do: gear(c.class, "t1"), else: gear(c.class, "full")
  end

  defp allocate(%{free_stat_points: 0} = c, _strategy), do: c

  defp allocate(c, strategy) do
    stat =
      case strategy do
        "str" -> "strength"
        "agi" -> "agility"
        "vit" -> "vitality"
        "ene" -> "energy"
        _ -> Enum.at(~w(strength agility vitality), rem(c.free_stat_points, 3))
      end

    {:ok, c} = Engine.alloc(c, stat, 1)
    allocate(c, strategy)
  end

  defp start_character(class_id) do
    cls = Data.class(class_id || Config.get(["newCharacter", "defaultClass"]))

    %{
      class: cls["id"],
      level: 1,
      experience: 0,
      strength: cls["strength"],
      agility: cls["agility"],
      vitality: cls["vitality"],
      energy: cls["energy"],
      free_stat_points: 0
    }
  end

  @doc "Template item (`priv/game_data/items.json`)."
  def item_templates, do: Map.values(Data.items())

  @doc """
  Trang bị cho mô phỏng: `"none"`, `"starter"` (`newCharacter.startingEquipment`) hoặc `"full"`
  (mỗi ô một template t0 class dùng được; vũ khí hai tay thì bỏ khiên).
  """
  def gear(class_id, kind) do
    class_id = class_id || Config.get(["newCharacter", "defaultClass"])

    case kind do
      "starter" ->
        Enum.map(Config.get(["newCharacter", "startingEquipment", class_id]) || [], &Data.item/1)

      "t1" ->
        t1 =
          item_templates()
          |> Enum.filter(&(&1["slot"] != nil and class_id in (&1["classes"] || [])))
          |> Enum.filter(&String.ends_with?(&1["templateId"], "_t1"))
          |> Map.new(&{&1["slot"], &1})

        picked = Map.merge(Map.new(gear(class_id, "full"), &{&1["slot"], &1}), t1)

        picked =
          if Mu.Game.Inventory.two_handed?(picked["WEAPON"] || %{}),
            do: Map.delete(picked, "SHIELD"),
            else: picked

        Map.values(picked)

      "full" ->
        starter = gear(class_id, "starter")

        picked =
          item_templates()
          |> Enum.filter(&(&1["slot"] != nil and class_id in (&1["classes"] || [])))
          |> Enum.sort_by(& &1["templateId"])
          |> Enum.reduce(%{}, fn t, acc -> Map.put_new(acc, t["slot"], t) end)

        picked =
          Enum.reduce(starter, picked, fn t, acc -> Map.put(acc, t["slot"], t) end)

        picked =
          if Mu.Game.Inventory.two_handed?(picked["WEAPON"] || %{}),
            do: Map.delete(picked, "SHIELD"),
            else: picked

        Map.values(picked)

      _ ->
        []
    end
  end

  defp potion_heal do
    Enum.find(item_templates(), &(&1["templateId"] == "hp_potion_small"))["effect"]["hp"]
  end
end

defmodule Mu.Game.Engine do
  @moduledoc """
  Luật chiến đấu và phát triển nhân vật, **hàm thuần** (RNG truyền vào/trả ra: `Mu.Game.Rng`).
  Viết lại so với `HacLong.Game.Engine` (theo lượt), giữ phong cách hàm thuần + test seed.

  - Chỉ số suy ra `derived/2`: `KB_GAME_DESIGN §4.1` (hệ số trong `classes.json` → `derived`),
    `hpMax` cộng `hpBonus` trang bị (G6). Mỗi chỉ số `floor` một lần.
  - Sát thương `damage/2`: pipeline §4, `floor` một lần ở bước cuối.
  - Trúng `hit_chance/2`: §5. Cooldown `cooldown_ms/1`: §6.
  - EXP/level: §3 + `experience` trong config. Cộng điểm `alloc/3`: §1.

  Nhân vật là map/struct có `class, level, experience, strength, agility, vitality, energy,
  free_stat_points`. Trang bị là danh sách template item (map khóa chuỗi, `KB_ITEM_REFERENCE`).
  Mọi công thức ở đây là IMPLEMENTATION, không phải công thức MU (`KB_00_RULES` S7).
  """

  alias Mu.Game.{Config, Data, Rng, Stats}

  @stats ~w(strength agility vitality energy)

  # ---------- Chỉ số ----------

  @doc "Chỉ số suy ra của nhân vật với trang bị `equipment`."
  def derived(c, equipment \\ []) do
    formulas = Data.class(c.class)["derived"]
    value = fn key -> eval(formulas[key], c, equipment) end
    attack_speed = value.("attackSpeed")
    attack_max = value.("attackMax")

    # MG (P3-M5): attackPowerMagic / attackSpeedMagic cho skill phép (§4.1); class khác = như thường
    speed_magic =
      if formulas["attackSpeedMagic"], do: value.("attackSpeedMagic"), else: attack_speed

    %{
      attack_min: value.("attackMin"),
      attack_max: attack_max,
      attack_max_magic:
        if(formulas["attackMaxMagic"], do: value.("attackMaxMagic"), else: attack_max),
      attack_speed_magic: speed_magic,
      cooldown_ms_magic: cooldown_ms(speed_magic),
      defense: value.("defense"),
      attack_rate: value.("attackRate"),
      defense_rate: value.("defenseRate"),
      attack_speed: attack_speed,
      cooldown_ms: cooldown_ms(attack_speed),
      attack_range: basic_attack_range(equipment),
      hp_max: Stats.hp_max(c.class, c.level, c.vitality) + item_sum(equipment, "hpBonus"),
      mp_max: Stats.mp_max(c.class, c.level, c.energy),
      # cánh (P6-4): % sát thương gây ra / % sát thương nhận bớt
      damage_increase: item_sum(equipment, "damageIncrease"),
      absorb: item_sum(equipment, "absorb"),
      # cho heal/buff (công thức theo energy của người dùng, P2-M3) và hồi MP
      energy: c.energy
    }
  end

  @doc """
  Template đồ ở cấp cường hóa `level` (+N, P5-3 (1)) và cấp option Jewel of Life `option`
  (P5-4): cộng `items.levelBonus[type]` × `level` — `attack` vào `attackMin` / `attackMax`,
  khóa khác (`defense`, cánh P6-4: `damageIncrease`, `absorb`) vào khóa cùng tên — và
  `upgrade.life.perOption` × `option` vào chỉ số đòn (vũ khí) / thủ (đồ khác). Type không có
  trong bảng (nhẫn, jewel, potion) giữ nguyên.
  """
  def leveled(template, level, option \\ 0)

  def leveled(template, level, option) when level > 0 or option > 0 do
    case Config.get(["items", "levelBonus"])[template["type"]] do
      nil ->
        template

      bonus ->
        per_option = Config.get(["upgrade", "life", "perOption"]) * option
        # P7-3: từ cấp `items.highLevel.fromLevel` (+10) mỗi cấp tính `multiplier` lần
        level = bonus_levels(level)
        add = fn t, key, n -> Map.update(t, key, n, &(&1 + n)) end
        atk = (bonus["attack"] || 0) * level
        def = (bonus["defense"] || 0) * level

        # option cộng vào đúng loại chỉ số của đồ: vũ khí → đòn, giáp / khiên → thủ
        {atk, def} =
          if bonus["attack"], do: {atk + per_option, def}, else: {atk, def + per_option}

        # khóa khác của bảng (cánh: damageIncrease, absorb) cộng thẳng theo cấp
        extra =
          for {k, n} <- bonus, k not in ~w(attack defense), n * level > 0, do: {k, n * level}

        template
        |> then(
          &if(atk > 0, do: &1 |> add.("attackMin", atk) |> add.("attackMax", atk), else: &1)
        )
        |> then(&if(def > 0, do: add.(&1, "defense", def), else: &1))
        |> then(&Enum.reduce(extra, &1, fn {k, n}, t -> add.(t, k, n) end))
    end
  end

  def leveled(template, _level, _option), do: template

  @doc "Số cấp tính chỉ số của đồ +`level` (cấp ≥ `items.highLevel.fromLevel` nhân `multiplier`)."
  def bonus_levels(level) do
    case Config.get(["items"])["highLevel"] do
      %{"fromLevel" => from, "multiplier" => m} when level >= from ->
        level + (level - from + 1) * (m - 1)

      _ ->
        level
    end
  end

  @doc "Tầm đánh thường (ô) theo `weaponType` của vũ khí đang cầm (P2-5, `combat.basicAttackRange`)."
  def basic_attack_range(equipment) do
    ranges = Config.get(["combat", "basicAttackRange"])

    case Enum.find(equipment, &(&1["slot"] == "WEAPON")) do
      nil -> ranges["default"]
      w -> Map.get(ranges, w["weaponType"], ranges["default"])
    end
  end

  defp eval(%{"terms" => terms} = f, c, equipment) do
    base =
      Enum.reduce(terms, 0, fn
        %{"stat" => s, "mul" => m}, acc -> acc + stat(c, s) * m
        %{"stat" => s, "div" => d}, acc -> acc + stat(c, s) / d
      end)

    floor(base + if(f["item"], do: item_sum(equipment, f["item"]), else: 0))
  end

  defp stat(c, "level"), do: c.level
  defp stat(c, s) when s in @stats, do: Map.fetch!(c, String.to_existing_atom(s))

  defp item_sum(equipment, key), do: equipment |> Enum.map(&(&1[key] || 0)) |> Enum.sum()

  @doc "`max(minCooldownMs, baseCooldownMs / (1 + attackSpeed / 100))` (§6), làm tròn xuống."
  def cooldown_ms(attack_speed) do
    combat = Config.get(["combat"])
    max(combat["minCooldownMs"], floor(combat["baseCooldownMs"] / (1 + attack_speed / 100)))
  end

  @doc """
  Chỉ số dùng cho `skill`: skill `magic: true` lấy `attack_max_magic` / `attack_speed_magic` /
  `cooldown_ms_magic` (MG — §4.1 "Nếu class là MG và skill là magic"; class khác các số này bằng
  số thường). `attack_min` giữ nguyên (KB không cho công thức phép riêng).
  """
  def for_skill(stats, %{"magic" => true}) do
    # map chỉ số dựng tay (test, simulator) có thể thiếu khóa phép: giữ số thường
    for {k, magic} <- [
          attack_max: :attack_max_magic,
          attack_speed: :attack_speed_magic,
          cooldown_ms: :cooldown_ms_magic
        ],
        Map.has_key?(stats, magic),
        reduce: stats,
        do: (acc -> Map.put(acc, k, stats[magic]))
  end

  def for_skill(stats, _skill), do: stats

  @doc "Cooldown của skill: `cooldownMs` của skill, `null` = theo attack speed (G2)."
  def skill_cooldown_ms(%{"cooldownMs" => nil}, derived), do: derived.cooldown_ms
  def skill_cooldown_ms(%{"cooldownMs" => ms}, _derived), do: ms

  # ---------- Đánh ----------

  @doc "`clamp(attackRate / (attackRate + defenseRate), minHitChance, maxHitChance)` (§5)."
  def hit_chance(attack_rate, defense_rate) do
    combat = Config.get(["combat"])
    total = attack_rate + defense_rate
    p = if total <= 0, do: combat["maxHitChance"], else: attack_rate / total
    p |> max(combat["minHitChance"]) |> min(combat["maxHitChance"])
  end

  @doc """
  Pipeline sát thương §4 (giống `calculateDamage` của KB). `ctx`: `raw_attack`,
  `skill_multiplier`, `target_defense` và tùy chọn `skill_bonus`, `damage_bonus`,
  `critical?`, `critical_multiplier`, `buff_multiplier`, cánh (P6-4, %): `damage_increase` của
  bên đánh (nhân cùng bước buff) và `absorb` của bên nhận (nhân sau khi trừ thủ, trước sàn cứng).
  """
  def damage(ctx) do
    combat = Config.get(["combat"])

    d =
      ctx.raw_attack * ctx.skill_multiplier + Map.get(ctx, :skill_bonus, 0) +
        Map.get(ctx, :damage_bonus, 0)

    d = if Map.get(ctx, :critical?, false), do: d * ctx.critical_multiplier, else: d
    d = d * Map.get(ctx, :buff_multiplier, 1) * (1 + Map.get(ctx, :damage_increase, 0) / 100)
    after_def = d - ctx.target_defense
    soft_floor = d * combat["minDamageRatio"]
    absorbed = max(after_def, soft_floor) * (1 - min(Map.get(ctx, :absorb, 0), 100) / 100)
    max(combat["hardFloor"], floor(absorbed))
  end

  @doc """
  Một đòn đánh. `attacker`: `attack_min, attack_max, attack_rate`; `defender`:
  `defense, defense_rate`. Trả `{%{hit: bool, dmg: int, crit: bool}, rng}` (trượt: dmg 0).
  Thứ tự gọi RNG cố định: trúng → raw attack → chí mạng.
  """
  def roll_attack(rng, attacker, defender, skill_multiplier \\ 1.0) do
    combat = Config.get(["combat"])
    {hit?, rng} = Rng.chance(rng, hit_chance(attacker.attack_rate, defender.defense_rate))

    if hit? do
      {raw, rng} =
        Rng.int(rng, attacker.attack_min, max(attacker.attack_min, attacker.attack_max))

      {crit?, rng} = Rng.chance(rng, combat["critChance"])

      dmg =
        damage(%{
          raw_attack: raw,
          skill_multiplier: skill_multiplier,
          # buff Greater Damage (§4 bước 3)
          damage_bonus: Map.get(attacker, :damage_bonus, 0),
          damage_increase: Map.get(attacker, :damage_increase, 0),
          absorb: Map.get(defender, :absorb, 0),
          target_defense: defender.defense,
          critical?: crit?,
          critical_multiplier: combat["criticalMultiplier"]
        })

      {%{hit: true, dmg: dmg, crit: crit?}, rng}
    else
      {%{hit: false, dmg: 0, crit: false}, rng}
    end
  end

  # ---------- Heal, buff, hồi MP (P2-M3, IMPLEMENTATION) ----------

  @doc "Giá trị heal/buff của skill: `floor(base + energy / energyDiv)`."
  def effect_value(%{"base" => base, "energyDiv" => div}, energy), do: floor(base + energy / div)

  @doc """
  Thêm buff `id` (`stat`, `value`, hết hạn `until` ms): cùng buff thì làm mới thời gian và giữ
  giá trị lớn hơn; buff khác cộng dồn. `buffs`: `%{id => %{stat, value, until}}`.
  """
  def add_buff(buffs, id, stat, value, until) do
    Map.update(buffs, id, %{stat: stat, value: value, until: until}, fn b ->
      %{b | value: max(b.value, value), until: until}
    end)
  end

  @doc "Bỏ buff đã hết hạn lúc `now`: `{còn_lại, có_buff_hết_hạn?}`."
  def expire_buffs(buffs, now) do
    kept = for {id, b} <- buffs, b.until > now, into: %{}, do: {id, b}
    {kept, map_size(kept) != map_size(buffs)}
  end

  @doc "Chỉ số chiến đấu sau buff: `defense` cộng thêm, `damage_bonus` (sát thương phẳng)."
  def with_buffs(stats, buffs) do
    sum = fn stat ->
      buffs
      |> Map.values()
      |> Enum.filter(&(&1.stat == stat))
      |> Enum.map(& &1.value)
      |> Enum.sum()
    end

    stats
    |> Map.update(:defense, 0, &(&1 + sum.("defense")))
    |> Map.put(:damage_bonus, sum.("damageBonus"))
  end

  @doc "MP hồi trong `ms` mili-giây (số thực, cộng dồn phần lẻ ở nơi gọi): `energy / energyDiv` mỗi giây."
  def mp_regen(energy, ms),
    do: energy / Config.get(["combat", "mpRegen", "energyDiv"]) * ms / 1000

  @doc "Chỉ số đánh/thủ của quái theo template (`monsters.json`)."
  def monster_stats(m) do
    %{
      attack_min: m["damageMin"],
      attack_max: m["damageMax"],
      attack_rate: m["attackRate"],
      defense: m["defense"],
      defense_rate: m["defenseRate"]
    }
  end

  # ---------- Skill ----------

  @doc """
  Skill nhân vật đã học: skill có `classes` chứa class của mình (`null` = mọi class, vd
  `basic_attack`) và đủ `requiredLevel` (§7). MG học skill DK + DW theo `classes` (P3-4).
  """
  def skills(c) do
    for {id, s} <- Data.skills(),
        class_ok?(s, c),
        c.level >= s["requiredLevel"],
        do: id
  end

  defp class_ok?(s, c), do: s["classes"] == nil or c.class in s["classes"]

  @doc "`:ok` hoặc `{:error, \"INVALID_TARGET\" | \"REQUIREMENT_NOT_MET\"}`."
  def can_use_skill(c, skill_id) do
    case Data.skill(skill_id) do
      nil ->
        {:error, "INVALID_TARGET"}

      s ->
        if skill_id in skills(c) and class_ok?(s, c),
          do: :ok,
          else: {:error, "REQUIREMENT_NOT_MET"}
    end
  end

  # ---------- EXP & level ----------

  def max_level, do: Config.get(["game", "maxLevel"])

  @doc "EXP để lên từ `level` sang `level + 1`: `round(100 × level^1.5)` (KB_CONFIG, G19)."
  def exp_required(level) do
    %{"formula" => "100 * level ^ 1.5"} = Config.get(["experience"])
    round(100 * :math.pow(level, 1.5))
  end

  @doc """
  EXP nhận được khi hạ quái: `experience × multiplier × levelDiffModifier` (§3), làm tròn
  xuống, tối thiểu 1. Người chơi cao hơn quái quá `levelDiffPenaltyStart` cấp thì giảm
  `levelDiffPenaltyPerLevel` mỗi cấp, không dưới `minExpRatio` (G23).
  """
  def exp_gain(monster_exp, player_level, monster_level),
    do: party_exp_gain(monster_exp, 1, player_level, monster_level)

  @doc """
  EXP mỗi người khi `n` thành viên nhóm cùng nhận (§3 "Party EXP", P3-5):
  `experience / n × (1 + partyBonusPerMember × (n − 1)) × multiplier × levelDiffModifier` của
  **từng người**, làm tròn xuống, tối thiểu 1. `n = 1` = `exp_gain/3`.
  """
  def party_exp_gain(monster_exp, n, player_level, monster_level) when n >= 1 do
    e = Config.get(["experience"])
    over = player_level - monster_level - e["levelDiffPenaltyStart"]

    ratio =
      if over > 0, do: max(e["minExpRatio"], 1 - over * e["levelDiffPenaltyPerLevel"]), else: 1.0

    share = monster_exp / n * (1 + e["partyBonusPerMember"] * (n - 1))
    # + 1e-9: tránh 11,999… do số thực (vd 30 / 3 × 1,2)
    max(1, floor(share * e["multiplier"] * ratio + 1.0e-9))
  end

  @doc """
  Cộng EXP, lên cấp liên tiếp nếu đủ (mỗi cấp `+statPerLevel` điểm tự do). Ở `maxLevel`
  EXP dừng ở 0 (G19). Trả `{nhân_vật, số_cấp_đã_lên}`; hồi đầy HP/MP do nơi gọi (G10).
  """
  def add_exp(c, amount) when amount >= 0,
    do: level_up(%{c | experience: c.experience + amount}, 0)

  defp level_up(%{level: level} = c, n) do
    cond do
      level >= max_level() ->
        {%{c | experience: 0}, n}

      c.experience >= exp_required(level) ->
        per = Data.class(c.class)["statPerLevel"]

        c = %{
          c
          | level: level + 1,
            experience: c.experience - exp_required(level),
            free_stat_points: c.free_stat_points + per
        }

        level_up(c, n + 1)

      true ->
        {c, n}
    end
  end

  # ---------- Cộng điểm ----------

  @doc """
  Cộng `points` điểm tự do vào `stat` (`"strength"`...). Kiểm tra server-side (§1):
  không vượt điểm tự do, không giảm. `{:ok, c}` hoặc `{:error, code}`
  (`FORBIDDEN`: stat/điểm sai kiểu; `REQUIREMENT_NOT_MET`: không đủ điểm).
  """
  def alloc(c, stat, points) when stat in @stats and is_integer(points) and points > 0 do
    if points <= c.free_stat_points do
      key = String.to_existing_atom(stat)

      {:ok,
       c
       |> Map.update!(key, &(&1 + points))
       |> Map.put(:free_stat_points, c.free_stat_points - points)}
    else
      {:error, "REQUIREMENT_NOT_MET"}
    end
  end

  def alloc(_c, _stat, _points), do: {:error, "FORBIDDEN"}

  @doc "Điểm đã cộng = tổng stat − stat khởi điểm của class."
  def allocated_points(c) do
    base = Data.class(c.class)
    Enum.sum(for s <- @stats, do: Map.fetch!(c, String.to_existing_atom(s)) - base[s])
  end
end

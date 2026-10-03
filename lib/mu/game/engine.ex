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

    %{
      attack_min: value.("attackMin"),
      attack_max: value.("attackMax"),
      defense: value.("defense"),
      attack_rate: value.("attackRate"),
      defense_rate: value.("defenseRate"),
      attack_speed: attack_speed,
      cooldown_ms: cooldown_ms(attack_speed),
      attack_range: basic_attack_range(equipment),
      hp_max: Stats.hp_max(c.class, c.level, c.vitality) + item_sum(equipment, "hpBonus"),
      mp_max: Stats.mp_max(c.class, c.level, c.energy)
    }
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
  `critical?`, `critical_multiplier`, `buff_multiplier`.
  """
  def damage(ctx) do
    combat = Config.get(["combat"])

    d =
      ctx.raw_attack * ctx.skill_multiplier + Map.get(ctx, :skill_bonus, 0) +
        Map.get(ctx, :damage_bonus, 0)

    d = if Map.get(ctx, :critical?, false), do: d * ctx.critical_multiplier, else: d
    d = d * Map.get(ctx, :buff_multiplier, 1)
    after_def = d - ctx.target_defense
    soft_floor = d * combat["minDamageRatio"]
    max(combat["hardFloor"], floor(max(after_def, soft_floor)))
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
          target_defense: defender.defense,
          critical?: crit?,
          critical_multiplier: combat["criticalMultiplier"]
        })

      {%{hit: true, dmg: dmg, crit: crit?}, rng}
    else
      {%{hit: false, dmg: 0, crit: false}, rng}
    end
  end

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

  @doc "Skill nhân vật đã học: `basic_attack` + skill của class đủ `requiredLevel` (§7)."
  def skills(c) do
    for {id, s} <- Data.skills(),
        s["class"] in [nil, c.class],
        c.level >= s["requiredLevel"],
        do: id
  end

  @doc "`:ok` hoặc `{:error, \"INVALID_TARGET\" | \"REQUIREMENT_NOT_MET\"}`."
  def can_use_skill(c, skill_id) do
    case Data.skill(skill_id) do
      nil ->
        {:error, "INVALID_TARGET"}

      s ->
        if skill_id in skills(c) and s["class"] in [nil, c.class],
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
  def exp_gain(monster_exp, player_level, monster_level) do
    e = Config.get(["experience"])
    over = player_level - monster_level - e["levelDiffPenaltyStart"]

    ratio =
      if over > 0, do: max(e["minExpRatio"], 1 - over * e["levelDiffPenaltyPerLevel"]), else: 1.0

    max(1, floor(monster_exp * e["multiplier"] * ratio))
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

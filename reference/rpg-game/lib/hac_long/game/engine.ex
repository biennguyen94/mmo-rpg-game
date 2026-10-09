defmodule HacLong.Game.Engine do
  @moduledoc """
  Luật chơi: chỉ số nhân vật, sinh quái, chiến đấu, lên cấp, mua bán.

  Mọi hàm đều thuần: nhận trạng thái nhân vật (map) và trả về `{kết_quả, nhân_vật_mới}`.
  Trạng thái được gửi nguyên cho client (JSON) để vẽ giao diện, nên tên khóa
  theo kiểu JS (`maxHp`, `skillCd`...). Số ngẫu nhiên lấy qua `HacLong.Game.Rng`
  để test cố định được kết quả.
  """

  alias HacLong.Game.{Bestiary, Crafting, Data, Events, Gear, Home, Pets, Rng}

  @save_version 1
  # số luật chơi: `RULES` trong `priv/game_data/rules.json`
  @rules Data.rules()
  @char @rules.character
  @combat @rules.combat
  @effects @rules.skill_effects
  @mon @rules.monster
  @loot @rules.loot
  @max_level @char.max_level
  @pet_sk @rules.pets.skills
  @up @rules.upgrade
  @shop @rules.shop
  @log_limit 60
  # bình máu / bình mana (Phase 12): hồi theo phần trăm máu / MP tối đa (`heal_pct`, `mana_pct`)
  @potions ~w(potion_s potion_m potion_l)
  @manas ~w(mana_s mana_m mana_l)
  # Sức mạnh, Nhanh nhẹn, Thể lực, Năng lượng (như MU)
  @stats ~w(str agi vit ene)a
  # mỗi lượt của người chơi hồi `mp_regen` × MP tối đa + `mp_regen_ene` × Năng lượng (Phase 12, 12-A)
  @mp_regen @combat.mp_regen
  @mp_regen_ene @combat.mp_regen_ene
  @skill_mp_per_level @combat.skill_mp_per_level
  @max_batch 99
  # vũ khí, giáp, khiên, cánh
  @equip_slots ~w(weapon armor shield wing)
  @max_rebirths @char.max_rebirths
  @rebirth_points @char.rebirth_points

  def equip_slots, do: @equip_slots
  @doc "Điểm tiềm năng mỗi lần lên cấp của lớp `cls` (Đấu Sĩ 7, lớp khác 5)."
  def points_per_level(cls), do: Data.class(cls).points

  def stats, do: @stats
  def max_level, do: @max_level

  # ---------- Ngẫu nhiên ----------
  defp rand(a, b), do: a + Rng.uniform() * (b - a)
  defp chance(p), do: Rng.uniform() < p
  defp pick(list), do: Enum.at(list, floor(Rng.uniform() * length(list)))
  defp clamp(v, lo, hi), do: max(lo, min(hi, v))

  defp ok(msg \\ nil), do: if(msg, do: %{ok: true, msg: msg}, else: %{ok: true})
  defp err(msg), do: %{ok: false, msg: msg}

  # ---------- Nhân vật ----------
  def new_player(name, cls) do
    case Data.class(cls) do
      nil ->
        {:error, "Lớp nhân vật không hợp lệ"}

      c ->
        name =
          case name |> to_string() |> String.trim() |> String.slice(0, 16) do
            "" -> "Hiệp Khách"
            n -> n
          end

        p = %{
          version: @save_version,
          name: name,
          cls: cls,
          level: 1,
          xp: 0,
          gold: @char.start_gold,
          stats: c.base,
          mp: 0,
          points: 0,
          equip: %{weapon: "club", armor: "vest", shield: nil, wing: nil},
          inv: @char.start_items,
          upgrades: %{},
          gear: [],
          bestiary: %{},
          rebirths: 0,
          chest_day: nil,
          pet: nil,
          pets: [],
          pet_xp: %{},
          daily_done: 0,
          boss_top: 0,
          food: nil,
          crafting: %{cook: 0, smith: 0},
          festival: 0,
          furniture: %{},
          decor: [],
          storage: %{inv: %{}, extra: 0},
          fish_caught: 0,
          achievements: [],
          title: nil,
          bosses: [],
          kills: 0,
          deaths: 0,
          victory: false,
          battle: nil,
          hp: 0
        }

        d = derived(p)
        {:ok, %{p | hp: d.maxHp, mp: d.maxMp}}
    end
  end

  @doc """
  Chỉ số dẫn xuất. Công thức theo lớp ở `CLASSES[lớp].derived` (`priv/game_data/classes.json`): mỗi chỉ số là
  tổng `hệ_số × giá_trị` với giá trị là một chỉ số gốc (`str`, `agi`, `vit`, `ene`), `level` hoặc
  `base` (= 1). Chí mạng và né theo Nhanh nhẹn, như nhau cho mọi lớp.
  """
  def derived(p) do
    # chỉ số cộng thêm của đồ ngẫu nhiên đang mặc
    s = Map.merge(p.stats, Gear.bonus_stats(p), fn _, a, b -> a + b end)
    f = Data.class(p.cls).derived
    w = Gear.item(p, p.equip.weapon)
    a = Gear.item(p, p.equip.armor)
    sh = Gear.item(p, p.equip.shield)
    wg = Gear.item(p, p.equip[:wing])

    up = fn id -> if id, do: upgrade_bonus(p, id) + life_bonus(p, id), else: 0 end

    lin = fn terms ->
      Enum.reduce(terms, 0, fn
        {:level, k}, acc -> acc + k * p.level
        {:base, k}, acc -> acc + k
        {stat, k}, acc -> acc + k * Map.get(s, stat, 0)
      end)
    end

    # thú cưng đang dắt theo và món đang ăn cộng phần trăm
    pet = fn key -> 1 + Pets.bonus(p, key) + Crafting.food_bonus(p, key) end

    %{
      maxHp: round(lin.(f.hp) * pet.(:hp)),
      maxMp: round(lin.(f.mp)),
      atk: round((lin.(f.atk) + if(w, do: w.atk, else: 0) + up.(p.equip.weapon)) * pet.(:atk)),
      def:
        round(
          (lin.(f.def) + if(a, do: a.def, else: 0) + if(sh, do: sh.def, else: 0) +
             if(wg, do: wg.def, else: 0) + up.(p.equip.armor) + up.(p.equip.shield) +
             up.(p.equip[:wing])) * pet.(:def)
        ),
      crit: clamp(@combat.crit.base + s.agi * @combat.crit.per_agi, 0, @combat.crit.max),
      critMult:
        min(@combat.crit_mult.max, @combat.crit_mult.base + s.agi * @combat.crit_mult.per_agi),
      # attack rate: tỉ lệ đòn thường trúng quái (`hit_chance/2`)
      ar: p.level * @combat.hit.level + s.agi * @combat.hit.agi,
      dodge: clamp(@combat.dodge.base + s.agi * @combat.dodge.per_agi, 0, @combat.dodge.max),
      # cánh: phần sát thương gây thêm / giảm khi nhận (mỗi cấp nâng +2 %)
      wingDmg: wing_pct(p, wg, :dmg),
      wingAbsorb: wing_pct(p, wg, :absorb)
    }
    |> with_ranges(p.level)
  end

  # đòn thấp ~ cao và tỉ lệ trúng quái cùng cấp, để hiện ở bảng nhân vật
  defp with_ranges(d, level) do
    [lo, hi] = @combat.damage_spread

    Map.merge(d, %{
      atkMin: round(d.atk * lo),
      atkMax: round(d.atk * hi),
      hitRate: hit_chance(d.ar, level)
    })
  end

  defp wing_pct(_p, nil, _key), do: 0

  defp wing_pct(p, wg, key),
    do:
      Float.round(wg[key] + @combat.wing_per_level * effective_level(upgrade_level(p, wg.uid)), 3)

  @doc """
  Các chỉ số tính ra từ trạng thái, gửi kèm cho client để hiển thị
  (client không có công thức nào).
  """
  def view(p) do
    %{
      derived: derived(p),
      xpToNext: xp_to_next(p.level),
      restCost: rest_cost(p),
      unlocked: Enum.map(0..(Data.zone_count() - 1), &zone_unlocked?(p, &1)),
      look: look(p),
      comfort: Home.comfort(p),
      # cộng thêm của đồ đã nâng cấp (để client so sánh đồ) và giá nâng cấp đồ đang mặc
      bonus:
        (Map.keys(upgrades(p)) ++ for(g <- Gear.list(p), g[:opt], do: g.uid))
        |> Map.new(&{&1, upgrade_bonus(p, &1) + life_bonus(p, &1)}),
      # giá ép từng món trong túi (đồ hiếm chưa cất, đồ thường mặc được), cho nút "Ép" trong tooltip
      forgeBag:
        for id <- Enum.map(Gear.bag(p), & &1.uid) ++ Map.keys(p.inv),
            (it = Gear.item(p, id)) && it.slot in @equip_slots,
            into: %{} do
          {id, %{level: upgrade_level(p, id), cost: upgrade_cost(it, upgrade_level(p, id))}}
        end,
      storage: HacLong.Game.Storage.view(p),
      forge:
        for {slot, id} <- p.equip, id != nil, into: %{} do
          {slot,
           %{
             id: id,
             level: upgrade_level(p, id),
             cost: upgrade_cost(Gear.item(p, id), upgrade_level(p, id))
           }}
        end,
      # đồ ngẫu nhiên (cả món đang mặc) đã tính tên, chỉ số, giá bán
      gear: Map.new(Map.get(p, :gear) || [], &{&1.uid, Gear.resolve(&1)})
    }
  end

  def xp_to_next(lv), do: round(@rules.xp.coef * :math.pow(lv, @rules.xp.exp) + @rules.xp.base)

  def zone_unlocked?(_p, 0), do: true

  def zone_unlocked?(p, zi) do
    case Data.zone(zi - 1) do
      nil -> false
      z -> z.boss.id in p.bosses
    end
  end

  # ---------- Quái ----------
  def make_monster(spec, boss?) do
    l = spec.level
    m = Map.get(spec, :mult, 1)
    [gs_lo, gs_hi] = @mon.gold_spread
    bm = if boss?, do: @mon.boss.hp, else: 1
    # thưởng nhân thêm (quái vàng Golden Invasion), không đổi sức mạnh
    rw = Map.get(spec, :reward_mult, 1)

    %{
      id: spec.id,
      name: spec.name,
      level: l,
      boss: boss?,
      final: Map.get(spec, :final, false),
      special: Map.get(spec, :special),
      on_hit: Map.get(spec, :on_hit),
      night: Map.get(spec, :night, false),
      golden: Map.get(spec, :golden, false),
      jewel_chance: Map.get(spec, :jewel_chance),
      maxHp: round((@mon.hp.base + l * @mon.hp.level + l * l * @mon.hp.level_sq) * m * bm),
      atk: round((@mon.atk.base + l * @mon.atk.level) * m * 1),
      def: round((@mon.def.base + l * @mon.def.level) * m),
      crit: @mon.crit,
      dodge: @mon.dodge.base + l * @mon.dodge.level,
      xp: round(base_xp(l) * m * rw * if(boss?, do: @mon.boss.xp, else: 1)),
      gold:
        round(base_gold(l) * m * rw * rand(gs_lo, gs_hi) * if(boss?, do: @mon.boss.gold, else: 1))
    }
  end

  @doc "Kinh nghiệm gốc của quái cấp `l` (chưa nhân hệ số), dùng chung cho tháp, việc hằng ngày."
  def base_xp(l), do: @mon.xp.base + l * @mon.xp.level + l * l * @mon.xp.level_sq
  @doc "Vàng rơi gốc của quái cấp `l` (chưa nhân hệ số, chưa may rủi)."
  def base_gold(l), do: @mon.gold.base + l * @mon.gold.level

  @doc """
  Sát thương một đòn (`RULES.combat`, `INTEGRATION_PLAN §11.2`), chỉ làm tròn ở bước cuối:

  1. đòn gốc ngẫu nhiên trong `công × damage_spread` (đòn thấp ~ cao);
  2. × `mult` (kỹ năng, chí mạng, sổ quái, % cánh);
  3. trừ thủ kiểu Hắc Long `đòn² / (đòn + thủ)`;
  4. sàn mềm: không dưới `soft_floor` × đòn ở bước 2;
  5. × `taken` (thủ thế, hấp thụ của cánh khi bị đánh);
  6. sàn cứng 1.
  """
  def damage(atk, dfn, mult \\ 1, taken \\ 1) do
    [lo, hi] = @combat.damage_spread
    raw = atk * rand(lo, hi) * mult

    hit =
      if raw > 0,
        do: max(raw * raw / (raw + max(dfn, 0)), raw * @combat.soft_floor),
        else: 0

    max(1, round(hit * taken))
  end

  @doc "Tỉ lệ đòn người chơi (attack rate `ar`) trúng quái cấp `level`: `AR / (AR + DR)`, chặn trong `[min, max]`."
  def hit_chance(ar, level) do
    h = @combat.hit
    dr = level * h.monster_dr
    clamp(ar / (ar + dr), h.min, h.max)
  end

  @doc "Phần EXP còn lại khi hạ quái thường thấp hơn mình quá `RULES.xp.penalty.from` cấp (1 = không phạt)."
  def xp_factor(player_level, monster_level) do
    pen = @rules.xp.penalty
    gap = player_level - monster_level

    if gap > pen.from,
      do: max(pen.min, 1 - pen.per_level * (gap - pen.from)),
      else: 1
  end

  # ---------- Chiến đấu ----------
  @doc "Trận với một con quái ngẫu nhiên của vùng (dùng cho bot mô phỏng)."
  def start_battle(p, zi, boss?) do
    z = if is_integer(zi), do: Data.zone(zi)

    with :ok <- can_fight(p, zi, z) do
      # Quái thường: ưu tiên con không quá cấp người chơi + 1 để người mới không bị đánh úp.
      spec =
        if boss? do
          z.boss
        else
          fair = Enum.filter(z.monsters, &(&1.level <= p.level + 1))
          pick(if fair == [], do: [hd(z.monsters)], else: fair)
        end

      do_start_battle(p, zi, spec, boss?)
    end
  end

  @doc "Trận với đúng con quái `spec` (người chơi vừa chạm vào nó trên bản đồ)."
  def start_encounter(p, zi, spec, boss?) do
    with :ok <- can_fight(p, zi, Data.zone(zi)), do: do_start_battle(p, zi, spec, boss?)
  end

  defp can_fight(p, zi, z) do
    cond do
      p.battle -> {err("Đang trong trận đấu."), p}
      z == nil or not zone_unlocked?(p, zi) -> {err("Khu vực chưa mở."), p}
      p.hp <= 0 -> {err("Bạn cần hồi máu trước."), p}
      true -> :ok
    end
  end

  @doc "Trận với một con quái đã dựng sẵn `m` (trùm thế giới). `zi`: vùng lấy hình nền."
  def start_with_monster(p, zi, m) do
    cond do
      p.battle -> {err("Đang trong trận đấu."), p}
      p.hp <= 0 -> {err("Bạn cần hồi máu trước."), p}
      true -> put_battle(p, zi, m, true)
    end
  end

  defp do_start_battle(p, zi, spec, boss?) do
    m = make_monster(spec, boss?)
    put_battle(p, zi, Map.put(m, :hp, m.maxHp), boss?)
  end

  defp put_battle(p, zi, m, boss?) do
    battle = %{
      zone: zi,
      monster: m,
      turn: 0,
      # hồi chiêu từng kỹ năng: [%{id, turns}]
      cds: [],
      # hiệu ứng trạng thái: [%{id, turns, power}] của mỗi bên
      effects: %{player: [], monster: []},
      log: [],
      over: false,
      result: nil,
      reward: nil
    }

    text =
      if boss?,
        do: "⚔️ #{m.name} (Cấp #{m.level}) xuất hiện!",
        else: "Bạn gặp #{m.name} (Cấp #{m.level})."

    {ok(), p |> Map.put(:battle, battle) |> log(text, "info")}
  end

  defp log(p, text, kind) do
    entries = p.battle.log ++ [%{text: text, kind: kind}]
    entries = if length(entries) > @log_limit, do: tl(entries), else: entries
    put_in(p.battle.log, entries)
  end

  @doc "Lượng hồi của bình `id` cho nhân vật `p` (theo % máu / MP tối đa): `{:hp | :mp, số}`."
  def potion_amount(p, id) do
    it = Data.item(id)
    d = derived(p)

    cond do
      it[:mana_pct] -> {:mp, max(1, round(d.maxMp * it.mana_pct))}
      it[:heal_pct] -> {:hp, max(1, round(d.maxHp * it.heal_pct))}
      true -> {:hp, it[:heal] || 0}
    end
  end

  @doc "Bình máu nhỏ nhất đủ hồi phần máu đã mất, không có thì bình lớn nhất đang có."
  def best_potion(p, missing), do: best(p, @potions, missing)

  @doc "Bình mana nhỏ nhất đủ hồi phần MP đã mất, không có thì bình lớn nhất đang có."
  def best_mana(p, missing), do: best(p, @manas, missing)

  defp best(p, ids, missing) do
    case Enum.filter(ids, &(Map.get(p.inv, &1, 0) > 0)) do
      [] -> nil
      owned -> Enum.find(owned, &(elem(potion_amount(p, &1), 1) >= missing)) || List.last(owned)
    end
  end

  defp drink(p, id) do
    d = derived(p)

    case potion_amount(p, id) do
      {:mp, n} ->
        before = mp(p)
        p = %{p | mp: min(d.maxMp, before + n)} |> take_item(id)
        {p, p.mp - before}

      {:hp, n} ->
        before = p.hp
        p = %{p | hp: min(d.maxHp, p.hp + n)} |> take_item(id)
        {p, p.hp - before}
    end
  end

  @doc """
  MP kỹ năng tốn ở cấp hiện tại (Phase 12): `mp` gốc của kỹ năng (kỹ năng mạnh gốc cao hơn) ×
  (1 + `skill_mp_per_level` × (cấp − 1)), để MP vẫn là giới hạn khi MP tối đa tăng theo cấp.
  """
  def skill_mp(p, skill), do: round((skill[:mp] || 0) * (1 + @skill_mp_per_level * (p.level - 1)))

  # ---------- Kỹ năng ----------

  @doc "Các kỹ năng đã mở ở cấp hiện tại (mỗi lớp mở thêm kỹ năng ở cấp 10 và 25)."
  def skills(p), do: Enum.filter(Data.class(p.cls).skills, &(&1.level <= p.level))

  @doc "Số lượt còn phải chờ để dùng lại kỹ năng `id` trong trận hiện tại."
  def cooldown(%{battle: %{} = b}, id) do
    case Enum.find(Map.get(b, :cds) || [], &(&1.id == id)) do
      nil -> 0
      c -> c.turns
    end
  end

  def cooldown(_p, _id), do: 0

  defp set_cd(p, id, turns) do
    cds = (Map.get(p.battle, :cds) || []) |> Enum.reject(&(&1.id == id))
    %{p | battle: Map.put(p.battle, :cds, cds ++ [%{id: id, turns: turns}])}
  end

  # ---------- Hiệu ứng trạng thái ----------
  # Độc, bỏng, chảy máu (`power` là số máu mất mỗi lượt); choáng (mất lượt kế tiếp);
  # suy yếu (tấn công giảm `power`); cuồng nộ (tấn công tăng); thủ thế (sát thương nhận
  # giảm); ảnh bộ (né thêm). Cuối mỗi lượt tính độc rồi giảm số lượt còn lại.

  @dots ~w(poison burn bleed)
  @effect_names %{
    "poison" => "trúng độc",
    "burn" => "bị bỏng",
    "bleed" => "chảy máu",
    "stun" => "bị choáng",
    "weaken" => "suy yếu",
    "rage" => "cuồng nộ",
    "guard" => "thủ thế",
    "evade" => "ảnh bộ"
  }

  def effect_names, do: @effect_names

  defp effects(p, who), do: (Map.get(p.battle, :effects) || %{})[who] || []
  defp effect(p, who, id), do: Enum.find(effects(p, who), &(&1.id == id))

  defp power(p, who, id) do
    case effect(p, who, id) do
      nil -> 0
      e -> e.power
    end
  end

  defp set_effects(p, who, list) do
    all = Map.get(p.battle, :effects) || %{player: [], monster: []}
    %{p | battle: Map.put(p.battle, :effects, Map.put(all, who, list))}
  end

  defp put_effect(p, who, id, turns, power) do
    list = p |> effects(who) |> Enum.reject(&(&1.id == id))
    set_effects(p, who, list ++ [%{id: id, turns: turns, power: power}])
  end

  defp drop_effect(p, who, id),
    do: set_effects(p, who, p |> effects(who) |> Enum.reject(&(&1.id == id)))

  # ---------- Lượt đánh ----------

  @doc """
  action: "attack" | "skill" | "potion" | "mana" | "flee". Với "skill", `skill_id` chọn kỹ năng
  (không có thì dùng kỹ năng đầu tiên).
  """
  def act(p, action, skill_id \\ nil) do
    b = p.battle

    cond do
      b == nil or b.over ->
        {err("Không có trận đấu."), p}

      action not in ~w(attack skill potion mana flee) ->
        {err("Thao tác không hợp lệ."), p}

      effect(p, :player, "stun") ->
        p
        |> next_turn()
        |> drop_effect(:player, "stun")
        |> log("💫 Bạn bị choáng, mất một lượt.", "bad")
        |> monster_turn(derived(p))

      action in ~w(attack skill) ->
        act_strike(p, action, skill_id, derived(p))

      action == "potion" ->
        act_potion(p, derived(p))

      action == "mana" ->
        act_mana(p, derived(p))

      true ->
        act_flee(p, derived(p))
    end
  end

  # Sang lượt mới của người chơi: hồi một phần MP.
  defp next_turn(p) do
    p = %{p | mp: min(derived(p).maxMp, mp(p) + mp_regen(p))}
    update_in(p.battle.turn, &(&1 + 1))
  end

  defp mp(p), do: Map.get(p, :mp) || 0

  @doc "MP hồi mỗi lượt trong trận: `mp_regen` × MP tối đa + `mp_regen_ene` × Năng lượng (cả đồ cộng)."
  def mp_regen(p) do
    ene = Map.get(p.stats, :ene, 0) + Map.get(Gear.bonus_stats(p), :ene, 0)
    max(1, round(derived(p).maxMp * @mp_regen + ene * @mp_regen_ene))
  end

  defp act_mana(p, d) do
    id = best_mana(p, d.maxMp - mp(p))

    cond do
      id == nil ->
        {err("Hết bình mana."), p}

      mp(p) >= d.maxMp ->
        {err("MP đang đầy."), p}

      true ->
        {p, got} = p |> next_turn() |> drink(id)
        p |> log("Bạn uống #{Data.item(id).name}, hồi #{got} MP.", "good") |> monster_turn(d)
    end
  end

  defp act_flee(p, d) do
    p = next_turn(p)

    if chance(if p.battle.monster.boss, do: @combat.flee_chance_boss, else: @combat.flee_chance) do
      p |> log("Bạn đã bỏ chạy thành công.", "info") |> finish("fled")
    else
      p |> log("Bỏ chạy thất bại!", "bad") |> monster_turn(d)
    end
  end

  defp act_potion(p, d) do
    id = best_potion(p, d.maxHp - p.hp)
    poisoned = Enum.filter(effects(p, :player), &(&1.id in @dots))

    cond do
      id == nil ->
        {err("Hết bình máu."), p}

      p.hp >= d.maxHp and poisoned == [] ->
        {err("Máu đang đầy."), p}

      true ->
        {p, healed} = p |> next_turn() |> drink(id)
        p = log(p, "Bạn uống #{Data.item(id).name}, hồi #{healed} máu.", "good")

        # bình máu giải luôn độc, bỏng, chảy máu
        p =
          if poisoned == [],
            do: p,
            else:
              p
              |> set_effects(:player, Enum.reject(effects(p, :player), &(&1.id in @dots)))
              |> log("Hết #{Enum.map_join(poisoned, ", ", &@effect_names[&1.id])}.", "good")

        monster_turn(p, d)
    end
  end

  defp pick_skill(p, nil), do: List.first(skills(p))
  defp pick_skill(p, id), do: Enum.find(skills(p), &(&1.id == id))

  defp act_strike(p, action, skill_id, d) do
    m = p.battle.monster
    skill = if action == "skill", do: pick_skill(p, skill_id)

    cond do
      action == "skill" and skill == nil ->
        {err("Chưa học kỹ năng này."), p}

      skill && cooldown(p, skill.id) > 0 ->
        {err("#{skill.name} hồi sau #{cooldown(p, skill.id)} lượt."), p}

      skill && mp(p) < skill_mp(p, skill) ->
        {err("Không đủ MP cho #{skill.name} (cần #{skill_mp(p, skill)})."), p}

      true ->
        p = next_turn(p)

        atk =
          round(d.atk * (1 + power(p, :player, "rage")) * (1 - power(p, :player, "weaken")))

        {p, atk, dfn, crit, mult, name, on_hit} =
          strike_with(p, skill, d, atk, m.def, chance(d.crit))

        # kỹ năng luôn trúng; đòn thường: đấu trường theo né của đối thủ, quái theo tỉ lệ trúng
        p =
          if skill == nil and
               if(m[:pvp], do: chance(m.dodge), else: chance(1 - hit_chance(d.ar, m.level))) do
            log(p, "Trượt! #{m.name} tránh được đòn #{name}.", "info")
          else
            # hiểu rõ loài này (sổ tay quái vật) thì đánh mạnh hơn
            mult = mult * (1 + Bestiary.mastery(p, m.id)) * (1 + d.wingDmg)
            dmg = damage(atk, dfn, mult * if(crit, do: d.critMult, else: 1))
            p = update_in(p.battle.monster.hp, &max(0, &1 - dmg))
            prefix = if skill, do: "✨ #{name}: ", else: ""
            suffix = if crit, do: " (CHÍ MẠNG!)", else: ""

            p
            |> log(
              "#{prefix}Bạn gây #{dmg} sát thương#{suffix}.",
              if(crit, do: "crit", else: "hit")
            )
            |> on_hit.(dmg)
          end

        p = pet_bite(p, d)
        if p.battle.monster.hp <= 0, do: win(p), else: monster_turn(p, d)
    end
  end

  # Thú cưng đi theo thỉnh thoảng cắn thêm (khi quái còn sống)
  defp pet_bite(p, d) do
    m = p.battle.monster

    bite =
      if m.hp > 0 and Map.get(p, :pet),
        do: Pets.bite(p, damage(d.atk, m.def), Rng.uniform()),
        else: 0

    if bite > 0 do
      sk = Pets.active_skill(p)
      bite = if sk && sk.id == "rend", do: bite * @pet_sk.rend_mult, else: bite
      what = if sk && sk.id == "rend", do: "#{sk.name}: ", else: ""

      p
      |> update_in([:battle, :monster, :hp], &max(0, &1 - bite))
      |> log("🐾 #{Pets.name(p)} #{what}cắn thêm #{bite} sát thương.", "hit")
      |> pet_skill(sk, d, bite)
    else
      p
    end
  end

  # kỹ năng riêng của thú (từ cấp 5), dùng khi thú cắn
  defp pet_skill(p, %{id: "heal"} = sk, d, _bite) do
    healed = min(d.maxHp - p.hp, max(1, round(d.maxHp * @pet_sk.heal)))

    if healed > 0,
      do: %{p | hp: p.hp + healed} |> log("🐾 #{sk.name}: hồi #{healed} máu.", "good"),
      else: p
  end

  defp pet_skill(p, %{id: "bash"} = sk, _d, _bite) do
    p
    |> put_effect(:monster, "weaken", @pet_sk.bash_turns, @pet_sk.bash_power)
    |> log("🐾 #{sk.name}: #{p.battle.monster.name} bị suy yếu.", "good")
  end

  defp pet_skill(p, %{id: "pickpocket"} = sk, _d, _bite) do
    gold = max(1, p.battle.monster.level * @pet_sk.pickpocket_per_level)
    %{p | gold: p.gold + gold} |> log("🐾 #{sk.name}: móc được #{gold} vàng.", "good")
  end

  defp pet_skill(p, %{id: "venom"} = sk, _d, bite) do
    if p.battle.monster.hp > 0 do
      p
      |> put_effect(
        :monster,
        "poison",
        @pet_sk.venom_turns,
        max(1, round(bite * @pet_sk.venom_power))
      )
      |> log("🐾 #{sk.name}: #{p.battle.monster.name} trúng độc.", "good")
    else
      p
    end
  end

  defp pet_skill(p, _sk, _d, _bite), do: p

  # Trả về {nhân_vật, tấn_công, phòng_thủ_quái, chí_mạng?, hệ_số, tên, hàm_sau_khi_trúng}.
  defp strike_with(p, nil, _d, atk, dfn, crit),
    do: {p, atk, dfn, crit, 1, "tấn công", fn p, _ -> p end}

  defp strike_with(p, skill, d, atk, dfn, crit) do
    # +1 vì cuối lượt sẽ trừ 1
    p = set_cd(p, skill.id, skill.cooldown + 1)
    p = %{p | mp: mp(p) - skill_mp(p, skill)}
    m = p.battle.monster
    none = fn p, _ -> p end

    # tác dụng theo `effect` (kỹ năng các lớp dùng chung vài kiểu tác dụng), số ở `RULES.skill_effects`
    effect = skill[:effect] || skill.id
    e = @effects[String.to_existing_atom(effect)]
    dfn = if e[:def_mult], do: round(dfn * e.def_mult), else: dfn
    crit = e[:always_crit] || crit
    pct = fn x -> round(x * 100) end

    case effect do
      "holy" ->
        heal = round(d.maxHp * e.heal)
        before = p.hp
        p = %{p | hp: min(d.maxHp, p.hp + heal)}

        {log(p, "Khiên Thánh hồi #{p.hp - before} máu.", "good"), atk, dfn, crit, e.mult,
         skill.name, none}

      "stun_bash" ->
        {p, atk, dfn, crit, e.mult, skill.name,
         fn p, _ ->
           if (m.boss || m[:world]) && chance(e.boss_resist),
             do: log(p, "#{m.name} không bị choáng.", "info"),
             else:
               p |> put_effect(:monster, "stun", 1, 0) |> log("💫 #{m.name} bị choáng!", "good")
         end}

      "war_cry" ->
        {p, atk, dfn, crit, e.mult, skill.name,
         fn p, _ ->
           p
           |> put_effect(:player, "rage", e.turns, e.power)
           |> log("Bạn nổi cuồng nộ: tấn công +#{pct.(e.power)}%.", "good")
         end}

      "venom" ->
        {p, atk, dfn, crit, e.mult, skill.name,
         fn p, dmg ->
           p
           |> put_effect(:monster, "poison", e.turns, max(1, round(dmg * e.power)))
           |> log("☠ #{m.name} trúng độc.", "good")
         end}

      "shadow_step" ->
        {p, atk, dfn, crit, e.mult, skill.name,
         fn p, _ ->
           p
           |> put_effect(:player, "evade", e.turns, e.power)
           |> log("Bạn nhập ảnh bộ: né +#{pct.(e.power)}%.", "good")
         end}

      "guard" ->
        {p, atk, dfn, crit, e.mult, skill.name,
         fn p, _ ->
           p
           |> put_effect(:player, "guard", e.turns, e.power)
           |> log("Bạn giơ khiên thủ thế: sát thương nhận -#{pct.(e.power)}%.", "good")
         end}

      "judgement" ->
        {p, atk, dfn, crit, e.mult, skill.name,
         fn p, _ ->
           p
           |> put_effect(:monster, "weaken", e.turns, e.power)
           |> log("#{m.name} bị suy yếu: tấn công -#{pct.(e.power)}%.", "good")
         end}

      # cleave, fire_ball, backstab: chỉ đánh mạnh hơn (hệ số, bỏ qua giáp, chắc chí mạng)
      _ ->
        {p, atk, dfn, crit, e.mult, skill.name, none}
    end
  end

  defp monster_turn(p, d) do
    b = p.battle
    m = b.monster

    if effect(p, :monster, "stun") do
      p
      |> drop_effect(:monster, "stun")
      |> log("💫 #{m.name} bị choáng, không đánh được.", "good")
      |> round_end()
    else
      special = m.special != nil and rem(b.turn, m.special.every) == 0
      m_atk = if special, do: round(m.atk * m.special.mult), else: m.atk
      m_atk = round(m_atk * (1 - power(p, :monster, "weaken")))

      p =
        if not special and chance(d.dodge + power(p, :player, "evade")) do
          log(p, "Bạn né được đòn của #{m.name}.", "info")
        else
          mc = not special and chance(m.crit)

          dmg =
            damage(
              m_atk,
              d.def,
              if(mc, do: @combat.monster_crit_mult, else: 1),
              (1 - power(p, :player, "guard")) * (1 - d.wingAbsorb)
            )

          p = %{p | hp: max(0, p.hp - dmg)}

          text =
            if special,
              do: "🔥 #{m.name} dùng #{m.special.name}! Bạn mất #{dmg} máu.",
              else: "#{m.name} đánh bạn #{dmg} máu#{if mc, do: " (chí mạng)", else: ""}."

          p = log(p, text, "bad")

          cond do
            special and m.special[:effect] ->
              inflict(p, m, m.special.effect)

            not special and m[:on_hit] && chance(m.on_hit.chance) ->
              inflict(p, m, m.on_hit)

            true ->
              p
          end
        end

      if p.hp <= 0, do: lose(p), else: round_end(p)
    end
  end

  # Quái gây hiệu ứng lên người chơi.
  defp inflict(p, m, e) do
    case e.id do
      id when id in @dots ->
        per = max(1, round(m.atk * e.power))

        p
        |> put_effect(:player, id, e.turns, per)
        |> log("Bạn #{@effect_names[id]} (-#{per} máu mỗi lượt, uống bình máu để giải).", "bad")

      "stun" ->
        p |> put_effect(:player, "stun", 1, 0) |> log("💫 Bạn bị choáng!", "bad")

      "weaken" ->
        p
        |> put_effect(:player, "weaken", e.turns, e.power)
        |> log("Bạn bị suy yếu: tấn công -#{round(e.power * 100)}%.", "bad")
    end
  end

  # Cuối lượt: độc trên quái rồi trên người chơi, sau đó giảm số lượt hiệu ứng và hồi chiêu.
  defp round_end(p) do
    m = p.battle.monster

    mdot =
      p
      |> effects(:monster)
      |> Enum.filter(&(&1.id in @dots))
      |> Enum.map(& &1.power)
      |> Enum.sum()

    p =
      if mdot > 0 do
        p
        |> update_in([:battle, :monster, :hp], &max(0, &1 - mdot))
        |> log("☠ #{m.name} mất #{mdot} máu vì độc.", "hit")
      else
        p
      end

    if p.battle.monster.hp <= 0 do
      win(p)
    else
      pdots = p |> effects(:player) |> Enum.filter(&(&1.id in @dots))
      pdot = pdots |> Enum.map(& &1.power) |> Enum.sum()

      p =
        if pdot > 0 do
          p = %{p | hp: max(0, p.hp - pdot)}

          log(
            p,
            "Bạn mất #{pdot} máu vì #{Enum.map_join(pdots, ", ", &@effect_names[&1.id])}.",
            "bad"
          )
        else
          p
        end

      if p.hp <= 0 do
        lose(p)
      else
        tick = fn list ->
          list
          |> Enum.map(fn e -> if e.id == "stun", do: e, else: %{e | turns: e.turns - 1} end)
          |> Enum.filter(&(&1.turns > 0))
        end

        p =
          p
          |> set_effects(:player, tick.(effects(p, :player)))
          |> set_effects(:monster, tick.(effects(p, :monster)))

        cds =
          (Map.get(p.battle, :cds) || [])
          |> Enum.map(&%{&1 | turns: &1.turns - 1})
          |> Enum.filter(&(&1.turns > 0))

        {ok(), %{p | battle: Map.put(p.battle, :cds, cds)}}
      end
    end
  end

  # lễ hội: quái thường có thể rơi vật phẩm lễ hội, trùm rơi 3 cái
  defp event_drop(p, _m, nil, reward), do: {p, reward}

  defp event_drop(p, m, event, reward) do
    n =
      cond do
        m.boss or m[:world] -> @loot.event_token_boss
        chance(Events.drop_chance()) -> 1
        true -> 0
      end

    if n > 0 do
      name = Data.item(event.token).name
      p = p |> add_item(event.token, n) |> log("#{event.icon} Nhặt được #{name} ×#{n}.", "good")
      {p, %{reward | items: reward.items ++ [event.token]}}
    else
      {p, reward}
    end
  end

  @doc "Kết thúc trận bằng chiến thắng dù quái chưa hết máu ở trận này (đồng đội hạ quái)."
  def finish_win(%{battle: %{over: false}} = p) do
    p |> put_in([:battle, :monster, :hp], 0) |> win()
  end

  def finish_win(p), do: {ok(), p}

  defp win(p) do
    m = p.battle.monster
    # thú cưng (vàng, kinh nghiệm) và nhà trang trí (kinh nghiệm) cộng thêm
    event = if m[:pvp], do: nil, else: Events.current()
    gold = round(m.gold * (1 + Pets.bonus(p, :gold) + Crafting.food_bonus(p, :gold)))

    # quái thường thấp hơn mình quá nhiều cấp thì bớt EXP (không áp trùm, tháp, trùm thế giới, đấu trường)
    normal? = not m.boss and !m[:world] and !m[:pvp] and !m[:tower]
    xf = if normal?, do: xp_factor(p.level, m.level), else: 1

    xp =
      round(
        m.xp * xf *
          (1 + Pets.bonus(p, :xp) + Home.xp_bonus(p) + Crafting.food_bonus(p, :xp) +
             Events.xp_bonus(event))
      )

    p = %{p | kills: p.kills + 1, gold: p.gold + gold}
    reward = %{xp: xp, gold: gold, items: [], levels: 0}

    p =
      if m[:world],
        do: log(p, "🏆 #{m.name} gục ngã dưới đòn của bạn!", "win"),
        else:
          log(
            p,
            "🏆 Bạn đã hạ #{m.name}! +#{xp} kinh nghiệm#{if xf < 1, do: " (−#{round((1 - xf) * 100)}% vì cao hơn quái #{p.level - m.level} cấp)"}, +#{gold} vàng.",
            "win"
          )

    {p, reward} =
      if not m.boss and !m[:world] and !m[:pvp] and chance(@loot.potion_chance) do
        id = Data.potion_for(m.level)

        p = p |> add_item(id) |> log("Nhặt được #{Data.item(id).name}.", "good")
        {p, %{reward | items: reward.items ++ [id]}}
      else
        {p, reward}
      end

    {p, reward} = jewel_drop(p, m, reward)
    {p, reward} = event_drop(p, m, event, reward)

    {p, reward} =
      if m.boss and m.id not in p.bosses, do: first_boss_kill(p, m, reward), else: {p, reward}

    {p, reward} = gear_drop(p, m, reward)

    {p, reward} =
      case !m[:pvp] && Bestiary.record(p, m) do
        false ->
          {p, reward}

        {p, nil} ->
          {p, reward}

        {p, mark} ->
          text =
            "📖 Sổ tay: đã hạ #{mark.kills} #{m.name}! Đánh loài này +#{round(mark.bonus * 100)}% sát thương, thưởng #{mark.gold} vàng."

          {%{p | gold: p.gold + mark.gold} |> log(text, "win"),
           %{reward | gold: reward.gold + mark.gold}}
      end

    {p, pet_up} = if m[:pvp], do: {p, nil}, else: Pets.gain(p, m.boss || m[:world] == true)

    p =
      cond do
        pet_up == Pets.skill_level() ->
          log(
            p,
            "🐾 #{Pets.name(p)} lên cấp #{pet_up}, học được #{Pets.skill(p.pet).name}!",
            "win"
          )

        pet_up ->
          log(p, "🐾 #{Pets.name(p)} lên cấp #{pet_up}!", "win")

        true ->
          p
      end

    {levels, p} = gain_xp(p, xp)

    p =
      if levels > 0,
        do:
          log(
            p,
            "⭐ Lên cấp #{p.level}! Nhận #{levels * points_per_level(p.cls)} điểm tiềm năng.",
            "win"
          ),
        else: p

    p = put_in(p.battle.reward, %{reward | levels: levels})
    finish(p, "win")
  end

  # Ngọc ép đồ (bảng `JEWELS`): quái cấp cao hiếm khi rơi, trùm vùng hay rơi. Trùm trong tháp tính
  # như quái thường (leo lại tháp được nên không cho cày ngọc ở đó).
  defp jewel_drop(p, m, reward) do
    j = Data.jewels()
    tower? = p.battle[:encounter][:tower] != nil

    c =
      cond do
        m[:world] || m[:pvp] -> 0
        m[:jewel_chance] -> m.jewel_chance
        m.boss and not tower? -> j.boss_chance
        m.level >= j.monster_level -> j.monster_chance
        true -> 0
      end

    if c > 0 and chance(c) do
      id = pick_jewel()
      p = p |> add_item(id) |> log("💎 Nhặt được #{Data.item(id).name}!", "win")
      {p, %{reward | items: reward.items ++ [id]}}
    else
      {p, reward}
    end
  end

  @doc "Một viên ngọc ngẫu nhiên theo trọng số `JEWELS.weights`."
  def pick_jewel do
    w = Enum.sort(Data.jewels().weights)
    r = Rng.uniform() * (w |> Enum.map(&elem(&1, 1)) |> Enum.sum())

    Enum.reduce_while(w, 0, fn {id, n}, acc ->
      if r < acc + n, do: {:halt, id}, else: {:cont, acc + n}
    end)
  end

  # Đồ có chỉ số ngẫu nhiên (xem `Gear`).
  defp gear_drop(p, m, reward) do
    with true <- chance(Gear.drop_chance(m)),
         %{} = g <- Gear.roll(m.level) do
      it = Gear.resolve(g)
      label = "#{it.name} (#{Gear.rarity_names()[g.rarity]})"

      case Gear.add(p, g) do
        {p, :kept} ->
          {log(p, "🎁 Nhặt được #{label}!", "win"), Map.put(reward, :gear, [label])}

        {p, {:sold, gold}} ->
          {log(p, "🎁 Nhặt được #{label}, túi đầy nên bán luôn được #{gold} vàng.", "good"),
           Map.put(reward, :gear, [label])}
      end
    else
      _ -> {p, reward}
    end
  end

  defp first_boss_kill(p, m, reward) do
    p = %{p | bosses: p.bosses ++ [m.id]}

    {p, reward} =
      case Data.boss_drop(m.id) do
        nil ->
          {p, reward}

        drop ->
          p = p |> add_item(drop) |> log("Trùm rơi ra #{Data.item(drop).name}!", "win")
          {p, %{reward | items: reward.items ++ [drop]}}
      end

    next = Data.zone(p.battle.zone + 1)

    p =
      cond do
        m.final ->
          %{p | victory: true} |> log("Hắc Long đã gục ngã. Vùng đất được giải phóng!", "win")

        next ->
          log(p, "Đã mở khu vực mới: #{next.name}.", "win")

        true ->
          p
      end

    {p, reward}
  end

  defp lose(p) do
    lost = floor(p.gold * @char.death_gold_loss)
    p = %{p | gold: p.gold - lost, deaths: p.deaths + 1}
    p = log(p, "💀 Bạn đã gục ngã... Mất #{lost} vàng. Dân làng đưa bạn về nhà trọ.", "bad")
    p = %{p | hp: round(derived(p).maxHp * @char.death_hp)}
    finish(p, "lose")
  end

  defp finish(p, result) do
    p = update_in(p.battle, &%{&1 | over: true, result: result}) |> Crafting.tick()
    {%{ok: true, result: result}, p}
  end

  def leave_battle(%{battle: %{over: true}} = p), do: {ok(), %{p | battle: nil}}
  def leave_battle(%{battle: nil} = p), do: {ok(), p}
  def leave_battle(p), do: {err("Trận đấu chưa kết thúc."), p}

  def gain_xp(p, xp), do: level_up(%{p | xp: p.xp + xp}, 0)

  defp level_up(p, levels) do
    if p.level < @max_level and p.xp >= xp_to_next(p.level) do
      %{
        p
        | xp: p.xp - xp_to_next(p.level),
          level: p.level + 1,
          points: p.points + points_per_level(p.cls)
      }
      |> level_up(levels + 1)
    else
      p = if p.level >= @max_level, do: %{p | xp: 0}, else: p
      # lên cấp hồi đầy máu và MP
      p =
        if levels > 0,
          do: Map.merge(p, %{hp: derived(p).maxHp, mp: derived(p).maxMp}),
          else: p

      {levels, p}
    end
  end

  # ---------- Ngoại hình ----------

  @doc """
  Ngoại hình để vẽ nhân vật (và gửi cho người khác trên bản đồ): lớp tóc theo lớp nhân vật,
  lớp hình của vũ khí, giáp, khiên đang mặc (`doll` trong dữ liệu đồ) và thú cưng đang dắt.
  """
  def look(p) do
    doll = fn id -> (it = Gear.item(p, id)) && it[:doll] end

    %{
      hair: Data.class(p.cls)[:hair],
      weapon: doll.(p.equip.weapon),
      armor: doll.(p.equip.armor),
      shield: doll.(p.equip.shield),
      wing: wing_look(p),
      pet: Map.get(p, :pet)
    }
  end

  # cánh vẽ bằng code ở client (doll.js): chỉ cần lớp và cấp cánh
  defp wing_look(p) do
    case Gear.item(p, p.equip[:wing]) do
      %{cls: cls, tier: tier} -> %{cls: cls, tier: tier}
      _ -> nil
    end
  end

  # ---------- Nâng cấp đồ (Thợ Rèn) ----------
  # Cấp nâng lưu theo từng món (`upgrades: %{uid => cấp}`): đồ thường được tách thành bản riêng
  # (`Gear.plain/1`) lúc nâng cấp lần đầu hoặc lúc khóa, nên hai thanh kiếm cùng loại có cấp riêng.
  # +1 → +5 dùng quặng (luôn thành công); +6 → +11 dùng ngọc theo bảng `UPGRADE` (có rủi ro).

  def max_upgrade, do: Data.upgrade().max

  @doc "Cấp tính chỉ số: từ `double_from` (+10) mỗi cấp tính gấp đôi (+11 tương đương 13 cấp)."
  def effective_level(l), do: l + max(0, l - Data.upgrade().double_from + 1)

  defp upgrades(p), do: Map.get(p, :upgrades) || %{}

  def upgrade_level(p, id), do: Map.get(upgrades(p), id, 0)

  @doc "Tấn công/phòng thủ cộng thêm: mỗi cấp +8% chỉ số gốc của món đồ (ít nhất +1)."
  def upgrade_bonus(p, id) do
    case {upgrade_level(p, id), Gear.item(p, id)} do
      {0, _} -> 0
      {_, nil} -> 0
      {l, it} -> effective_level(l) * max(1, round((it[:atk] || it[:def] || 0) * @up.bonus_pct))
    end
  end

  @doc """
  Giá nâng món đồ (id đồ thường hoặc thông tin món đồ) từ cấp `level` lên cấp tiếp theo:
  `%{gold, items, rate, fail}` hoặc `nil` nếu đã tối đa.

  - +1 → +5: quặng (đồ dưới cấp 17 dùng Quặng Sắt, từ cấp 17 dùng Mithril), +5 cần thêm Vảy Cổ
    Long; luôn thành công.
  - +6 → +11: một viên ngọc theo bảng `UPGRADE`, tỉ lệ `rate`; thất bại (`fail`) tụt một cấp
    (`"down"`) hoặc vỡ đồ (`"destroy"`). Ngọc và vàng mất cả khi thất bại.
  """
  def upgrade_cost(id, level) when is_binary(id), do: upgrade_cost(Data.item(id), level)

  def upgrade_cost(it, level) do
    n = level + 1
    gold = round(max(it.price, @up.cost_min_price) * @up.cost_pct * n)

    cond do
      level >= max_upgrade() ->
        nil

      step = Data.upgrade_step(n) ->
        %{gold: gold, items: %{step.jewel => 1}, rate: step.rate, fail: step.fail}

      true ->
        ore = if (it[:level] || 1) >= @up.rare_ore_level, do: "ore_rare", else: "ore"
        items = %{ore => n}
        items = if n == @up.scale_step, do: Map.put(items, "dragon_scale", 1), else: items
        %{gold: gold, items: items, rate: 1.0, fail: nil}
    end
  end

  @doc """
  Ép món đang mặc ở ô `slot`. Bước có thể vỡ đồ thì phải gửi `confirm` (client hỏi lại trước).
  Kết quả có `upgrade: %{result: "success" | "down" | "destroy" | "fail", level}`; ép thành công
  từ `announce_from` thì kèm `announce` (Session đưa lên kênh chat hệ thống).
  """
  def upgrade(p, target, confirm \\ false) do
    {id, slot} = forge_target(p, target)
    level = if id, do: upgrade_level(p, id), else: 0
    it = id && Gear.item(p, id)
    cost = it && upgrade_cost(it, level)

    cond do
      !id ->
        {err(
           if target in @equip_slots, do: "Chưa mặc đồ ở chỗ này.", else: "Không ép được món này."
         ), p}

      slot == nil and not Gear.instance?(id) and length(Gear.bag(p)) >= Gear.max_bag() ->
        {err("Túi đồ hiếm đầy (#{Gear.max_bag()} món): món ép riêng cần một chỗ."), p}

      p.battle ->
        {err("Đang trong trận."), p}

      cost == nil ->
        {err("#{it.name} đã nâng cấp tối đa."), p}

      p.gold < cost.gold ->
        {err("Cần #{cost.gold} vàng."), p}

      not Enum.all?(cost.items, fn {m, n} -> Map.get(p.inv, m, 0) >= n end) ->
        missing =
          cost.items
          |> Enum.filter(fn {m, n} -> Map.get(p.inv, m, 0) < n end)
          |> Enum.map_join(", ", fn {m, n} ->
            "#{Data.item(m).name} #{Map.get(p.inv, m, 0)}/#{n}"
          end)

        {err("Thiếu nguyên liệu: #{missing}."), p}

      cost.fail == "destroy" and not confirm ->
        {Map.put(
           err("Ép lên +#{level + 1} thất bại sẽ VỠ #{it.name}. Xác nhận lại để ép."),
           :confirm,
           true
         ), p}

      true ->
        hp_ratio = p.hp / derived(p).maxHp
        {p, uid} = forge_instance(p, id, slot)

        p =
          Enum.reduce(cost.items, %{p | gold: p.gold - cost.gold}, fn {m, n}, p ->
            take_item(p, m, n)
          end)

        {result, p} = roll_upgrade(p, slot, uid, it, level, cost)

        # uid của món vừa ép (đồ thường được tách thành bản riêng): client theo dõi món đang chọn
        {Map.put(result, :uid, uid),
         %{p | hp: min(round(hp_ratio * derived(p).maxHp), derived(p).maxHp)}}
    end
  end

  # Món được ép: ô đang mặc (`"weapon"`...), đồ hiếm trong túi (uid) hoặc đồ thường trong túi (id).
  # Trả về `{id_hoặc_uid, ô_đang_mặc | nil}`; `{nil, nil}` nếu không ép được.
  defp forge_target(p, target) when target in @equip_slots do
    slot = String.to_existing_atom(target)
    {p.equip[slot], slot}
  end

  defp forge_target(p, "#" <> _ = uid) do
    g = Gear.find(p, uid)

    cond do
      g == nil or g[:stored] ->
        {nil, nil}

      slot = Enum.find(@equip_slots, &(p.equip[String.to_existing_atom(&1)] == uid)) ->
        {uid, String.to_existing_atom(slot)}

      true ->
        {uid, nil}
    end
  end

  defp forge_target(p, id) when is_binary(id) do
    it = Data.item(id)
    if it && it.slot in @equip_slots && Map.get(p.inv, id, 0) > 0, do: {id, nil}, else: {nil, nil}
  end

  defp forge_target(_p, _), do: {nil, nil}

  # Đồ thường được ép thì tách thành bản riêng (đang mặc: `ensure_instance`; trong túi: lấy một món ra).
  defp forge_instance(p, _id, slot) when slot != nil, do: ensure_instance(p, slot)

  defp forge_instance(p, "#" <> _ = uid, nil), do: {p, uid}

  defp forge_instance(p, id, nil) do
    g = Gear.plain(id)
    {p |> take_item(id) |> Map.put(:gear, Gear.list(p) ++ [g]), g.uid}
  end

  @doc """
  Ngọc Sinh Mệnh (`RULES.upgrade.life`): thêm một dòng tùy chọn cho món `target` (như `upgrade/3`):
  vũ khí +`per_line` tấn công, giáp / khiên / cánh +`per_line` phòng thủ, tối đa `max_lines`. Tỉ lệ `rate`;
  thất bại mất dòng cuối.
  """
  def life(p, target) do
    l = @up.life
    {id, slot} = forge_target(p, target)
    it = id && Gear.item(p, id)
    lines = if id && Gear.instance?(id), do: Gear.find(p, id)[:opt] || 0, else: 0

    cond do
      !id ->
        {err("Không ép được món này."), p}

      p.battle ->
        {err("Đang trong trận."), p}

      lines >= l.max_lines ->
        {err("#{it.name} đã đủ #{l.max_lines} dòng tùy chọn."), p}

      Map.get(p.inv, l.jewel, 0) < 1 ->
        {err("Cần 1 #{Data.item(l.jewel).name}."), p}

      slot == nil and not Gear.instance?(id) and length(Gear.bag(p)) >= Gear.max_bag() ->
        {err("Túi đồ hiếm đầy (#{Gear.max_bag()} món): món ép riêng cần một chỗ."), p}

      true ->
        hp_ratio = p.hp / derived(p).maxHp
        {p, uid} = forge_instance(p, id, slot)
        p = take_item(p, l.jewel)
        stat = if it.slot == "weapon", do: "tấn công", else: "phòng thủ"

        {r, p} =
          if chance(l.rate) do
            {ok("💚 #{it.name}: thêm dòng +#{l.per_line} #{stat} (#{lines + 1}/#{l.max_lines}).")
             |> Map.put(:life, %{result: "success", lines: lines + 1}),
             Gear.put(p, uid, :opt, lines + 1)}
          else
            n = max(lines - 1, 0)

            text =
              if lines > 0,
                do: "mất một dòng (còn #{n}/#{l.max_lines})",
                else: "không có gì thay đổi"

            {ok("💔 Ép Ngọc Sinh Mệnh thất bại, #{it.name} #{text}.")
             |> Map.put(:life, %{result: "fail", lines: n}), Gear.put(p, uid, :opt, n)}
          end

        {Map.put(r, :uid, uid),
         %{p | hp: min(round(hp_ratio * derived(p).maxHp), derived(p).maxHp)}}
    end
  end

  @doc "Tấn công / phòng thủ cộng thêm từ dòng Ngọc Sinh Mệnh của món `id`."
  def life_bonus(p, id) do
    if Gear.instance?(id), do: ((Gear.find(p, id) || %{})[:opt] || 0) * @up.life.per_line, else: 0
  end

  @doc """
  Vứt đồ: `n` món đồ thường `id`, hoặc món đồ hiếm `id` (uid). Không vứt đồ đang mặc, đang khóa,
  đang cất trong tủ.
  """
  def discard(p, id, n \\ 1)

  def discard(%{battle: b} = p, _id, _n) when b != nil, do: {err("Đang trong trận."), p}

  def discard(p, "#" <> _ = uid, _n) do
    g = Gear.find(p, uid)

    cond do
      g == nil or g[:stored] ->
        {err("Không có món này trong túi."), p}

      Gear.equipped?(p, uid) ->
        {err("Tháo món này ra trước khi vứt."), p}

      g[:locked] ->
        {err("#{Gear.resolve(g).name} đang khóa. Mở khóa trước khi vứt."), p}

      true ->
        {ok("Đã vứt #{Gear.resolve(g).name}."), p |> Gear.remove(uid) |> put_upgrade(uid, 0)}
    end
  end

  def discard(p, id, n) do
    have = Map.get(p.inv, id, 0)

    cond do
      not (is_binary(id) and is_integer(n) and n >= 1) or have == 0 ->
        {err("Không có món này trong túi."), p}

      have < n ->
        {err("Chỉ có #{have} món."), p}

      true ->
        {ok("Đã vứt #{Data.item(id).name} ×#{n}."), take_item(p, id, n)}
    end
  end

  defp roll_upgrade(p, slot, uid, it, level, cost) do
    n = level + 1

    cond do
      cost.rate >= 1 or chance(cost.rate) ->
        p = put_upgrade(p, uid, n)

        text =
          if Data.upgrade_step(n),
            do: "✨ Ép thành công #{it.name} lên +#{n}!",
            else: "Đã nâng #{it.name} lên +#{n}."

        r = ok(text) |> Map.put(:upgrade, %{result: "success", level: n})

        r =
          if n >= Data.upgrade().announce_from,
            do: Map.put(r, :announce, "📢 #{p.name} vừa ép thành công #{it.name} +#{n}!"),
            else: r

        {r, p}

      cost.fail == "down" ->
        p = put_upgrade(p, uid, level - 1)

        {ok("💥 Ép thất bại, #{it.name} tụt về +#{level - 1}.")
         |> Map.put(:upgrade, %{result: "down", level: level - 1}), p}

      cost.fail == "destroy" ->
        p = destroy_equipped(p, slot, uid)

        {ok("💔 Ép thất bại, #{it.name} +#{level} đã vỡ!")
         |> Map.put(:upgrade, %{result: "destroy", level: 0}), p}

      true ->
        {ok("Ép thất bại, #{it.name} giữ nguyên +#{level}.")
         |> Map.put(:upgrade, %{result: "fail", level: level}), p}
    end
  end

  defp put_upgrade(p, uid, 0), do: Map.put(p, :upgrades, Map.delete(upgrades(p), uid))
  defp put_upgrade(p, uid, n), do: Map.put(p, :upgrades, Map.put(upgrades(p), uid, n))

  # Món đang mặc vỡ: bỏ khỏi nhân vật; vũ khí / giáp về đồ khởi đầu (như lúc mới tạo).
  defp destroy_equipped(p, nil, uid), do: p |> Gear.remove(uid) |> put_upgrade(uid, 0)

  defp destroy_equipped(p, slot, uid) do
    p = p |> Gear.remove(uid) |> put_upgrade(uid, 0)
    fallback = %{weapon: "club", armor: "vest"}
    %{p | equip: Map.put(p.equip, slot, fallback[slot])}
  end

  @doc """
  Món đang mặc ở `slot` là đồ thường thì tách thành bản riêng (giữ cấp nâng cũ theo loại nếu có).
  Trả về `{nhân_vật, uid}`.
  """
  def ensure_instance(p, slot) do
    id = p.equip[slot]

    if Gear.instance?(id) do
      {p, id}
    else
      g = Gear.plain(id)
      level = upgrade_level(p, id)

      p = %{
        Map.put(p, :gear, (Map.get(p, :gear) || []) ++ [g])
        | equip: Map.put(p.equip, slot, g.uid)
      }

      p = p |> put_upgrade(id, 0) |> put_upgrade(g.uid, level)
      {p, g.uid}
    end
  end

  @doc """
  Dữ liệu cũ (cấp nâng theo loại đồ thường, `upgrades[id]`): tách mỗi món cùng loại (đang mặc và
  trong túi) thành bản riêng giữ nguyên cấp. Chạy lúc nạp nhân vật.
  """
  def split_upgrades(p) do
    Enum.reduce(upgrades(p), p, fn {id, level}, p ->
      it = not Gear.instance?(id) && Data.item(id)

      if it && it.slot in @equip_slots && level > 0 do
        p =
          Enum.reduce(p.equip, p, fn
            {slot, ^id}, p -> p |> put_upgrade(id, level) |> ensure_instance(slot) |> elem(0)
            _, p -> p
          end)

        copies = for _ <- 1..Map.get(p.inv, id, 0)//1, do: Gear.plain(id)
        p = %{Map.put(p, :gear, (Map.get(p, :gear) || []) ++ copies) | inv: Map.delete(p.inv, id)}
        p = Enum.reduce(copies, p, &put_upgrade(&2, &1.uid, level))
        put_upgrade(p, id, 0)
      else
        p
      end
    end)
  end

  # ---------- Khóa đồ ----------

  @doc """
  Khóa (`on? = true`) / mở khóa món `id`. Đồ khóa không bán, rao chợ, giao dịch, bỏ vào máy ghép
  được. Đồ thường (vũ khí / giáp / khiên / cánh) được tách thành bản riêng để khóa từng món.
  """
  def lock(p, id, on?) when is_binary(id) do
    slot = Enum.find(@equip_slots, &(p.equip[String.to_existing_atom(&1)] == id))
    it = Gear.item(p, id)

    cond do
      it == nil or it.slot not in @equip_slots ->
        {err("Chỉ khóa được vũ khí, giáp, khiên, cánh."), p}

      Gear.instance?(id) ->
        {ok(if on?, do: "🔒 Đã khóa #{it.name}.", else: "Đã mở khóa #{it.name}."),
         Gear.set_locked(p, id, on?)}

      not on? ->
        {err("Món này chưa khóa."), p}

      slot ->
        {p, uid} = ensure_instance(p, String.to_existing_atom(slot))
        {ok("🔒 Đã khóa #{it.name}."), Gear.set_locked(p, uid, true)}

      Map.get(p.inv, id, 0) <= 0 ->
        {err("Không có món này."), p}

      length(Gear.bag(p)) >= Gear.max_bag() ->
        {err("Túi đồ hiếm đầy (#{Gear.max_bag()} món), không tách món này ra để khóa được."), p}

      true ->
        g = Gear.plain(id) |> Map.put(:locked, true)
        p = take_item(p, id)
        {ok("🔒 Đã khóa #{it.name}."), Map.put(p, :gear, (Map.get(p, :gear) || []) ++ [g])}
    end
  end

  def lock(p, _id, _on?), do: {err("Không có món này."), p}

  # ---------- Đồ đạc ----------
  def add_item(p, id, n \\ 1), do: %{p | inv: Map.update(p.inv, id, n, &(&1 + n))}

  defp take_item(p, id, n \\ 1) do
    inv =
      case Map.get(p.inv, id, 0) do
        have when have > n -> Map.put(p.inv, id, have - n)
        _ -> Map.delete(p.inv, id)
      end

    %{p | inv: inv}
  end

  defp count_ok?(n), do: is_integer(n) and n >= 1 and n <= @max_batch

  def buy(p, id, n \\ 1) do
    it = Data.item(id)

    cond do
      # Chỉ bán những món có trong cửa hàng (đồ khởi đầu giá 0 và đồ rơi từ trùm thì không).
      it == nil || it[:drop] || id not in Data.shop() ->
        {err("Không bán món này."), p}

      not count_ok?(n) ->
        {err("Số lượng không hợp lệ."), p}

      it[:level] && p.level < it.level ->
        {err("Cần cấp #{it.level}."), p}

      p.gold < price(p, id) * n ->
        {err("Không đủ vàng."), p}

      true ->
        {ok("Đã mua #{if n > 1, do: "#{n} ", else: ""}#{it.name}."),
         %{p | gold: p.gold - price(p, id) * n} |> add_item(id, n)}
    end
  end

  @doc """
  Giá mua ở cửa hàng cho nhân vật `p`. Bình máu / mana hồi theo % nên giá tăng theo cấp (Phase 12):
  `giá × (1 + potion_price_per_level × (cấp − 1))`; giá bán lại vẫn theo giá gốc.
  """
  def price(p, id) do
    it = Data.item(id)

    if it.slot == "potion",
      do: round(it.price * (1 + @shop.potion_price_per_level * (p.level - 1))),
      else: it.price
  end

  def sell_price(id) do
    price = Data.item(id).price
    floor(if(price == 0, do: @shop.unpriced_value, else: price) * @shop.sell_ratio)
  end

  def sell(p, "#" <> _ = uid) do
    case Gear.find(p, uid) do
      nil ->
        {err("Không có món này."), p}

      g ->
        cond do
          Gear.equipped?(p, uid) ->
            {err("Đang mặc món này."), p}

          g[:stored] ->
            {err("Món này đang cất trong tủ."), p}

          g[:locked] ->
            {err("#{Gear.resolve(g).name} đang khóa. Mở khóa trước khi bán."), p}

          true ->
            it = Gear.resolve(g)
            p = %{Gear.remove(p, uid) | gold: p.gold + it.sell}
            p = Map.put(p, :upgrades, Map.delete(upgrades(p), uid))
            {ok("Đã bán #{it.name} được #{it.sell} vàng."), p}
        end
    end
  end

  def sell(p, id) do
    if Map.get(p.inv, id, 0) > 0 and Data.item(id) do
      g = sell_price(id)
      p = %{take_item(p, id) | gold: p.gold + g}

      # bán hết món đã nâng cấp (không còn trong túi, không đang mặc) thì mất cấp nâng
      gone = not Map.has_key?(p.inv, id) and id not in Map.values(p.equip)
      p = if gone, do: Map.put(p, :upgrades, Map.delete(upgrades(p), id)), else: p
      {ok("Đã bán #{Data.item(id).name} được #{g} vàng."), p}
    else
      {err("Không có món này."), p}
    end
  end

  def equip(p, id) do
    it = Gear.item(p, id)
    gear? = Gear.instance?(id)

    owned =
      if gear?,
        do: it != nil and not Gear.equipped?(p, id) and not Gear.stored?(p, id),
        else: Map.get(p.inv, id, 0) > 0

    cond do
      it == nil or not owned or it.slot not in @equip_slots ->
        {err("Không trang bị được."), p}

      it[:level] && p.level < it.level ->
        {err("Cần cấp #{it.level}."), p}

      it[:cls] && it.cls != p.cls ->
        {err("#{it.name} dành cho #{Data.class(it.cls).name}."), p}

      true ->
        slot = String.to_existing_atom(it.slot)
        hp_ratio = p.hp / derived(p).maxHp
        old = p.equip[slot]

        # đồ ngẫu nhiên luôn nằm trong `gear`, chỉ đồ thường mới lấy ra/cất vào `inv`
        p = if gear?, do: p, else: take_item(p, id)
        p = if old && not Gear.instance?(old), do: add_item(p, old), else: p
        p = %{p | equip: Map.put(p.equip, slot, id)}
        {ok("Đã trang bị #{it.name}."), %{p | hp: round(hp_ratio * derived(p).maxHp)}}
    end
  end

  def unequip(p, slot) when slot in ~w(shield wing) do
    key = String.to_existing_atom(slot)

    case p.equip[key] do
      nil ->
        {err("Không tháo được."), p}

      old ->
        p = if Gear.instance?(old), do: p, else: add_item(p, old)

        {ok(if(key == :wing, do: "Đã tháo cánh.", else: "Đã tháo khiên.")),
         %{p | equip: Map.put(p.equip, key, nil)}}
    end
  end

  def unequip(p, _slot), do: {err("Không tháo được."), p}

  def use_potion(p, id) do
    it = Data.item(id)
    mana? = it != nil and it[:mana_pct] != nil

    cond do
      p.battle ->
        {err("Dùng nút Uống máu / Uống mana trong trận."), p}

      it == nil or Map.get(p.inv, id, 0) <= 0 or it.slot != "potion" ->
        {err("Không có bình này."), p}

      mana? and mp(p) >= derived(p).maxMp ->
        {err("MP đang đầy."), p}

      not mana? and p.hp >= derived(p).maxHp ->
        {err("Máu đang đầy."), p}

      true ->
        {p, h} = drink(p, id)
        {ok(if(mana?, do: "Hồi #{h} MP.", else: "Hồi #{h} máu.")), p}
    end
  end

  defp full?(p), do: (d = derived(p)) && p.hp >= d.maxHp and mp(p) >= d.maxMp

  def rest_cost(p),
    do: if(full?(p), do: 0, else: max(0, p.level * @char.rest_per_level - @char.rest_per_level))

  # nghỉ trọ hồi đầy cả máu và MP
  def rest(p) do
    c = rest_cost(p)
    d = derived(p)

    cond do
      p.battle ->
        {err("Đang trong trận."), p}

      full?(p) ->
        {err("Máu và MP đang đầy."), p}

      p.gold < c ->
        {err("Cần #{c} vàng."), p}

      c > 0 ->
        {ok("Nghỉ trọ hết #{c} vàng. Máu và MP đã đầy."),
         Map.merge(p, %{gold: p.gold - c, hp: d.maxHp, mp: d.maxMp})}

      true ->
        {ok("Nghỉ ngơi miễn phí. Máu và MP đã đầy."), Map.merge(p, %{hp: d.maxHp, mp: d.maxMp})}
    end
  end

  # ---------- Chuyển sinh ----------

  def max_rebirths, do: @max_rebirths
  def rebirth_points, do: @rebirth_points

  @doc """
  Chuyển sinh (ở cấp tối đa): về cấp 1 với chỉ số gốc của lớp, nhận #{@rebirth_points} điểm
  tiềm năng cộng thêm cho mỗi lần đã chuyển sinh. Giữ vàng, đồ, trùm đã hạ, nhiệm vụ,
  thành tựu.
  """
  def rebirth(p) do
    n = Map.get(p, :rebirths, 0)

    cond do
      p.battle ->
        {err("Đang trong trận."), p}

      p.level < @max_level ->
        {err("Cần đạt cấp #{@max_level} mới chuyển sinh được."), p}

      n >= @max_rebirths ->
        {err("Đã chuyển sinh tối đa #{@max_rebirths} lần."), p}

      true ->
        n = n + 1
        p = %{p | level: 1, xp: 0, stats: Data.class(p.cls).base, points: n * @rebirth_points}
        p = Map.put(p, :rebirths, n)
        d = derived(p)

        {ok("🔄 Chuyển sinh lần #{n}! Trở về cấp 1 với #{p.points} điểm tiềm năng cộng thêm."),
         Map.merge(p, %{hp: d.maxHp, mp: d.maxMp})}
    end
  end

  def allocate(p, stat, n \\ 1) do
    stat = Enum.find(@stats, &(Atom.to_string(&1) == stat))

    cond do
      stat == nil ->
        {err("Chỉ số không hợp lệ."), p}

      not count_ok?(n) ->
        {err("Số điểm không hợp lệ."), p}

      p.points < n ->
        {err("Hết điểm tiềm năng."), p}

      true ->
        before = derived(p)
        p = %{p | stats: Map.update!(p.stats, stat, &(&1 + n)), points: p.points - n}
        # tăng thể lực / năng lượng thì cộng luôn máu / MP
        after_ = derived(p)

        {ok(),
         Map.merge(p, %{
           hp: p.hp + after_.maxHp - before.maxHp,
           mp: mp(p) + after_.maxMp - before.maxMp
         })}
    end
  end
end

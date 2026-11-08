defmodule HacLong.Game.Engine do
  @moduledoc """
  Luật chơi: chỉ số nhân vật, sinh quái, chiến đấu, lên cấp, mua bán.

  Mọi hàm đều thuần: nhận trạng thái nhân vật (map) và trả về `{kết_quả, nhân_vật_mới}`.
  Trạng thái được gửi nguyên cho client (JSON) để vẽ giao diện, nên tên khóa
  theo kiểu JS (`maxHp`, `skillCd`...). Số ngẫu nhiên lấy qua `HacLong.Game.Rng`
  để test cố định được kết quả.
  """

  alias HacLong.Game.{
    BattleText,
    Bestiary,
    Blessing,
    Crafting,
    Elements,
    Data,
    Events,
    Gear,
    Mastery,
    Pets,
    Rng
  }

  @save_version 1
  # số luật chơi: `RULES` trong `priv/game_data/rules.json`
  @rules Data.rules()
  @boss_rw @rules.boss_rewards
  @boss_weights Enum.map(@rules.boss_rewards.first_kill_weights, &List.to_tuple/1)
  @char @rules.character
  @combat @rules.combat
  # ép cánh theo bậc (RULES.wing_upgrade)
  @wing_up @rules.wing_upgrade
  @effects @rules.skill_effects
  @mon @rules.monster
  @loot @rules.loot
  @max_level @char.max_level
  # DECISIONS "Cân bằng đánh người"
  @pvp @rules.pvp
  @arena_first @rules.arena[:first_strike_mult] || 1
  # cầm 2 vũ khí 1 tay (B-42)
  @dual @rules.dual_wield
  @up @rules.upgrade
  @shop @rules.shop
  # Phase 15b: đồ ngẫu nhiên rơi từ quái hợp lớp người hạ (`RULES.loot.gear_own_class`)
  @loot_own_class @rules.loot[:gear_own_class] == true
  @log_limit 60
  # bình máu / bình mana: hồi số cố định `heal` máu / `mana` MP (DECISIONS "Bình máu / mana hồi số")
  @potions ~w(potion_s potion_m potion_l)
  @manas ~w(mana_s mana_m mana_l)
  # Sức mạnh, Nhanh nhẹn, Thể lực, Năng lượng (như MU)
  @stats ~w(str agi vit ene)a
  # mỗi lượt của người chơi hồi `mp_regen` × MP tối đa + `mp_regen_ene` × Năng lượng (Phase 12, 12-A)
  @mp_regen @combat.mp_regen
  @mp_regen_ene @combat.mp_regen_ene
  @skill_mp_per_level @combat.skill_mp_per_level
  @max_batch 99
  # vũ khí, giáp, khiên, cánh; Phase 15b thêm mũ, quần, găng, giày, 2 nhẫn, dây chuyền (đồ Item.txt)
  @equip_slots ~w(weapon armor shield wing helm pants gloves boots ring1 ring2 pendant)
  # loại đồ mặc được (`slot` của món): như ô, nhưng hai ô nhẫn chung một loại "ring"
  @item_slots (@equip_slots -- ~w(ring1 ring2)) ++ ["ring"]
  # ô phòng thủ (cộng `def`) và ô tháo ra được: mọi ô (anh chốt, DECISIONS B-11; tay không thì tấn công
  # chỉ tính theo chỉ số, không giáp thì phòng thủ chỉ tính theo chỉ số)
  @def_slots ~w(armor shield wing helm pants gloves boots ring1 ring2)a
  @removable @equip_slots
  # Phase 15c: thưởng đủ bộ giáp, dòng Excellent (`rules.json`)
  @set_bonus @rules[:set_bonus] || %{min_tier: 99, def_pct: 0, atk_pct: 0, hp_per_tier: 0}
  @max_rebirths @char.max_rebirths
  @rebirth_points @char.rebirth_points
  # kỹ năng quái theo hệ (DECISIONS "Quái dùng kỹ năng theo hệ")
  @mskills @rules.monster_skills
  @mskills_by Map.new(@mskills.by_element, fn {k, v} -> {Atom.to_string(k), v} end)

  def equip_slots, do: @equip_slots
  @doc "Loại đồ mặc được (`slot` của món): như ô trang bị, hai ô nhẫn chung loại \"ring\"."
  def item_slots, do: @item_slots
  @doc "Loại đồ có đồ ngẫu nhiên (chỉ số cộng thêm, rơi từ quái): mọi loại trừ cánh."
  def gear_slots, do: @item_slots -- ["wing"]

  @doc """
  Ô mặc món `it` lên (atom): như `it.slot`, riêng nhẫn vào ô nhẫn còn trống (`ring1` rồi `ring2`; đủ cả hai thì
  thay `ring1`).
  """
  def equip_slot(p, %{slot: "ring"}) do
    cond do
      p.equip[:ring1] == nil -> :ring1
      p.equip[:ring2] == nil -> :ring2
      true -> :ring1
    end
  end

  def equip_slot(_p, it), do: String.to_existing_atom(it.slot)

  @doc "Ô đang mặc món `id` (atom) hoặc nil."
  def worn_slot(p, id), do: Enum.find_value(p.equip, fn {slot, v} -> if v == id, do: slot end)
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
          equip: Map.merge(empty_equip(), Data.starters(cls)),
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
          drink: nil,
          blessing: nil,
          skill_set: nil,
          # thông thạo kỹ năng (`HacLong.Game.Mastery`): nhân vật mới luyện từ cấp 1
          skill_mastery: %{},
          auto_cfg: nil,
          secret: nil,
          crafting: %{cook: 0, smith: 0},
          festival: 0,
          storage: %{inv: %{}, extra: 0, gold: 0},
          visited: [],
          fish_caught: 0,
          long_khi: 0,
          achievements: [],
          title: nil,
          bosses: [],
          kills: 0,
          deaths: 0,
          victory: false,
          battle: nil,
          hp: 0
        }

        # đồ khởi đầu đang mặc cũng là món riêng như mọi trang bị
        p = instance_gear(p)
        d = derived(p)
        {:ok, %{p | hp: d.maxHp, mp: d.maxMp}}
    end
  end

  @stat_names %{str: "Sức mạnh", agi: "Nhanh nhẹn", vit: "Thể lực", ene: "Năng lượng"}

  @doc "Mọi ô trang bị đều trống (`%{weapon: nil, …}`)."
  def empty_equip, do: Map.new(@equip_slots, &{String.to_atom(&1), nil})

  @doc """
  Lớp `cls` dùng được món `it` không: cánh theo `cls` (một lớp), đồ Item.txt theo `classes`
  (danh sách). Đồ không ghi gì thì lớp nào cũng dùng được.
  """
  def class_ok?(it, cls),
    do: it[:cls] in [nil, cls] and (it[:classes] in [nil, []] or cls in it.classes)

  @doc """
  Kiểm tra mặc được món `it` (đã `Gear.item/2`): cấp, lớp, yêu cầu chỉ số (`req`, so với chỉ số gốc
  đã cộng điểm, không tính đồ). `:ok` hoặc `{:error, lời_báo}`.
  """
  def can_wear(p, it) do
    short = Enum.find(it[:req] || %{}, fn {k, v} -> Map.get(p.stats, k, 0) < v end)

    cond do
      it[:level] && p.level < it.level -> {:error, "Cần cấp #{it.level}."}
      not class_ok?(it, p.cls) -> {:error, "#{it.name} không dành cho #{Data.class(p.cls).name}."}
      short -> {:error, "#{it.name} cần #{@stat_names[elem(short, 0)]} #{elem(short, 1)}."}
      true -> :ok
    end
  end

  def can_wear?(p, it), do: can_wear(p, it) == :ok

  @doc """
  Ô đang mặc món chưa đủ điều kiện (`can_wear/2`: cấp, lớp, yêu cầu chỉ số), vd vừa chuyển sinh về cấp 1: món đó
  vẫn mặc trên người nhưng không có tác dụng (DECISIONS "Đồ quá cấp sau chuyển sinh không có tác dụng").
  """
  def inactive_slots(p) do
    for {slot, id} <- p.equip, id, it = Gear.item(p, id), not can_wear?(p, it), do: slot
  end

  @doc "Nhân vật chỉ tính đồ có tác dụng (bỏ món chưa đủ điều kiện khỏi `equip`), để cộng chỉ số / dòng / bộ."
  def effective(p) do
    case inactive_slots(p) do
      [] -> p
      off -> %{p | equip: Map.new(p.equip, fn {k, v} -> {k, if(k in off, do: nil, else: v)} end)}
    end
  end

  @doc """
  Chỉ số dẫn xuất. Công thức theo lớp ở `CLASSES[lớp].derived` (`priv/game_data/classes.json`): mỗi chỉ số là
  tổng `hệ_số × giá_trị` với giá trị là một chỉ số gốc (`str`, `agi`, `vit`, `ene`), `level` hoặc
  `base` (= 1). Chí mạng và né theo Nhanh nhẹn, như nhau cho mọi lớp.
  """
  def derived(p) do
    p = effective(p)
    s = p.stats
    f = Data.class(p.cls).derived
    w = Gear.item(p, p.equip.weapon)
    wg = Gear.item(p, p.equip[:wing])
    pd = Gear.item(p, p.equip[:pendant])
    # Phase 15c: máu cộng từ đồ (nhẫn), thưởng đủ bộ, dòng Excellent
    gear_hp =
      p.equip
      |> Map.values()
      |> Enum.map(fn
        nil -> 0
        id -> ((Gear.item(p, id) || %{})[:hp] || 0) + upgrade_hp(p, id)
      end)
      |> Enum.sum()

    sb = set_bonus(p)
    anc = ancient_bonus(p)
    exc = Gear.exc_stats(p)
    ls = Gear.luck_skill_stats(p)
    wo = Gear.wing_stats(p)

    up = fn id -> if id, do: upgrade_bonus(p, id) + life_bonus(p, id), else: 0 end

    # vũ khí thứ hai ở tay trái (B-42): công + ép + dòng cộng thêm × `dual_wield.mult`
    lw = left_weapon(p)
    dual = if lw, do: @dual.mult * (lw.atk + up.(p.equip.shield)), else: 0

    lin = fn terms ->
      Enum.reduce(terms, 0, fn
        {:level, k}, acc -> acc + k * p.level
        {:base, k}, acc -> acc + k
        {stat, k}, acc -> acc + k * Map.get(s, stat, 0)
      end)
    end

    # thú cưng đang dắt theo và món đang ăn cộng phần trăm
    pet = fn key ->
      1 + Pets.bonus(p, key) + Crafting.food_bonus(p, key) + Blessing.bonus(p, key)
    end

    %{
      maxHp:
        round((lin.(f.hp) + gear_hp + sb.hp + anc.hp + wo.hp) * pet.(:hp) * (1 + exc.hp_pct)) +
          Pets.flat(p, :hp),
      maxMp: round((lin.(f.mp) + wo.mp) * (1 + exc.mp_pct)) + Pets.flat(p, :mp),
      atk:
        round(
          (lin.(f.atk) + exc.atk_lvl * p.level + if(w, do: w.atk, else: 0) + up.(p.equip.weapon) +
             dual + if(pd, do: pd[:atk] || 0, else: 0) + up.(p.equip[:pendant])) * pet.(:atk) *
            (1 + exc.atk_pct + sb.atk_pct + anc.atk_pct)
        ),
      def:
        round(
          (lin.(f.def) +
             Enum.sum(
               for slot <- @def_slots, id = p.equip[slot], !(slot == :shield && lw) do
                 Map.get(Gear.item(p, id) || %{}, :def, 0) + up.(id)
               end
             )) * pet.(:def) * (1 + sb.def_pct + anc.def_pct)
        ),
      crit:
        clamp(@combat.crit.base + s.agi * @combat.crit.per_agi, 0, @combat.crit.max) + exc.crit +
          ls.crit + Pets.bonus(p, :crit),
      critMult:
        min(@combat.crit_mult.max, @combat.crit_mult.base + s.agi * @combat.crit_mult.per_agi),
      # attack rate: tỉ lệ đòn thường trúng quái (`hit_chance/2`)
      ar: (p.level * @combat.hit.level + s.agi * @combat.hit.agi) * (1 + exc.ar_pct),
      # B-28: trần `max` theo Nhanh nhẹn, rồi nhân Excellent def_rate, chặn `max_total`
      dodge:
        min(
          clamp(@combat.dodge.base + s.agi * @combat.dodge.per_agi, 0, @combat.dodge.max) *
            (1 + exc.def_rate),
          @combat.dodge.max_total
        ),
      # cánh: phần sát thương gây thêm / giảm khi nhận (mỗi cấp nâng +2 %)
      wingDmg: wing_pct(p, wg, :dmg),
      wingAbsorb: wing_pct(p, wg, :absorb),
      # Excellent: giảm sát thương nhận (cộng dồn các món, tối đa `excellent.max_dmg_red`)
      excAbsorb: exc.dmg_red,
      # Excellent (B-16): phản lại phần sát thương quái gây ra
      excReflect: exc.reflect,
      # Kỹ năng (Phase 15d): sát thương chiêu cộng thêm
      skillDmg: ls.skill_dmg,
      # dòng cánh (Phase 15e): bỏ qua phần phòng thủ của đối thủ
      ignoreDef: wo.ignore_def,
      # kháng hệ từ nhẫn / dây chuyền (DECISIONS "Quái dùng kỹ năng theo hệ"): %{hệ => tỉ lệ}
      resist: resists(p)
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

  @doc """
  Phase 15c: thưởng đủ bộ giáp (`RULES.set_bonus`). Đếm món đang mặc theo bộ (`set`); bộ nhiều món nhất được xét,
  đủ số món của bộ cho lớp này (`Data.set_size/2`; Đấu Sĩ không mũ nên 4) thì có thưởng:
  `def_pct` phòng thủ, `atk_pct` tấn công, `hp_per_tier × bậc` máu. Bộ dưới bậc `min_tier` (bộ khởi đầu) không tính.
  Trả `%{name, tier, have, need, active, def_pct, atk_pct, hp}` (không có bộ nào: `name` nil, thưởng 0).
  """
  def set_bonus(p) do
    worn =
      for {_slot, id} <- p.equip, id, it = Gear.item(p, id), it[:set], do: {it.set, it.tier}

    zero = %{name: nil, tier: 0, have: 0, need: 0, active: false, def_pct: 0, atk_pct: 0, hp: 0}

    case worn |> Enum.frequencies() |> Enum.max_by(&elem(&1, 1), fn -> nil end) do
      nil ->
        zero

      {{name, tier}, have} ->
        need = Data.set_size(name, p.cls)
        on = need > 0 and have >= need and tier >= @set_bonus.min_tier

        %{
          zero
          | name: name,
            tier: tier,
            have: have,
            need: need,
            active: on,
            def_pct: if(on, do: @set_bonus.def_pct, else: 0),
            atk_pct: if(on, do: @set_bonus.atk_pct, else: 0),
            hp: if(on, do: @set_bonus.hp_per_tier * tier, else: 0)
        }
    end
  end

  @anc Data.rules().ancient

  @doc """
  Thưởng Bộ Thần (Phase 15g, `RULES.ancient.bonus`): đếm món Thần **cùng bộ** đang mặc (bộ có nhiều món Thần nhất),
  cộng dồn mọi mức `count` đã đạt (`"full"` = đủ bộ theo `Data.set_size/2`).
  `%{name, have, need, atk_pct, def_pct, hp}`.
  """
  def ancient_bonus(p) do
    zero = %{name: nil, have: 0, need: 0, atk_pct: 0, def_pct: 0, hp: 0}

    worn =
      for {_slot, id} <- p.equip, id, it = Gear.item(p, id), it[:anc] && it[:set], do: it.set

    case worn |> Enum.frequencies() |> Enum.max_by(&elem(&1, 1), fn -> nil end) do
      nil ->
        zero

      {name, have} ->
        need = Data.set_size(name, p.cls)

        Enum.reduce(@anc.bonus, %{zero | name: name, have: have, need: need}, fn b, acc ->
          reached = if b.count == "full", do: need > 0 and have >= need, else: have >= b.count

          if reached,
            do: %{
              acc
              | atk_pct: acc.atk_pct + b.atk_pct,
                def_pct: acc.def_pct + b.def_pct,
                hp: acc.hp + b.hp
            },
            else: acc
        end)
    end
  end

  # Excellent: hồi máu / MP khi hạ quái
  defp exc_on_kill(p, %{heal_kill: 0, mp_kill: 0}), do: p

  defp exc_on_kill(p, exc) do
    d = derived(p)

    %{
      p
      | hp: min(d.maxHp, p.hp + round(d.maxHp * exc.heal_kill)),
        mp: min(d.maxMp, (Map.get(p, :mp) || 0) + round(d.maxMp * exc.mp_kill))
    }
  end

  defp wing_pct(_p, nil, _key), do: 0

  defp wing_pct(p, wg, key) do
    v = wg[key] + wing_up(key, wg[:tier] || 1, upgrade_level(p, wg.uid))
    v = if key == :absorb, do: min(v, @wing_up.absorb.max), else: v
    Float.round(v, 3)
  end

  @doc """
  % sát thương (`:dmg`) / hấp thụ (`:absorb`) cộng thêm khi ép cánh bậc `tier` lên +`lv` (`RULES.wing_upgrade`):
  mỗi cấp tới +9 một ít, +10 và +11 nhảy lớn. Hấp thụ tổng (gốc + ép) có trần ở `wing_pct/3`.
  """
  def wing_up(key, tier, lv) do
    t = @wing_up[key]
    i = min(max(tier, 1), length(t.per_level)) - 1

    Enum.at(t.per_level, i) * min(lv, 9) + if(lv >= 10, do: Enum.at(t.jump10, i), else: 0) +
      if(lv >= 11, do: Enum.at(t.jump11, i), else: 0)
  end

  @doc """
  Các chỉ số tính ra từ trạng thái, gửi kèm cho client để hiển thị
  (client không có công thức nào).
  """
  def view(p) do
    %{
      derived: derived(p),
      xpToNext: xp_need(p),
      # chúa tể cần hạ trước lần chuyển sinh kế (nil nếu không cần / đã hạ)
      rebirthNeed: with(%{} = n <- rebirth_need(p), do: Map.put(n, :map, lord_map_name(n.id))),
      # điểm tiềm năng nhận được ở lần chuyển sinh kế (giảm sau mốc tối đa)
      rebirthPoints: rebirth_bonus((Map.get(p, :rebirths) || 0) + 1),
      restCost: rest_cost(p),
      # Phase 13: phần cộng thêm cho tab Nhân vật: % từ thú cưng + món ăn (đồ không cộng chỉ số, B-15)
      extra: %{
        hp: Pets.bonus(p, :hp) + Crafting.food_bonus(p, :hp) + Blessing.bonus(p, :hp),
        atk: Pets.bonus(p, :atk) + Crafting.food_bonus(p, :atk) + Blessing.bonus(p, :atk),
        def: Pets.bonus(p, :def) + Crafting.food_bonus(p, :def) + Blessing.bonus(p, :def),
        # thú cưng: máu / MP cộng số
        hpFlat: Pets.flat(p, :hp),
        mpFlat: Pets.flat(p, :mp)
      },
      unlocked: Enum.map(0..(Data.zone_count() - 1), &zone_unlocked?(p, &1)),
      # Phase 15c: thưởng đủ bộ giáp, tổng dòng Excellent đang có
      setBonus: set_bonus(effective(p)),
      # ô đồ chưa đủ điều kiện (vd vừa chuyển sinh): vẫn mặc nhưng không có tác dụng
      inactive: inactive_slots(p),
      # Quảng Trường Quỷ (Phase 18 M1): giờ mở, giá vé, điểm cao nhất hôm nay, đã vào đợt này chưa
      ds: HacLong.Game.DevilSquare.view(p),
      # Lâu Đài Máu (Phase 18 M2)
      bc: HacLong.Game.BloodCastle.view(p),
      # Hỗn Chiến Thành (B-19)
      cc: HacLong.ChaosCastle.view(p),
      # Kalima (B-21)
      kal: HacLong.Game.Kalima.view(p),
      # Công Thành Chiến (B-22)
      cs: HacLong.CastleSiege.view(p),
      ancient: ancient_bonus(effective(p)),
      exc: Gear.exc_stats(effective(p)),
      look: look(p),
      # Phase 3: kỹ năng mang vào trận (id, theo thứ tự) và mọi kỹ năng đã mở
      skillSet: Enum.map(skills(p), & &1.id),
      # thông thạo kỹ năng: cấp, điểm, mốc, cần đột phá; MP và hồi chiêu ở cấp hiện tại
      mastery:
        Map.new(Mastery.view(p), fn {id, v} ->
          k = Enum.find(available_skills(p), &(&1.id == id))

          {id,
           Map.merge(v, %{
             mp: skill_mp(p, k),
             cd: skill_cd(p, k),
             pct: round(Mastery.mult(v.lv) * 100)
           })}
        end),
      skillsOpen: Enum.map(available_skills(p), & &1.id),
      # cài đặt tự đánh đã lưu (lần bật gần nhất), để bảng cài đặt mở lại đúng như cũ
      autoCfg: Map.get(p, :auto_cfg),
      # Phase 2: Đài Phúc Lành đang có (phúc lành + điểm hồi sinh)
      blessing: Blessing.view(p),
      # thú cưng đã có (cấp, cắn, kỹ năng, giá cho ăn) và loài thuần được / đang hạ dở
      pets: Pets.view(p),
      tameable: Pets.tameable(p),
      taming: Pets.taming(p),
      # cộng thêm của đồ đã nâng cấp (để client so sánh đồ) và giá nâng cấp đồ đang mặc
      bonus:
        (Map.keys(upgrades(p)) ++ for(g <- Gear.list(p), g[:opt], do: g.uid))
        |> Map.new(&{&1, upgrade_bonus(p, &1) + life_bonus(p, &1)}),
      # B-28: máu cộng thêm khi ép nhẫn máu
      bonusHp:
        for(id <- Map.keys(upgrades(p)), (v = upgrade_hp(p, id)) > 0, into: %{}, do: {id, v}),
      # giá ép từng món trong túi (đồ hiếm chưa cất, đồ thường mặc được), cho nút "Ép" trong tooltip
      forgeBag:
        for id <- Enum.map(Gear.bag(p), & &1.uid) ++ Map.keys(p.inv),
            (it = Gear.item(p, id)) && it.slot in @item_slots,
            into: %{} do
          {id, %{level: upgrade_level(p, id), cost: upgrade_cost(it, upgrade_level(p, id))}}
        end,
      storage: HacLong.Game.Storage.view(p),
      forge:
        for {slot, id} <- p.equip, id != nil, it = Gear.item(p, id), into: %{} do
          {slot,
           %{
             id: id,
             level: upgrade_level(p, id),
             cost: upgrade_cost(it, upgrade_level(p, id))
           }}
        end,
      # đồ ngẫu nhiên (cả món đang mặc) đã tính tên, chỉ số, giá bán
      # chỉ đồ của nhân vật (túi + đang mặc); đồ trong thùng đồ chung ở `storage.items`
      gear: Map.new(Map.get(p, :gear) || [], &{&1.uid, Gear.resolve(&1)})
    }
  end

  def xp_to_next(lv, rebirths \\ 0),
    do:
      round(
        (@rules.xp.coef * :math.pow(lv, @rules.xp.exp) + @rules.xp.base) *
          (1 + @char.rebirth_xp_pct * rebirths)
      )

  @doc "Kinh nghiệm cần để nhân vật `p` lên cấp kế (tính cả số lần đã chuyển sinh)."
  def xp_need(p), do: xp_to_next(p.level, min(Map.get(p, :rebirths) || 0, @max_rebirths))

  @doc """
  Vùng `zi` vào được / đánh được chưa: **đủ cấp** (cấp nhân vật ≥ `zone_level/1`, cấp quái thấp nhất
  của vùng). Không còn khóa bằng trùm vùng trước (2026-10-10, `DECISIONS.md` B-4); trùm là thử thách
  có thưởng (`first_boss_kill/3`, thưởng mỗi ngày `boss_daily/3`).
  """
  def zone_unlocked?(_p, 0), do: true

  def zone_unlocked?(p, zi) do
    case zone_level(zi) do
      nil -> false
      lv -> p.level >= lv
    end
  end

  @doc "Cấp quái thấp nhất của vùng `zi` (nil nếu không có vùng)."
  def zone_level(zi) do
    case Data.zone(zi) do
      nil -> nil
      z -> z.monsters |> Enum.map(& &1.level) |> Enum.min()
    end
  end

  # ---------- Quái ----------
  def make_monster(spec, boss?) do
    l = spec.level

    # Phase 6 (B-30): quái vùng chuyển sinh tính chỉ số ở `stat_level` (cấp hiện `level` chỉ cho vàng / EXP)
    sl = Map.get(spec, :stat_level) || l
    m = Map.get(spec, :mult, 1)
    [gs_lo, gs_hi] = @mon.gold_spread
    bm = if boss?, do: @mon.boss.hp, else: 1
    # trùm: công / thủ nhân thêm (`RULES.monster.boss.atk` / `def`)
    ba = if boss?, do: @mon.boss.atk, else: 1
    bd = if boss?, do: @mon.boss.def, else: 1
    # thưởng nhân thêm (quái vàng Golden Invasion), không đổi sức mạnh
    rw = Map.get(spec, :reward_mult, 1)

    element = Map.get(spec, :element) || Elements.for_level(l)
    tier = mskill_tier(spec, boss?, l)

    %{
      id: spec.id,
      name: spec.name,
      level: l,
      boss: boss?,
      final: Map.get(spec, :final, false),
      special: Map.get(spec, :special) || lord_special(tier, element),
      # kỹ năng theo hệ (DECISIONS "Quái dùng kỹ năng theo hệ"): `mskills` (khóa riêng, `skills` là của bản sao người)
      mskills: mskills(tier, element),
      mskill_chance: if(tier, do: @mskills.tiers[tier].chance, else: 0),
      on_hit: Map.get(spec, :on_hit),
      night: Map.get(spec, :night, false),
      golden: Map.get(spec, :golden, false),
      raid: Map.get(spec, :raid),
      jewel_chance: Map.get(spec, :jewel_chance),
      maxHp: round((@mon.hp.base + sl * @mon.hp.level + sl * sl * @mon.hp.level_sq) * m * bm),
      # vùng chuyển sinh: công nhân hệ số riêng `atk_mult` (nhẹ hơn máu), không có thì như máu
      atk: round((@mon.atk.base + sl * @mon.atk.level) * Map.get(spec, :atk_mult, m) * ba),
      def: round((@mon.def.base + sl * @mon.def.level) * m * bd),
      # Phase 6: vùng chuyển sinh rơi đồ quý hơn (`Gear.rich/2`)
      rich: Map.get(spec, :rich, 0),
      crit: @mon.crit,
      # Phase 3 (B-29): nguyên tố riêng của quái, không có thì theo cấp
      element: element,
      # B-28: quái không có né (đòn thường trúng theo AR / DR, `hit_chance/2`); né chỉ có ở bản sao người chơi
      dodge: 0,
      # vùng chuyển sinh: kinh nghiệm ở `stat_level` × `xp_mult` (cấp hiện 52–150 cho quá nhiều), không có thì theo cấp hiện × mult
      xp:
        round(
          if(Map.has_key?(spec, :xp_mult), do: base_xp(sl) * spec.xp_mult, else: base_xp(l) * m) *
            rw * if(boss?, do: @mon.boss.xp, else: 1)
        ),
      gold:
        round(base_gold(l) * m * rw * rand(gs_lo, gs_hi) * if(boss?, do: @mon.boss.gold, else: 1))
    }
  end

  @ev_scale @rules.event_scale

  # ---------- Kỹ năng quái theo hệ (RULES.monster_skills) ----------

  @doc "Bậc kỹ năng của quái: :lord | :boss | :elite | :normal | nil (quái thường dưới `min_level`)."
  def mskill_tier(spec, boss?, level) do
    cond do
      spec[:lord] == true -> :lord
      boss? -> :boss
      spec[:elite] == true or spec[:night] == true or spec[:golden] == true -> :elite
      level >= @mskills.min_level -> :normal
      true -> nil
    end
  end

  @doc "Kỹ năng quái bậc `tier` hệ `element` (`count` kỹ năng đầu của hệ)."
  def mskills(nil, _element), do: []

  def mskills(tier, element),
    do: Enum.take(@mskills_by[element] || [], @mskills.tiers[tier].count)

  defp lord_special(:lord, element) do
    ls = @mskills.lord_special
    names = Map.new(ls.names, fn {k, v} -> {Atom.to_string(k), v} end)
    effects = Map.new(ls.effects, fn {k, v} -> {Atom.to_string(k), v} end)

    if ls.every > 0 and names[element],
      do: %{name: names[element], every: ls.every, mult: ls.mult, effect: effects[element]}
  end

  defp lord_special(_, _), do: nil

  @doc "Kháng hệ của nhân vật từ nhẫn / dây chuyền đang mặc có tác dụng (`RULES.monster_skills.resist`): %{hệ => tỉ lệ}."
  def resists(p) do
    r = @mskills.resist
    items = Map.new(r.items, fn {k, v} -> {Atom.to_string(k), v} end)

    for {_slot, id} <- p.equip,
        id,
        it = Gear.item(p, id),
        el = items[it[:base] || it[:id] || id],
        reduce: %{} do
      acc ->
        Map.update(
          acc,
          el,
          r.base + r.per_up * upgrade_level(p, id),
          &(&1 + r.base + r.per_up * upgrade_level(p, id))
        )
    end
    |> Map.new(fn {k, v} -> {k, min(r.max, Float.round(v * 1.0, 3))} end)
  end

  @doc """
  Quái sự kiện mạnh theo mốc chuyển sinh `k` (`RULES.event_scale`): máu / thủ × (1 + hp_per_rebirth × k), công
  × (1 + atk_per_rebirth × k), kinh nghiệm / vàng × (1 + reward_per_rebirth × k). `k` là mốc của phòng / tổ đội /
  sự kiện (DECISIONS "Sự kiện đánh chung theo phòng"), không phải của người đánh. Gọi ngay sau khi vào trận.
  """
  def scale_event(%{battle: %{monster: m}} = p, k) do
    k = min(k || 0, @char.max_rebirths)

    if k <= 0 do
      p
    else
      fh = 1 + @ev_scale.hp_per_rebirth * k
      fa = 1 + @ev_scale.atk_per_rebirth * k
      fr = 1 + @ev_scale.reward_per_rebirth * k

      up = fn m, key, f ->
        if is_number(m[key]), do: Map.put(m, key, round(m[key] * f)), else: m
      end

      m =
        m
        |> up.(:maxHp, fh)
        |> up.(:hp, fh)
        |> up.(:def, fh)
        |> up.(:atk, fa)
        |> up.(:xp, fr)
        |> up.(:gold, fr)

      put_in(p.battle.monster, m)
    end
  end

  def scale_event(p, _k), do: p

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

  @doc """
  Trận ở bản đồ phụ (Phase 15a): không thuộc vùng nào nên không cần mở vùng; `place` (tên bản đồ) và
  `theme` (nền) để client vẽ.
  """
  def start_side_encounter(p, spec, place, theme, boss? \\ false) do
    cond do
      p.battle ->
        {err("Đang trong trận đấu."), p}

      p.hp <= 0 ->
        {err("Bạn cần hồi máu trước."), p}

      true ->
        {r, p} = do_start_battle(p, nil, spec, boss?)
        {r, update_in(p.battle, &Map.merge(&1, %{place: place, theme: theme}))}
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

  # Nhật ký trận ghi tên, không xưng "bạn" (DECISIONS "Nhật ký trận: tên, dùng gì, gây bao nhiêu"): "Bạn" / "bạn"
  # trong câu đổi thành tên nhân vật
  @you ~r/(?<![\p{L}\p{N}_])[Bb]ạn(?![\p{L}\p{N}_])/u
  #
  # `parts` (DECISIONS "Nhật ký trận dễ đọc"): các phần để client vẽ câu thân thiện — `who` ("me" người chơi, "foe"
  # quái / đối thủ), `name`, `act` (tên kỹ năng, nil = đòn thường), `dmg`, `crit`, `miss`, `reflect`, `heal`, `mp`,
  # `hits`, `note` (khắc hệ…), `left` (máu quái còn lại), `turn` (lượt, để gom khối). `text` giữ câu đầy đủ như cũ.
  defp log(p, text, kind, parts \\ nil) do
    text = if p[:name], do: Regex.replace(@you, text, p.name), else: text
    entry = %{text: text, kind: kind}

    entry =
      if parts, do: Map.merge(entry, Map.put(parts, :turn, p.battle[:turn] || 0)), else: entry

    entries = p.battle.log ++ [entry]
    entries = if length(entries) > @log_limit, do: tl(entries), else: entries
    put_in(p.battle.log, entries)
  end

  @doc "Lượng hồi của bình `id` (số cố định `heal` / `mana`, DECISIONS \"Bình máu / mana hồi số\"): `{:hp | :mp, số}`."
  def potion_amount(_p, id) do
    it = Data.item(id)

    cond do
      it[:mana] -> {:mp, it.mana}
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

  # `mult`: hệ số hồi máu (đánh người: `RULES.pvp.potion_mult`)
  defp drink(p, id, mult \\ 1) do
    d = derived(p)

    case potion_amount(p, id) do
      {:mp, n} ->
        before = mp(p)
        p = %{p | mp: min(d.maxMp, before + n)} |> take_item(id)
        {p, p.mp - before}

      {:hp, n} ->
        before = p.hp
        p = %{p | hp: min(d.maxHp, p.hp + round(n * mult))} |> take_item(id)
        {p, p.hp - before}
    end
  end

  @doc """
  MP kỹ năng tốn ở cấp hiện tại (Phase 12): `mp` gốc của kỹ năng (kỹ năng mạnh gốc cao hơn) ×
  (1 + `skill_mp_per_level` × (cấp − 1)), để MP vẫn là giới hạn khi MP tối đa tăng theo cấp. Kỹ năng tháp (có `floor`)
  nhân thêm `RULES.tower_skills.mp_mult` theo lớp (Kiếm Sĩ, Tiên Nữ ít MP).
  """
  def skill_mp(p, skill) do
    # lớp ít MP (Kiếm Sĩ, Tiên Nữ): mọi kỹ năng (lớp + tháp) × `RULES.tower_skills.mp_mult` (DECISIONS "MP kỹ năng theo lớp")
    cls = class_mp_mult(p.cls)
    # thông thạo kỹ năng: cấp thấp tốn thêm MP (`RULES.skill_mastery.mp_low`)
    ms = Mastery.mp_factor(Mastery.level(p, skill.id))
    round((skill[:mp] || 0) * (1 + @skill_mp_per_level * (p.level - 1)) * cls * ms)
  end

  @doc "Hồi chiêu kỹ năng ở cấp thông thạo hiện tại (cấp thấp + `RULES.skill_mastery.cd_low` lượt)."
  def skill_cd(p, skill), do: skill.cooldown + Mastery.cd_extra(Mastery.level(p, skill.id))

  defp class_mp_mult(cls) do
    m = Map.get(@rules.tower_skills, :mp_mult) || %{}
    Map.get(m, String.to_atom(cls)) || Map.get(m, cls) || 1
  end

  # ---------- Kỹ năng ----------

  @doc "Các kỹ năng đã mở ở cấp hiện tại (mỗi lớp mở thêm kỹ năng ở cấp 10 và 25)."
  def skills(p) do
    avail = available_skills(p)

    case Map.get(p, :skill_set) do
      [_ | _] = ids ->
        picked = Enum.flat_map(ids, fn id -> Enum.filter(avail, &(&1.id == id)) end)
        if picked == [], do: default_set(avail), else: picked

      _ ->
        default_set(avail)
    end
  end

  @tower_skills @rules.tower_skills
  @loadout @tower_skills.loadout

  @doc """
  Mọi kỹ năng nhân vật đã có (Phase 3, B-29): kỹ năng lớp mở theo cấp, rồi kỹ năng tháp mở theo kỷ lục tháp
  (`tower_best` ≥ `floor`). `skills/1` là các kỹ năng mang vào trận (tối đa `RULES.tower_skills.loadout`).
  """
  def available_skills(p) do
    c = Data.class(p.cls)
    best = Map.get(p, :tower_best) || 0

    Enum.filter(c.skills, &(&1.level <= p.level)) ++
      Enum.filter(c[:tower_skills] || [], &(&1.floor <= best))
  end

  # chưa chọn: `loadout` kỹ năng mạnh nhất (cuối danh sách: lớp theo cấp, rồi tháp theo tầng), giữ thứ tự
  defp default_set(avail), do: Enum.take(avail, -@loadout)

  @doc "Chọn kỹ năng mang vào trận (`ids`: tối đa `loadout`, không trùng, đã mở). Đổi được cả trong trận (hồi chiêu giữ nguyên)."
  def set_skills(p, ids) do
    avail = Enum.map(available_skills(p), & &1.id)

    cond do
      not is_list(ids) or ids == [] or length(ids) > @loadout ->
        {err("Chọn từ 1 tới #{@loadout} kỹ năng."), p}

      Enum.uniq(ids) != ids or Enum.any?(ids, &(&1 not in avail)) ->
        {err("Kỹ năng không hợp lệ hoặc chưa mở."), p}

      true ->
        {ok("Đã đổi bộ kỹ năng."), Map.put(p, :skill_set, ids)}
    end
  end

  @doc "Số lượt còn phải chờ để dùng lại kỹ năng `id` trong trận hiện tại."
  def cooldown(%{battle: %{} = b}, id) do
    case Enum.find(Map.get(b, :cds) || [], &(&1.id == id)) do
      nil -> 0
      c -> c.turns
    end
  end

  def cooldown(_p, _id), do: 0

  # hiệu ứng lên mình của kỹ năng buff (Đánh nhanh: bước "chỉ dùng khi chưa có hiệu ứng")
  @buff_ids %{"war_cry" => "rage", "shadow_step" => "evade", "guard" => "guard"}

  @doc "Hiệu ứng buff của kỹ năng `k` còn trên người không (kỹ năng không buff: false)."
  def buff_active?(%{battle: %{}} = p, k) do
    case (k[:buff] || %{})[:id] || @buff_ids[k[:effect]] do
      nil -> false
      id -> effect(p, :player, id) != nil
    end
  end

  def buff_active?(_p, _k), do: false

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
    "evade" => "ảnh bộ",
    # Phase 3: kỹ năng tháp
    "sunder" => "phá giáp",
    "shield" => "khiên",
    "undying" => "bất tử"
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

  @doc "Tỉ lệ né đòn thường của quái trong trận: né (đã có trần) + buff né, tối đa `RULES.combat.dodge.max_with_buff`."
  def dodge_chance(p, d \\ nil),
    do: min(@combat.dodge.max_with_buff, (d || derived(p)).dodge + power(p, :player, "evade"))

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
        |> then(
          &if(b.monster[:pvp],
            do: put_in(&1, [:battle, :pstun_free], &1.battle.turn + 1 + @pvp.stun_immune),
            else: &1
          )
        )
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

  @doc "MP hồi mỗi lượt trong trận: `mp_regen` × MP tối đa + `mp_regen_ene` × Năng lượng."
  def mp_regen(p) do
    ene = Map.get(p.stats, :ene, 0)
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

        p
        |> log("Bạn uống #{Data.item(id).name}, hồi #{got} MP.", "good", %{
          who: "me",
          name: p.name,
          act: Data.item(id).name,
          potion: true,
          mp: got
        })
        |> monster_turn(d)
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

  # Đánh người (DECISIONS "Đánh người: bình máu"): bình máu hồi × `RULES.pvp.potion_mult`, mỗi `potion_cd` lượt
  # của mình uống được một lần (uống ở lượt T thì lượt T + potion_cd mới uống lại), tối đa `potion_max` bình mỗi trận.
  @doc """
  Uống bình máu được không lúc này (đánh người: chưa quá `potion_max` bình, đã qua `potion_cd` lượt). Bot dùng để không
  gửi lệnh uống bị từ chối rồi đứng im tới hết lượt.
  """
  def potion_ready?(%{battle: %{monster: m} = b}) do
    m[:pvp] == nil or
      ((b[:pots_used] || 0) < @pvp.potion_max and
         (b[:pot_at] || -99) + @pvp.potion_cd - (b.turn + 1) <= 0)
  end

  def potion_ready?(_p), do: true

  defp act_potion(p, d) do
    id = best_potion(p, d.maxHp - p.hp)
    poisoned = Enum.filter(effects(p, :player), &(&1.id in @dots))
    b = p.battle
    pvp? = b.monster[:pvp] != nil
    wait = if pvp?, do: (b[:pot_at] || -99) + @pvp.potion_cd - (b.turn + 1), else: 0

    cond do
      id == nil ->
        {err("Hết bình máu."), p}

      p.hp >= d.maxHp and poisoned == [] ->
        {err("Máu đang đầy."), p}

      pvp? and (b[:pots_used] || 0) >= @pvp.potion_max ->
        {err("Đánh người: mỗi trận chỉ uống được #{@pvp.potion_max} bình máu."), p}

      wait > 0 ->
        {err("Đánh người: bình máu dùng lại sau #{wait} lượt."), p}

      true ->
        {p, healed} = p |> next_turn() |> drink(id, if(pvp?, do: @pvp.potion_mult, else: 1))

        p =
          if pvp?,
            do:
              p
              |> put_in([:battle, :pot_at], p.battle.turn)
              |> update_in([:battle, :pots_used], &((&1 || 0) + 1)),
            else: p

        p =
          log(p, "Bạn uống #{Data.item(id).name}, hồi #{healed} máu.", "good", %{
            who: "me",
            name: p.name,
            act: Data.item(id).name,
            potion: true,
            heal: healed
          })

        # bình máu giải luôn độc, bỏng, chảy máu
        p =
          if poisoned == [],
            do: p,
            else:
              p
              |> set_effects(:player, Enum.reject(effects(p, :player), &(&1.id in @dots)))
              |> log("Hết #{effect_list(poisoned)}.", "good")

        monster_turn(p, d)
    end
  end

  defp pick_skill(p, nil), do: List.first(skills(p))
  defp pick_skill(p, id), do: Enum.find(skills(p), &(&1.id == id))

  # "dùng gì" trong nhật ký trận: tên kỹ năng, không thì Đòn thường
  defp strike_name(nil), do: "Đòn thường"
  defp strike_name(skill), do: skill.name

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

        pvp = m[:pvp] != nil

        {p, atk, dfn, crit, mult, _name, on_hit} =
          strike_with(p, skill, d, atk, m.def, chance(if pvp, do: pvp_crit(d.crit), else: d.crit))

        # thông thạo kỹ năng: hệ số trong dữ liệu là của cấp tối đa
        mult = if skill, do: mult * Mastery.mult(Mastery.level(p, skill.id)), else: mult

        dfn = round(dfn * (1 - d.ignoreDef) * (1 - power(p, :monster, "sunder")))
        # Phase 3: nguyên tố kỹ năng so với nguyên tố quái
        {emult, eres} = Elements.mult(skill && skill[:element], m[:element])

        # kỹ năng luôn trúng; đòn thường: đấu trường theo né của đối thủ, quái theo tỉ lệ trúng
        p =
          if skill == nil and
               if(pvp,
                 do: chance(m.dodge * @pvp.dodge_mult),
                 # quái đang Gió Lốc (kỹ năng hệ Gió): né thêm đòn thường
                 else: chance(1 - hit_chance(d.ar, m.level) * (1 - power(p, :monster, "gale")))
               ) do
            log(p, "#{p.name}, #{strike_name(skill)}, đánh trượt.", "info", %{
              who: "me",
              name: p.name,
              act: skill && skill.name,
              miss: true
            })
          else
            # hiểu rõ loài này (sổ tay quái vật) thì đánh mạnh hơn
            mult = mult * (1 + Bestiary.mastery(p, m.id)) * (1 + d.wingDmg)

            mult =
              if skill, do: mult * (1 + d.skillDmg) * emult * weather_mult(p, skill), else: mult

            hits = (skill && skill[:hits]) || 1

            # đối thủ là người (đấu trường, đồ sát): giảm sát thương nhận của cánh và Excellent bên đó;
            # kỹ năng nhiều đòn: chia đều hệ số, mỗi đòn trừ giáp riêng
            dmg =
              Enum.sum(
                for _ <- 1..hits,
                    do:
                      damage(
                        atk,
                        dfn,
                        mult / hits *
                          if(crit,
                            do: if(pvp, do: pvp_crit_mult(d.critMult), else: d.critMult),
                            else: 1
                          ),
                        (m[:taken] || 1) * (1 - power(p, :monster, "stone")) *
                          if(pvp, do: pvp_taken(m[:cls], m[:rebirths], m[:arena]), else: 1)
                      )
              )

            # dòng của khiên / phản đòn / đòn mở màn ghi SAU dòng "Bạn gây …" (đúng thứ tự xảy ra)
            log0 = p.battle.log
            {dmg, p} = mirror_guard(put_in(p.battle.log, []), dmg)
            {dmg, p} = arena_opening(p, dmg)
            {after_hit, p} = {p.battle.log, put_in(p.battle.log, log0)}
            p = put_in(p, [:battle, :overkill], p.battle.monster.hp - dmg)
            p = update_in(p.battle.monster.hp, &max(0, &1 - dmg))

            suffix =
              if(hits > 1, do: " (#{hits} đòn)", else: "") <>
                if(crit, do: " (CHÍ MẠNG!)", else: "") <>
                case eres do
                  :strong -> " (khắc hệ #{Elements.name(m[:element])}!)"
                  :weak -> " (bị hệ #{Elements.name(m[:element])} khắc)"
                  nil -> ""
                end

            note =
              case eres do
                :strong -> "khắc hệ #{Elements.name(m[:element])}!"
                :weak -> "bị hệ #{Elements.name(m[:element])} khắc"
                nil -> nil
              end

            p
            |> log(
              "#{p.name}, #{strike_name(skill)}, gây #{dmg} sát thương#{suffix}.",
              if(crit, do: "crit", else: "hit"),
              %{
                who: "me",
                name: p.name,
                act: skill && skill.name,
                dmg: dmg,
                crit: crit,
                hits: if(hits > 1, do: hits),
                note: note,
                left: p.battle.monster.hp
              }
            )
            |> then(&Enum.reduce(after_hit, &1, fn e, p -> log(p, e.text, e.kind) end))
            |> on_hit.(dmg)
          end

        # dùng kỹ năng với quái: cộng điểm thông thạo (đánh người không tính)
        p = if skill && !pvp, do: Mastery.gain(p, skill, m), else: p

        cond do
          # đồ sát: thắng thua do HacLong.Slay quyết (máu hai bên giữ ở đó);
          # vẫn trừ hồi chiêu và hiệu ứng mỗi lượt của mình
          p.battle[:live] -> tick_round(p)
          p.battle.monster.hp <= 0 and p.battle[:mirror] != nil -> mirror_last(p, d)
          p.battle.monster.hp <= 0 -> win(p)
          true -> monster_turn(p, d)
        end
    end
  end

  # phần sát thương nhận thú Hộ vệ / Long Vương đỡ (`bonus.reduce`, DECISIONS "Thú cưng 3 nhóm, chỉ cộng chỉ số")
  defp pet_guard(p), do: min(Pets.bonus(p, :reduce), 0.5)

  # Trả về {nhân_vật, tấn_công, phòng_thủ_quái, chí_mạng?, hệ_số, tên, hàm_sau_khi_trúng}.
  defp strike_with(p, nil, _d, atk, dfn, crit),
    do: {p, atk, dfn, crit, 1, "tấn công", fn p, _ -> p end}

  # Phase 3 (B-29): kỹ năng tháp, mọi tác dụng ghi trong dữ liệu (`RULES.tower_skills._doc`)
  defp strike_with(p, %{floor: _} = skill, d, atk, dfn, crit) do
    p = set_cd(p, skill.id, skill_cd(p, skill) + 1)
    p = %{p | mp: mp(p) - skill_mp(p, skill)}
    m = p.battle.monster

    # thông thạo kỹ năng: dưới cấp tối đa tác dụng phụ yếu hơn (`effect_low`)
    skill = scale_tower(skill, Mastery.effect(Mastery.level(p, skill.id)))
    dfn = if skill[:def_mult], do: round(dfn * skill.def_mult), else: dfn
    crit = skill[:crit] == true or crit

    p =
      case skill[:heal] do
        h when is_number(h) ->
          before = p.hp
          p = %{p | hp: min(d.maxHp, p.hp + pvp_heal(p, d.maxHp * h))}

          log(p, "#{skill.name} hồi #{p.hp - before} máu.", "good", %{
            who: "me",
            name: p.name,
            act: skill.name,
            heal: p.hp - before
          })

        _ ->
          p
      end

    on_hit = fn p, dmg ->
      p
      |> skill_drain(skill, d, dmg)
      |> skill_stun(skill, m)
      |> skill_buff(skill[:buff], d)
      |> skill_debuff(skill[:debuff], m, dmg)
    end

    {p, atk, dfn, crit, skill.mult, skill.name, on_hit}
  end

  defp strike_with(p, skill, d, atk, dfn, crit) do
    # +1 vì cuối lượt sẽ trừ 1
    p = set_cd(p, skill.id, skill_cd(p, skill) + 1)
    p = %{p | mp: mp(p) - skill_mp(p, skill)}
    m = p.battle.monster
    none = fn p, _ -> p end

    # tác dụng theo `effect` (kỹ năng các lớp dùng chung vài kiểu tác dụng), số ở `RULES.skill_effects`;
    # thông thạo kỹ năng: dưới cấp tối đa hồi máu / sức tác dụng / tỉ lệ choáng × `effect_low`
    effect = skill[:effect] || skill.id
    ef = Mastery.effect(Mastery.level(p, skill.id))
    e = scale_effect(@effects[String.to_existing_atom(effect)], ef)
    dfn = if e[:def_mult], do: round(dfn * e.def_mult), else: dfn
    crit = e[:always_crit] || crit
    pct = fn x -> round(x * 100) end

    case effect do
      "holy" ->
        heal = pvp_heal(p, d.maxHp * e.heal)
        before = p.hp
        p = %{p | hp: min(d.maxHp, p.hp + heal)}

        {log(p, "Khiên Thánh hồi #{p.hp - before} máu.", "good"), atk, dfn, crit, e.mult,
         skill.name, none}

      "stun_bash" ->
        {p, atk, dfn, crit, e.mult, skill.name,
         fn p, _ ->
           cond do
             (m.boss || m[:world]) && chance(e.boss_resist) ->
               log(p, "#{m.name} không bị choáng.", "info")

             # chưa tối đa thông thạo: không chắc choáng
             ef < 1 and not chance(ef) ->
               log(p, "#{m.name} không bị choáng.", "info")

             true ->
               stun_monster(p, "💫 #{m.name} bị choáng!")
           end
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
           |> log("☠ #{m.name} trúng độc.", "good", %{
             who: "foe",
             name: m.name,
             status: "trúng độc",
             per: max(1, round(dmg * e.power)),
             turns: e.turns
           })
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

  # thông thạo kỹ năng: tác dụng phụ kỹ năng tháp × `f` (hồi máu, hút máu, tỉ lệ khống chế, sức buff / debuff)
  defp scale_tower(skill, f) when f == 1, do: skill

  defp scale_tower(skill, f) do
    num = fn v -> if is_number(v), do: v * f, else: v end
    pw = fn b -> if is_map(b) and is_number(b[:power]), do: %{b | power: b.power * f}, else: b end

    skill
    |> Map.update(:heal, nil, num)
    |> Map.update(:drain, nil, num)
    |> Map.update(:stun, nil, num)
    |> Map.update(:buff, nil, pw)
    |> Map.update(:debuff, nil, pw)
  end

  defp scale_effect(e, f) when f == 1, do: e

  defp scale_effect(e, f) do
    e
    |> then(&if(is_number(&1[:heal]), do: %{&1 | heal: &1.heal * f}, else: &1))
    |> then(&if(is_number(&1[:power]), do: %{&1 | power: &1.power * f}, else: &1))
  end

  defp skill_drain(p, %{drain: f}, d, dmg) when is_number(f) and dmg > 0 do
    before = p.hp
    p = %{p | hp: min(d.maxHp, p.hp + round(dmg * f))}
    if p.hp > before, do: log(p, "🩸 Hút #{p.hp - before} máu.", "good"), else: p
  end

  defp skill_drain(p, _skill, _d, _dmg), do: p

  defp skill_stun(p, %{stun: c}, m) when is_number(c) do
    cond do
      p.battle.monster.hp <= 0 or not chance(c) ->
        p

      (m.boss || m[:world]) && chance(@tower_skills.stun_boss_resist) ->
        log(p, "#{m.name} không bị choáng.", "info")

      true ->
        stun_monster(p, "💫 #{m.name} bị khống chế, mất lượt!")
    end
  end

  defp skill_stun(p, _skill, _m), do: p

  defp skill_buff(p, %{id: "shield", turns: t, power: f}, d) do
    pool = max(1, round(d.maxHp * f))

    p
    |> put_effect(:player, "shield", t, pool)
    |> log("🛡 Khiên hấp thụ #{pool} sát thương.", "good")
  end

  defp skill_buff(p, %{id: "undying", turns: t, power: f}, _d) do
    p
    |> put_effect(:player, "undying", t, f)
    |> log("✨ Bất tử: gục ngã trong #{t} lượt sẽ đứng dậy với #{round(f * 100)}% máu.", "good")
  end

  defp skill_buff(p, %{id: id, turns: t, power: f}, _d) do
    p
    |> put_effect(:player, id, t, f)
    |> log("Bạn được #{@effect_names[id]} (#{round(f * 100)}%) trong #{t} lượt.", "good")
  end

  defp skill_buff(p, _b, _d), do: p

  defp skill_debuff(p, %{id: id, turns: t, power: f}, m, dmg) when id in @dots do
    if p.battle.monster.hp > 0 and dmg > 0 do
      p
      |> put_effect(:monster, id, t, max(1, round(dmg * f)))
      |> log("#{m.name} #{@effect_names[id]}.", "good")
    else
      p
    end
  end

  defp skill_debuff(p, %{id: id, turns: t, power: f}, m, _dmg) do
    if p.battle.monster.hp > 0 do
      p
      |> put_effect(:monster, id, t, f)
      |> log("#{m.name} bị #{@effect_names[id]} #{round(f * 100)}% trong #{t} lượt.", "good")
    else
      p
    end
  end

  defp skill_debuff(p, _x, _m, _dmg), do: p

  # khiên (kỹ năng tháp) hấp thụ sát thương trước khi mất máu: `{sát_thương_còn_lại, nhân_vật}`
  defp absorb_shield(p, dmg) do
    case effect(p, :player, "shield") do
      %{power: pool} when pool > 0 and dmg > 0 ->
        used = min(pool, dmg)

        list =
          effects(p, :player)
          |> Enum.map(&if(&1.id == "shield", do: %{&1 | power: pool - used}, else: &1))
          |> Enum.reject(&(&1.id == "shield" and &1.power <= 0))

        {dmg - used,
         p |> set_effects(:player, list) |> log("🛡 Khiên đỡ #{used} sát thương.", "good")}

      _ ->
        {dmg, p}
    end
  end

  # bất tử (kỹ năng tháp): gục thì đứng dậy với `power` × máu tối đa, một lần.
  # Đánh người (DECISIONS "Đánh người: mỗi trận cứu một lần"): bất tử chỉ cứu một lần mỗi trận
  # (`pet_revived`), dùng lại Bất Tử không cứu thêm.
  defp survive(%{hp: hp, battle: %{monster: %{pvp: pvp}, pet_revived: true}} = p, _d)
       when hp <= 0 and pvp not in [nil, false],
       do: p

  defp survive(%{hp: hp} = p, d) when hp <= 0 do
    case effect(p, :player, "undying") do
      %{power: f} ->
        %{p | hp: max(1, round(d.maxHp * f))}
        |> drop_effect(:player, "undying")
        |> then(
          &if(&1.battle.monster[:pvp], do: put_in(&1, [:battle, :pet_revived], true), else: &1)
        )
        |> log("✨ Bất tử! Bạn đứng dậy với #{max(1, round(d.maxHp * f))} máu.", "good")

      nil ->
        p
    end
  end

  defp survive(p, _d), do: p

  # đồ sát: đối thủ là người thật, tự ra đòn ở lượt của họ
  defp monster_turn(%{battle: %{live: true}} = p, _d), do: tick_round(p)

  defp monster_turn(p, d) do
    p = copy_tick(p)
    b = p.battle
    m = b.monster

    # đấu trường (đối thủ chạy như người): choáng vừa gây trong lượt này có hiệu lực từ lượt sau, như hai bên ra đòn
    # cùng lúc (người ra đòn trước không được thêm lợi thế)
    st = effect(p, :monster, "stun")
    fresh? = st && b[:mirror] && st.power == b.turn

    if st && !fresh? do
      p
      |> drop_effect(:monster, "stun")
      |> stun_cooled()
      |> log("💫 #{m.name} bị choáng, không đánh được.", "good")
      |> round_end()
    else
      cond do
        b[:mirror] -> mirror_turn(p, d)
        k = m[:skills] && copy_pick(b) -> copy_skill(p, d, k)
        true -> monster_strike(p, d)
      end
    end
  end

  # đòn thường / chiêu đặc biệt của quái (và bản sao người khi chưa có kỹ năng dùng được)
  defp monster_strike(p, d) do
    b = p.battle
    m = b.monster
    special = m.special != nil and rem(b.turn, m.special.every) == 0

    case not special and m[:pvp] == nil and mskill_pick(p) do
      %{} = k -> mskill_use(p, d, k)
      _ -> monster_attack(p, d)
    end
  end

  # kỹ năng quái hết hồi chiêu, tung với tỉ lệ `mskill_chance` mỗi lượt
  defp mskill_pick(p) do
    b = p.battle
    m = b.monster
    cds = b[:mscd] || %{}
    ready = for k <- m[:mskills] || [], (cds[k.id] || 0) <= b.turn, do: k

    if ready != [] and chance(m[:mskill_chance] || 0), do: pick(ready)
  end

  defp mskill_use(p, d, k) do
    b = p.battle
    m = b.monster
    el = m[:element]
    icon = Elements.icon(el)
    act = String.trim("#{icon} #{k.name}")
    p = put_in(p, [:battle, :mscd], Map.put(b[:mscd] || %{}, k.id, b.turn + @mskills.cooldown))
    res = Map.get(d[:resist] || %{}, el, 0)

    cond do
      k[:self] ->
        e = k.self

        txt =
          if e.id == "stone",
            do: "giảm #{round(e.power * 100)}% sát thương nhận",
            else: "né thêm #{round(e.power * 100)}% đòn thường"

        p
        |> put_effect(:monster, e.id, e.turns + 1, e.power)
        |> log("#{m.name}, #{k.name}: #{txt} (#{e.turns} lượt).", "bad", %{
          who: "foe",
          name: m.name,
          act: act,
          note: "#{txt}, #{e.turns} lượt"
        })
        |> round_end()

      k[:heal] ->
        n = min(m.maxHp - m.hp, round(m.maxHp * k.heal))

        p
        |> update_in([:battle, :monster, :hp], &(&1 + n))
        |> log("#{m.name}, #{k.name}, hồi #{n} máu.", "bad", %{
          who: "foe",
          name: m.name,
          act: act,
          heal: n
        })
        |> round_end()

      true ->
        hits = k[:hits] || 1
        m_atk = round(m.atk * (1 - power(p, :monster, "weaken")))

        # thời tiết cùng hệ cộng như kỹ năng người; kháng hệ của nhẫn / dây chuyền giảm theo đúng tỉ lệ
        mult = k.mult * weather_mult(p, %{element: el}) * (1 - res)

        taken =
          (1 - power(p, :player, "guard")) * (1 - d.wingAbsorb) * (1 - d.excAbsorb) *
            (1 - pet_guard(p))

        dmg = Enum.sum(for _ <- 1..hits, do: damage(m_atk, d.def, mult / hits, taken))
        {dmg, p} = absorb_shield(p, dmg)
        p = %{p | hp: max(0, p.hp - dmg)} |> survive(d)
        note = if res > 0, do: "kháng #{Elements.name(el)} #{round(res * 100)}%"

        p =
          p
          |> log(
            "#{m.name}, #{k.name}, gây #{dmg} sát thương#{if hits > 1, do: " (#{hits} đòn)"}.",
            "bad",
            %{
              who: "foe",
              name: m.name,
              act: act,
              dmg: dmg,
              hits: if(hits > 1, do: hits),
              note: note,
              el: el
            }
          )
          |> reflect(dmg, d.excReflect)

        # hút máu: quái hồi phần sát thương gây ra
        p =
          if k[:drain] && dmg > 0,
            do: update_in(p, [:battle, :monster, :hp], &min(m.maxHp, &1 + round(dmg * k.drain))),
            else: p

        p =
          cond do
            k[:effect] == nil or p.hp <= 0 ->
              p

            k.effect.id == "stun" and not chance(k.effect[:chance] || 1) ->
              p

            res > 0 and chance(res) ->
              log(
                p,
                "🛡 #{p.name} kháng được #{@effect_names[k.effect.id]} (kháng #{Elements.name(el)}).",
                "good"
              )

            true ->
              inflict(p, m, Map.merge(%{turns: 1, power: 0}, k.effect))
          end

        if p.hp <= 0, do: lose(p), else: round_end(p)
    end
  end

  defp monster_attack(p, d) do
    b = p.battle
    m = b.monster

    (
      special = m.special != nil and rem(b.turn, m.special.every) == 0
      m_atk = if special, do: round(m.atk * m.special.mult), else: m.atk
      m_atk = round(m_atk * (1 - power(p, :monster, "weaken")))

      pvp = m[:pvp] != nil

      p =
        if not special and
             chance(dodge_chance(p, d) * if(pvp, do: @pvp.dodge_mult, else: 1)) do
          log(p, "#{m.name}, Đòn thường, đánh trượt.", "info", %{
            who: "foe",
            name: m.name,
            miss: true
          })
        else
          mc = not special and chance(if pvp, do: pvp_crit(m.crit), else: m.crit)
          cm = m[:crit_mult] || @combat.monster_crit_mult

          dmg =
            damage(
              m_atk,
              # đối thủ là người có dòng cánh "bỏ qua phòng thủ"
              round(d.def * (1 - (m[:ignore_def] || 0))),
              if(mc, do: if(pvp, do: pvp_crit_mult(cm), else: cm), else: 1),
              (1 - power(p, :player, "guard")) * (1 - d.wingAbsorb) * (1 - d.excAbsorb) *
                (1 - pet_guard(p)) *
                if(pvp, do: pvp_taken(p.cls, Map.get(p, :rebirths), m[:arena]), else: 1)
            )

          {dmg, p} = absorb_shield(p, dmg)
          p = %{p | hp: max(0, p.hp - dmg)} |> survive(d)

          text =
            "#{m.name}, #{if special, do: m.special.name, else: "Đòn thường"}, gây #{dmg} sát thương" <>
              if(mc, do: " (CHÍ MẠNG!).", else: ".")

          p =
            log(p, text, "bad", %{
              who: "foe",
              name: m.name,
              act: if(special, do: m.special.name),
              dmg: dmg,
              crit: mc
            })
            |> reflect(dmg, d.excReflect)

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
    )
  end

  # ---------- Bản sao người dùng kỹ năng thật (đấu trường; DECISIONS "Cân bằng đánh người") ----------
  # đầu lượt của bản sao: trừ hồi chiêu, hồi MP
  defp copy_tick(%{battle: %{monster: %{skills: [_ | _]} = m} = b} = p) do
    cds = for %{turns: n} = c <- Map.get(b, :mcds, []), n > 1, do: %{c | turns: n - 1}
    m = %{m | mp: min(m.maxMp, m.mp + m.mp_regen)}
    %{p | battle: %{b | monster: m} |> Map.put(:mcds, cds)}
  end

  defp copy_tick(p), do: p

  # kỹ năng mạnh nhất đã hết hồi chiêu và đủ MP
  defp copy_pick(b) do
    m = b.monster
    busy = for c <- Map.get(b, :mcds, []), do: c.id

    m.skills
    |> Enum.filter(&(&1.id not in busy and m.mp >= &1.mp))
    |> Enum.max_by(& &1.mult, fn -> nil end)
  end

  defp copy_skill(p, d, k) do
    m = p.battle.monster
    atk = round(m.atk * (1 - power(p, :monster, "weaken")))
    dfn = round(d.def * (1 - (m[:ignore_def] || 0)) * (k.def_mult || 1))
    crit = k.crit or chance(pvp_crit(m.crit))
    cm = if crit, do: pvp_crit_mult(m[:crit_mult] || @combat.monster_crit_mult), else: 1

    taken =
      (1 - power(p, :player, "guard")) * (1 - d.wingAbsorb) * (1 - d.excAbsorb) *
        (1 - pet_guard(p)) * pvp_taken(p.cls, Map.get(p, :rebirths), m[:arena])

    dmg = Enum.sum(for _ <- 1..k.hits, do: damage(atk, dfn, k.mult / k.hits * cm, taken))
    {dmg, p} = absorb_shield(p, dmg)
    p = %{p | hp: max(0, p.hp - dmg)} |> survive(d)

    p =
      p
      |> put_in([:battle, :monster, :mp], m.mp - k.mp)
      |> put_in([:battle, :mcds], [%{id: k.id, turns: k.cd + 1} | Map.get(p.battle, :mcds, [])])
      |> log(
        "#{m.name}, #{k.name}, gây #{dmg} sát thương#{if crit, do: " (CHÍ MẠNG!)", else: ""}.",
        "bad",
        %{who: "foe", name: m.name, act: k.name, dmg: dmg, crit: crit}
      )
      |> reflect(dmg, d.excReflect)

    if p.hp <= 0, do: lose(p), else: round_end(p)
  end

  # ---------- Đối thủ đấu trường chạy như người thật (`battle.mirror`) ----------
  # `mirror`: nhân vật bên bị thách đấu trong trận `live` với bản sao của người thách đấu; mỗi lượt của đối thủ máy
  # chọn kỹ năng mạnh nhất (`auto_strike/1`) và đánh bằng đúng bộ máy trận (thú cưng, buff, hồi máu, gây choáng).
  # Chỉ giữ trong bộ nhớ (không lưu, không gửi client); mất thì đối thủ dùng `copy_skill/3`.
  @pad 10_000_000

  @doc "Dựng `mirror` cho trận đấu trường: `foe` là nhân vật bị thách đấu, `copy` là bản sao người thách đấu."
  def mirror(foe, copy) do
    d = derived(foe)
    foe = %{foe | battle: nil, hp: d.maxHp} |> Map.put(:mp, d.maxMp)
    {_, foe} = start_with_monster(foe, 1, copy)
    put_in(foe, [:battle, :live], true)
  end

  defp mirror_turn(p, d) do
    p = mirror_strike(p, d)
    if p.hp <= 0, do: lose(p), else: round_end(p)
  end

  # Đối thủ đấu trường vừa bị hạ: Bất Tử của họ (mỗi trận một lần) như người thật; không được cứu thì vẫn
  # kịp ra đòn cuối (cùng lúc với đòn của mình). Cả hai cùng gục: bên bị đánh lố ít hơn (so với máu tối đa) thắng.
  defp mirror_last(p, d) do
    if q = mirror_revive(p) do
      monster_turn(q, d)
    else
      foe_over = (p.battle[:overkill] || 0) / max(p.battle.monster.maxHp, 1)
      hp0 = p.hp
      p = mirror_strike(%{p | battle: %{p.battle | monster: %{p.battle.monster | hp: 1}}}, d)
      p = put_in(p, [:battle, :monster, :hp], 0)
      me_over = (hp0 - (p.battle[:last_hit] || 0)) / d.maxHp

      cond do
        p.hp > 0 -> win(p)
        me_over >= foe_over -> p |> both_down(me_over, foe_over, true) |> Map.put(:hp, 1) |> win()
        true -> p |> both_down(me_over, foe_over, false) |> lose()
      end
    end
  end

  # cả hai cùng gục: nói rõ ai bị đánh lố bao nhiêu (% máu tối đa) để người chơi hiểu vì sao thắng / thua
  defp both_down(p, me_over, foe_over, won?) do
    name = p.battle.monster.name
    pc = fn x -> round(-x * 100) end

    log(
      p,
      "⚖ Cả hai cùng gục: bạn bị đánh lố #{pc.(me_over)}% máu, #{name} lố #{pc.(foe_over)}% → " <>
        if(won?, do: "bạn thắng.", else: "#{name} thắng."),
      "info"
    )
  end

  # đối thủ đấu trường hết máu: Bất Tử của họ (mỗi trận một lần); không được cứu thì nil
  defp mirror_revive(%{battle: %{mirror: %{} = mi}} = p) do
    saved = survive(%{mi | hp: 0}, derived(mi))

    if saved.hp > 0 do
      p
      |> put_in([:battle, :monster, :hp], saved.hp)
      |> put_in([:battle, :mirror], saved)
      |> log("🐉 #{p.battle.monster.name} đứng dậy với #{saved.hp} máu.", "bad")
    end
  end

  defp mirror_revive(_p), do: nil

  defp mirror_strike(p, d) do
    b = p.battle
    m = b.monster

    # nhật ký trống: lấy đúng các dòng lượt của đối thủ (kỹ năng, chí mạng, nhiều đòn, trượt, thú cưng…)
    mi =
      %{b.mirror | hp: m.hp}
      |> put_in([:battle, :monster, :hp], p.hp + @pad)
      |> put_in([:battle, :log], [])

      # suy yếu mình đặt lên đối thủ: đòn của đối thủ máy yếu đi như người thật (hiệu ứng chéo)
      |> set_effects(
        :player,
        Enum.reject(effects(b.mirror, :player), &(&1.id == "weaken")) ++
          Enum.filter(effects(p, :monster), &(&1.id == "weaken"))
      )

    # đối thủ máy uống bình máu như người (dưới nửa máu; luật bình khi đánh người: hồi ×, cách lượt, tối đa mỗi trận)
    {r, mi2} =
      if mi.hp < derived(mi).maxHp * 0.5 and best_potion(mi, derived(mi).maxHp - mi.hp) != nil,
        do: act(mi, "potion"),
        else: {%{ok: false}, mi}

    mi =
      if r[:ok] == false do
        {act, sk} = auto_strike(mi)
        elem(act(mi, act, sk), 1)
      else
        mi2
      end
      |> fresh_buffs(effects(mi, :player))

    raw = p.hp + @pad - mi.battle.monster.hp
    stun? = effect(mi, :monster, "stun")
    mi = drop_effect(mi, :monster, "stun")

    # độc / bỏng / chảy máu / suy yếu đối thủ máy gây lên bản sao của mình: chuyển sang mình (như đồ sát)
    {mi, debuffs} = pvp_take_debuffs(mi)
    healed = mi.hp - m.hp

    # máu tối đa của đối thủ theo chỉ số thật lúc này (buff tăng máu như Tăng Sinh Lực), như máu tối đa của mình
    mmax = max(m.maxHp, derived(mi).maxHp)

    p =
      p
      |> put_in([:battle, :monster, :maxHp], mmax)
      |> put_in([:battle, :monster, :hp], min(mmax, mi.hp))

    # buff phòng thủ / khiên / thú che chắn của mình trong trận vẫn tính
    dealt = round(raw * (1 - power(p, :player, "guard")) * (1 - pet_guard(p)))
    {dealt, p} = if dealt > 0, do: absorb_shield(p, dealt), else: {0, p}
    p = %{p | hp: max(0, p.hp - dealt)} |> survive(d) |> put_in([:battle, :last_hit], dealt)

    lines =
      for l <- BattleText.view(mi.battle.log, m.name, p.name),
          do: {l.text, if(l.kind in ~w(hit crit), do: "bad", else: "info")}

    lines = if lines == [], do: [{"#{m.name} ra đòn nhưng không trúng.", "info"}], else: lines
    healed? = healed > 0 and not Enum.any?(lines, fn {t, _} -> t =~ ~r/hồi|Hút/u end)

    p =
      Enum.reduce(lines, p, fn {t, k}, p -> log(p, t, k) end)
      |> then(&if(healed?, do: log(&1, "#{m.name} hồi #{healed} máu.", "info"), else: &1))
      |> then(
        &if(dealt != raw and raw > 0,
          do: log(&1, "Bạn chỉ mất #{dealt} máu (thủ thế / khiên / thú che chắn).", "info"),
          else: &1
        )
      )
      |> reflect(dealt, d.excReflect)
      |> pvp_receive(debuffs)
      |> put_in([:battle, :mirror], mi)

    p =
      cond do
        !stun? or p.hp <= 0 ->
          p

        p.battle.turn < (p.battle[:pstun_free] || 0) ->
          log(p, "Bạn vừa thoát choáng, kháng được.", "info")

        ward?(p) ->
          log(p, "🐉 Long Uy: #{p.name} kháng được choáng.", "good")

        true ->
          p |> put_effect(:player, "stun", 1, 0) |> log("💫 Bạn bị choáng!", "bad")
      end

    p
  end

  @doc "Kỹ năng đang mang của `p` cho bản sao người (`HacLong.Arena.opponent/2`): hệ số, số đòn, hồi chiêu, MP."
  def copy_skills(p) do
    d = derived(p)

    for k <- skills(p) do
      e = if k[:floor], do: k, else: @effects[String.to_existing_atom(k[:effect] || k.id)] || %{}

      %{
        id: k.id,
        name: k.name,
        mult:
          (k[:mult] || e[:mult] || 1) * (1 + d.skillDmg) * Mastery.mult(Mastery.level(p, k.id)),
        hits: k[:hits] || 1,
        def_mult: k[:def_mult] || e[:def_mult],
        crit: k[:crit] == true or e[:always_crit] == true,
        cd: skill_cd(p, k),
        mp: skill_mp(p, k)
      }
    end
  end

  # Excellent "phản sát thương" (B-16): quái mất `pct` phần sát thương vừa gây, không chết vì phản đòn (còn ít nhất 1).
  # Đánh người (đối thủ có `pvp`): phản đòn hạ được đối thủ (anh duyệt 2026-10-23); `round_end/1` xử thắng.
  defp reflect(p, _dmg, pct) when pct <= 0, do: p

  defp reflect(p, dmg, pct) do
    m = p.battle.monster
    back = min(round(dmg * pct), if(m[:pvp], do: m.hp, else: m.hp - 1))

    if back > 0,
      do:
        put_in(p.battle.monster.hp, m.hp - back)
        |> log("#{m.name}, bị phản #{back} sát thương.", "good", %{
          who: "foe",
          name: m.name,
          reflect: back,
          left: m.hp - back
        }),
      else: p
  end

  # Quái gây hiệu ứng lên người chơi.
  # Long Uy (DECISIONS "Long Vương: thần thú độc nhất"): dắt Long Vương thì kháng một phần hiệu ứng xấu
  defp ward?(p) do
    w = Pets.trait(p, :ward)
    w > 0 and chance(w)
  end

  defp inflict(p, m, e) do
    if ward?(p),
      do: log(p, "🐉 Long Uy: #{p.name} kháng được #{@effect_names[e.id] || "hiệu ứng"}.", "good"),
      else: inflict_(p, m, e)
  end

  defp inflict_(p, m, e) do
    case e.id do
      id when id in @dots ->
        per = max(1, round(m.atk * e.power))

        p
        |> put_effect(:player, id, e.turns, per)
        |> log(
          "Bạn #{@effect_names[id]} (-#{per} máu mỗi lượt, uống bình máu để giải).",
          "bad",
          %{
            who: "me",
            name: p.name,
            status: @effect_names[id],
            per: per,
            turns: e.turns
          }
        )

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

    mdot =
      if m[:pvp] && mdot > 0,
        do: max(1, round(mdot * pvp_taken(m[:cls], m[:rebirths], m[:arena]))),
        else: mdot

    p =
      if mdot > 0 do
        p
        |> update_in([:battle, :monster, :hp], &max(0, &1 - mdot))
        |> then(
          &log(&1, "☠ #{m.name} mất #{mdot} máu vì độc.", "hit", %{
            who: "foe",
            name: m.name,
            dot: "độc",
            dmg: mdot,
            left: &1.battle.monster.hp
          })
        )
      else
        p
      end

    # quái / đối thủ gục vì độc hoặc phản sát thương (đánh người) trong lượt
    q = p.battle.monster.hp <= 0 && mirror_revive(p)

    cond do
      q -> tick_round(q)
      p.battle.monster.hp <= 0 -> win(p)
      true -> round_end_player(p)
    end
  end

  defp round_end_player(p) do
    pdots = p |> effects(:player) |> Enum.filter(&(&1.id in @dots))
    pdot = pdots |> Enum.map(& &1.power) |> Enum.sum()

    p =
      if pdot > 0 do
        p = %{p | hp: max(0, p.hp - pdot)}

        log(p, "Bạn mất #{pdot} máu vì #{effect_list(pdots)}.", "bad", %{
          who: "me",
          name: p.name,
          dot: effect_list(pdots),
          dmg: pdot,
          left: p.hp
        })
      else
        p
      end

    p = if p.hp <= 0, do: survive(p, derived(p)), else: p
    if p.hp <= 0, do: lose(p), else: tick_round(p)
  end

  # ---------- Đánh người (DECISIONS "Cân bằng đánh người", RULES.pvp) ----------
  @doc "Tỉ lệ chí mạng khi đánh người: thu nhỏ theo tỉ lệ (không chặn trần)."
  def pvp_crit(c), do: c * @pvp.crit_rate_mult

  @doc "Hệ số chí mạng khi đánh người: phần cộng thêm trên ×1 thu nhỏ theo tỉ lệ."
  def pvp_crit_mult(cm), do: 1 + (cm - 1) * @pvp.crit_bonus_mult

  def pvp_rules, do: @pvp

  # bảng hệ số lớp theo số lần chuyển sinh: [{mốc, %{"dk" => hệ số, …}}] tăng dần; Đấu trường có bảng riêng
  # (`class_taken_arena_by_rebirth`, luật khác đồ sát: đối thủ máy, đánh cùng lượt), không có thì dùng bảng đồ sát
  taken_rows = fn tab ->
    (tab || %{})
    |> Enum.map(fn {r, row} ->
      {String.to_integer(to_string(r)), Map.new(row, fn {c, v} -> {to_string(c), v} end)}
    end)
    |> Enum.sort()
  end

  @taken_rows taken_rows.(@pvp[:class_taken_by_rebirth])
  @taken_rows_arena taken_rows.(
                      @pvp[:class_taken_arena_by_rebirth] || @pvp[:class_taken_by_rebirth]
                    )

  @doc """
  Hệ số sát thương lên người lớp `cls`, `rebirths` lần chuyển sinh, khi đánh người: `dmg_mult` ×
  `class_taken_by_rebirth[mốc][lớp]` (cân bằng lớp theo mốc; quá bảng thì dùng dòng cuối); `arena?`: Đấu trường dùng
  `class_taken_arena_by_rebirth`.
  """
  def pvp_taken(cls, rebirths \\ 0, arena? \\ false),
    do: @pvp.dmg_mult * ((cls && class_taken(cls, rebirths || 0, arena? == true)) || 1)

  defp class_taken(cls, rb, arena?) do
    # script cân bằng (scripts/pvp/balance.exs) đè hệ số lớp lúc chạy; server không đặt nên luôn dùng rules.json
    case :persistent_term.get({__MODULE__, :class_taken}, nil) do
      nil ->
        row =
          Enum.reduce(if(arena?, do: @taken_rows_arena, else: @taken_rows), nil, fn {r, row},
                                                                                    acc ->
            if r <= rb or acc == nil, do: row, else: acc
          end)

        row && row[cls]

      tab ->
        Enum.find_value(tab, fn {c, v} -> to_string(c) == cls && v end)
    end
  end

  # ---------- Đánh người theo lượt: hiệu ứng chéo (DECISIONS "Đồ sát: hiệu ứng chéo") ----------
  # Đồ sát: mỗi bên đánh bản sao chỉ số của bên kia trong trận của mình, nên hiệu ứng chỉ nằm ở trận của
  # người gây ra. Các hàm dưới chuyển chúng sang người kia: choáng / suy yếu / độc mình đặt lên bản sao thành hiệu ứng
  # trên người bị đánh; sát thương vào người bị đánh đi qua thủ thế, thú che chắn, khiên, bất tử, Long Vương của họ.
  @pvp_debuffs ~w(stun weaken) ++ @dots

  @doc "Trạng thái trận của `p` mà người kia cần biết / sửa (hiệu ứng trên mình, lượt, kháng choáng, Long Vương đã cứu)."
  def pvp_fx(%{battle: b} = p) do
    %{
      effects: effects(p, :player),
      turn: b.turn,
      pstun_free: b[:pstun_free] || 0,
      pet_revived: b[:pet_revived] || false
    }
  end

  @doc "Ghi lại trạng thái `fx` (từ `pvp_fx/1`, có thể đã bị người kia sửa) vào trận của `p`."
  def pvp_put_fx(p, nil), do: p

  def pvp_put_fx(p, fx) do
    p
    |> set_effects(:player, fx.effects)
    |> put_in([:battle, :pstun_free], fx.pstun_free)
    |> put_in([:battle, :pet_revived], fx.pet_revived)
  end

  @doc "Người bị đánh dựng từ nhân vật `char` (đồ, thú cưng), máu `hp` và trạng thái `fx` (nil: đầu trận)."
  def pvp_victim(char, fx, hp) do
    b = %{
      log: [],
      turn: (fx && fx.turn) || 0,
      effects: %{player: [], monster: []},
      monster: %{pvp: true}
    }

    pvp_put_fx(%{char | hp: hp, battle: b}, fx)
  end

  @doc """
  Trước lượt của người đánh `p`: bản sao người bị đánh `foe` né thêm theo buff ảnh bộ của họ (trần như né của người),
  và kháng choáng nếu họ vừa thoát choáng.
  """
  def pvp_aim(p, foe) do
    m = p.battle.monster
    base = m[:base_dodge] || m.dodge
    evade = power(foe, :player, "evade")

    dodge =
      if evade > 0, do: max(base, min(@combat.dodge.max_with_buff, base + evade)), else: base

    immune? = foe.battle.turn + 1 < (foe.battle[:pstun_free] || 0)

    p
    |> put_in([:battle, :monster], Map.merge(m, %{dodge: dodge, base_dodge: base}))
    |> put_in([:battle, :stun_free], if(immune?, do: p.battle.turn + 2, else: 0))
  end

  @doc "Thêm một dòng nhật ký trận cho `p` (dùng bên ngoài Engine, vd. đồ sát ghi dòng đỡ đòn của người bị đánh)."
  def add_log(p, text, kind), do: log(p, text, kind)

  # Hồi máu theo % máu tối đa từ kỹ năng / thú cưng: đánh người × `RULES.pvp.heal_mult` (sát thương lên người × dmg_mult
  # nên hồi máu không giảm thì quá mạnh; DECISIONS "Đánh người: hồi máu kỹ năng"). Hút máu tính theo sát thương nên giữ nguyên.
  defp pvp_heal(%{battle: %{monster: %{pvp: pvp}}}, n) when pvp not in [nil, false],
    do: round(n * (@pvp[:heal_mult] || 1))

  defp pvp_heal(_p, n), do: round(n)

  @doc "Người đánh `p` có đang bị choáng (lượt này mất lượt) không."
  def stunned?(p), do: effect(p, :player, "stun") != nil

  @doc """
  Tách khỏi trận của `p` các hiệu ứng `p` vừa đặt lên bản sao đối thủ (choáng, suy yếu, độc / bỏng / chảy máu) để
  `pvp_receive/2` đặt sang người kia. Phá giáp giữ lại (tính trong đòn của chính `p`). Trả `{p, hiệu_ứng}`.
  """
  def pvp_take_debuffs(p) do
    {out, keep} = Enum.split_with(effects(p, :monster), &(&1.id in @pvp_debuffs))
    %{} = m = p.battle.monster

    out =
      Enum.map(out, fn
        %{id: "stun"} = e ->
          %{e | turns: 1, power: 0}

        %{id: id} = e when id in @dots ->
          %{e | power: max(1, round(e.power * pvp_taken(m[:cls], m[:rebirths], m[:arena])))}

        e ->
          e
      end)

    {set_effects(p, :monster, keep), out}
  end

  @doc "Người bị đánh `p` nhận hiệu ứng `list` (từ `pvp_take_debuffs/1`); đang kháng choáng thì bỏ choáng."
  def pvp_receive(p, list) do
    Enum.reduce(list, p, fn
      %{id: "stun"}, p ->
        cond do
          p.battle.turn + 1 < (p.battle[:pstun_free] || 0) -> p
          ward?(p) -> log(p, "🐉 Long Uy: #{p.name} kháng được choáng.", "good")
          true -> put_effect(p, :player, "stun", 1, 0)
        end

      e, p ->
        if ward?(p),
          do:
            log(
              p,
              "🐉 Long Uy: #{p.name} kháng được #{@effect_names[e.id] || "hiệu ứng"}.",
              "good"
            ),
          else: put_effect(p, :player, e.id, e.turns, e.power)
    end)
  end

  @doc """
  Người bị đánh `p` nhận `dmg` sát thương (bên đánh đã tính đủ công, thủ, chí mạng, giảm sát thương của cánh / Excellent):
  thủ thế, thú che chắn, khiên, rồi Bất Tử của chính họ. Máu có thể âm (không được cứu).
  Trả `{p, sát_thương_thật}`; dòng nhật ký (góc nhìn người bị đánh) ghi vào trận của `p`.
  """
  def pvp_defend(p, dmg) when dmg <= 0, do: {p, 0}

  def pvp_defend(p, dmg) do
    dmg = max(1, round(dmg * (1 - power(p, :player, "guard")) * (1 - pet_guard(p))))
    {dmg, p} = absorb_shield(p, dmg)
    p = %{p | hp: p.hp - dmg}
    {if(p.hp <= 0, do: survive(p, derived(p)), else: p), dmg}
  end

  @doc "Đầu lượt của mình (đánh người theo lượt): độc / bỏng / chảy máu đối thủ đặt lên mình trừ máu."
  def pvp_turn_start(p) do
    pdots = p |> effects(:player) |> Enum.filter(&(&1.id in @dots))
    pdot = pdots |> Enum.map(& &1.power) |> Enum.sum()

    if pdot > 0 do
      p =
        %{p | hp: p.hp - pdot}
        |> then(
          &log(&1, "Bạn mất #{pdot} máu vì #{effect_list(pdots)}.", "bad", %{
            who: "me",
            name: &1.name,
            dot: effect_list(pdots),
            dmg: pdot,
            left: max(&1.hp, 0)
          })
        )

      if p.hp <= 0, do: survive(p, derived(p)), else: p
    else
      p
    end
  end

  # Gây choáng cho quái / đối thủ; đối thủ là người vừa hết choáng thì kháng `stun_immune` lượt.
  # Đánh người: tỉ lệ choáng × `RULES.pvp.stun_mult` (DECISIONS "Đồ sát: hiệu ứng chéo").
  defp stun_monster(p, text) do
    b = p.battle

    cond do
      # đang chờ mất lượt (đấu trường: choáng có hiệu lực từ lượt sau) thì giữ choáng cũ
      b.monster[:pvp] && effect(p, :monster, "stun") ->
        p

      b.monster[:pvp] && b.turn < (b[:stun_free] || 0) ->
        log(p, "#{b.monster.name} vừa thoát choáng, kháng được.", "info")

      b.monster[:pvp] && not chance(@pvp[:stun_mult] || 1) ->
        log(p, "#{b.monster.name} không bị choáng.", "info")

      true ->
        p |> put_effect(:monster, "stun", 1, b.turn) |> log(text, "good")
    end
  end

  # Đối thủ đấu trường chạy như người: buff thủ, thú che chắn của đối thủ giảm đòn của mình; phản sát thương (Excellent)
  # của đối thủ đánh lại mình, hạ được mình như đánh người thật (Bất Tử của mình vẫn cứu)
  defp mirror_guard(%{battle: %{mirror: %{} = mi}} = p, dmg) do
    dmg = round(dmg * (1 - power(mi, :player, "guard")) * (1 - pet_guard(mi)))

    # khiên của đối thủ máy đỡ đòn như khiên của mình (trước đây bỏ sót: chỉ người thách đấu được khiên đỡ)
    {dmg, mi2} = absorb_shield(mi, dmg)

    p =
      if mi2 == mi,
        do: p,
        else:
          p
          |> put_in([:battle, :mirror], mi2)
          |> log(
            "🛡 Khiên của #{p.battle.monster.name} đỡ #{shield_used(mi, mi2)} sát thương.",
            "info"
          )

    back = min(round(dmg * derived(mi).excReflect), p.hp)

    p =
      if back > 0,
        do:
          %{p | hp: p.hp - back}
          |> log("#{p.name}, bị phản #{back} sát thương.", "bad", %{
            who: "me",
            name: p.name,
            reflect: back
          })
          |> then(&if(&1.hp <= 0, do: survive(&1, derived(&1)), else: &1)),
        else: p

    {dmg, p}
  end

  # bản sao người (đồ sát, đấu trường khi mất `mirror`): phản sát thương (Excellent) của người đó đánh lại mình;
  # ở đây phản đòn không hạ gục (còn ít nhất 1 máu) vì trận do Slay chốt theo máu hai bên
  defp mirror_guard(%{battle: %{monster: %{pvp: pvp, reflect: r}}} = p, dmg)
       when pvp != nil and is_number(r) and r > 0 do
    back = min(round(dmg * r), p.hp - 1)

    p =
      if back > 0,
        do:
          %{p | hp: p.hp - back}
          |> log("#{p.name}, bị phản #{back} sát thương.", "bad", %{
            who: "me",
            name: p.name,
            reflect: back
          }),
        else: p

    {dmg, p}
  end

  defp mirror_guard(p, dmg), do: {dmg, p}

  # Trận của đối thủ máy chạy `live`: hiệu ứng đếm lượt ngay sau đòn của nó, nên buff vừa đặt (khiên, thủ thế, né…)
  # mất một lượt trước khi kịp đỡ đòn nào. Hiệu ứng của mình đếm ở cuối vòng (sau đòn của đối thủ). Bù 1 lượt cho hiệu
  # ứng đối thủ máy vừa đặt / làm mới trong lượt này để hai bên được đỡ cùng số đòn.
  defp fresh_buffs(mi, before) do
    old = Map.new(before, &{&1.id, &1.turns})

    list =
      Enum.map(effects(mi, :player), fn e ->
        if e.turns >= (old[e.id] || 0), do: %{e | turns: e.turns + 1}, else: e
      end)

    set_effects(mi, :player, list)
  end

  defp shield_used(a, b) do
    pool = fn x -> (effect(x, :player, "shield") || %{power: 0}).power end
    pool.(a) - pool.(b)
  end

  # Đấu trường: đòn trong lượt đầu của người thách đấu × `RULES.arena.first_strike_mult` (đòn mở màn, như đồ sát)
  defp arena_opening(%{battle: %{mirror: %{}, turn: 1}} = p, dmg) when @arena_first < 1 do
    dmg2 = round(dmg * @arena_first)
    {dmg2, log(p, "⚔ Đòn mở màn chỉ gây ×#{@arena_first} sát thương.", "info")}
  end

  defp arena_opening(p, dmg), do: {dmg, p}

  @doc "Thời tiết của trận (`battle.wx`, Session ghi lúc bắt đầu): kỹ năng cùng hệ × (1 + pct)."
  def weather_mult(%{battle: %{wx: %{element: el, pct: pct}}}, %{} = skill),
    do: if(skill[:element] == el, do: 1 + pct, else: 1)

  def weather_mult(_p, _skill), do: 1

  defp stun_cooled(%{battle: %{monster: %{pvp: pvp}}} = p) when pvp != nil,
    do: put_in(p, [:battle, :stun_free], p.battle.turn + 1 + @pvp.stun_immune)

  defp stun_cooled(p), do: p

  @doc """
  Lệnh tự đánh khi đánh người (đồ sát hết giờ / bị choáng): kỹ năng mạnh nhất đang dùng được (hết hồi chiêu,
  đủ MP), không có thì đánh thường. Trả `{"skill", id}` hoặc `{"attack", nil}`.
  """
  def auto_strike(p) do
    p
    |> skills()
    |> Enum.filter(&(cooldown(p, &1.id) == 0 and mp(p) >= skill_mp(p, &1)))
    |> Enum.max_by(&skill_power/1, fn -> nil end)
    |> case do
      nil -> {"attack", nil}
      k -> {"skill", k.id}
    end
  end

  defp skill_power(%{floor: _} = k), do: k[:mult] || 1

  defp skill_power(k) do
    e = @effects[String.to_existing_atom(k[:effect] || k.id)] || %{}
    (e[:mult] || 1) * (((k[:hits] || 1) > 1 && 1.05) || 1)
  end

  # Giảm số lượt hiệu ứng và hồi chiêu.
  defp tick_round(p) do
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

  @doc "Kết thúc trận đang đánh bằng thua (gục ngã: mất vàng, máu còn một phần, như chết thường)."
  def finish_lose(%{battle: %{over: false}} = p), do: lose(p)
  def finish_lose(p), do: {ok(), p}

  defp win(p) do
    m = p.battle.monster
    # thú cưng (vàng, kinh nghiệm) và nhà trang trí (kinh nghiệm) cộng thêm
    event = if m[:pvp], do: nil, else: Events.current()
    exc = Gear.exc_stats(effective(p))

    gold =
      round(
        m.gold *
          (1 + Pets.bonus(p, :gold) + Crafting.food_bonus(p, :gold) + Blessing.bonus(p, :gold) +
             exc.gold_pct)
      )

    # quái thường thấp hơn mình quá nhiều cấp thì bớt EXP (không áp trùm, tháp, trùm thế giới, đấu trường)
    normal? = not m.boss and !m[:world] and !m[:pvp] and !m[:tower]
    xf = if normal?, do: xp_factor(p.level, m.level), else: 1

    xp =
      round(
        m.xp * xf *
          (1 + Pets.bonus(p, :xp) + Crafting.food_bonus(p, :xp) +
             Blessing.bonus(p, :xp) +
             Events.xp_bonus(event))
      )

    p = %{p | kills: p.kills + 1, gold: p.gold + gold}
    reward = %{xp: xp, gold: gold, items: [], levels: 0}
    # Excellent: hồi máu / MP khi hạ quái (phần của tối đa)
    p = exc_on_kill(p, exc)

    p =
      if m[:world],
        do: log(p, "🏆 #{m.name} gục ngã dưới đòn của bạn!", "win"),
        else:
          log(
            p,
            if(xf < 1,
              do:
                "🏆 Bạn đã hạ #{m.name}! +#{xp} kinh nghiệm (−#{round((1 - xf) * 100)}% vì cao hơn quái #{p.level - m.level} cấp), +#{gold} vàng.",
              else: "🏆 Bạn đã hạ #{m.name}! +#{xp} kinh nghiệm, +#{gold} vàng."
            ),
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
    {p, reward} = ds_ticket_drop(p, m, reward)
    {p, reward} = bc_ticket_drop(p, m, reward)
    {p, reward} = cc_ticket_drop(p, m, reward)
    {p, reward} = raid_drop(p, m, reward)
    {p, reward} = kundun_mark_drop(p, m, reward)
    {p, reward} = bi_kip_drop(p, m, reward)
    {p, reward} = event_drop(p, m, event, reward)

    {p, reward} =
      if m.boss and m.id not in p.bosses, do: first_boss_kill(p, m, reward), else: {p, reward}

    {p, reward} = boss_daily(p, m, reward)

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

    p = if pet_up, do: log(p, "🐾 #{Pets.name(p)} lên cấp #{pet_up}!", "win"), else: p

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

    # Long Ân: dắt Long Vương thì quái rơi ngọc thêm (DECISIONS "Long Vương: thần thú độc nhất")
    c = c * (1 + Pets.trait(p, :jewel))

    if c > 0 and chance(c) do
      id = pick_jewel()
      p = p |> add_item(id) |> log("💎 Nhặt được #{Data.item(id).name}!", "win")
      {p, %{reward | items: reward.items ++ [id]}}
    else
      {p, reward}
    end
  end

  # Mảnh vé Quảng Trường Quỷ (Phase 18 M1; B-18: rơi mảnh, ghép vé ở Máy Hỗn Nguyên): quái thường cấp cao thỉnh thoảng rơi
  defp ds_ticket_drop(p, m, reward) do
    c = HacLong.Game.DevilSquare.ticket_chance(m)

    if c > 0 and chance(c) do
      id = HacLong.Game.DevilSquare.ticket_part()
      p = p |> add_item(id) |> log("🎟 Nhặt được #{Data.item(id).name}!", "win")
      {p, %{reward | items: reward.items ++ [id]}}
    else
      {p, reward}
    end
  end

  # Mảnh vé Lâu Đài (Phase 18 M2; B-18)
  defp bc_ticket_drop(p, m, reward) do
    c = HacLong.Game.BloodCastle.ticket_chance(m)

    if c > 0 and chance(c) do
      id = HacLong.Game.BloodCastle.ticket_part()
      p = p |> add_item(id) |> log("🎟 Nhặt được #{Data.item(id).name}!", "win")
      {p, %{reward | items: reward.items ++ [id]}}
    else
      {p, reward}
    end
  end

  # Vé Hỗn Chiến Thành (B-19): quái thường cấp ≥ `ticket_drop.min_level` thỉnh thoảng rơi
  defp cc_ticket_drop(p, m, reward) do
    c = HacLong.ChaosCastle.ticket_chance(m)

    if c > 0 and chance(c) do
      id = HacLong.ChaosCastle.ticket()
      p = p |> add_item(id) |> log("🎟 Nhặt được #{Data.item(id).name}!", "win")
      {p, %{reward | items: reward.items ++ [id]}}
    else
      {p, reward}
    end
  end

  # Dấu Ấn Kundun (B-21): quái thường cấp ≥ `kalima.mark_drop.min_level` thỉnh thoảng rơi
  # Bí Kíp (đột phá thông thạo kỹ năng): trùm vùng, quái tinh anh, trùm thế giới; lần đầu hạ trùm vùng / chúa tể chắc
  # chắn (`RULES.skill_mastery.drop`)
  defp bi_kip_drop(p, m, reward) do
    dr = Mastery.rules().drop

    # lần đầu hạ trùm vùng (chưa ghi `bosses`) / chúa tể vùng chuyển sinh (chưa có trong Sổ quái): chắc chắn
    lord? = m[:lord] || (Data.side_monster(m.id) || %{})[:lord]

    first =
      cond do
        m[:pvp] -> 0
        m.boss and m.id not in p.bosses -> dr.first_boss
        lord? && Bestiary.count(p, m.id) == 0 -> dr.first_boss
        true -> 0
      end

    c =
      cond do
        m[:pvp] -> 0
        m[:world] -> dr.world
        m.boss -> dr.boss
        m[:elite] -> dr.elite
        true -> 0
      end

    n = if(first > 0, do: first, else: if(c > 0 and chance(c), do: 1, else: 0))

    if n > 0 do
      id = Mastery.rules().item

      p =
        p
        |> add_item(id, n)
        |> log("📕 Nhặt được #{Data.item(id).name}#{if n > 1, do: " ×#{n}", else: ""}!", "win")

      {p, %{reward | items: reward.items ++ List.duplicate(id, n)}}
    else
      {p, reward}
    end
  end

  defp kundun_mark_drop(p, m, reward) do
    c = HacLong.Game.Kalima.mark_chance(m)

    if c > 0 and chance(c) do
      id = HacLong.Game.Kalima.mark()
      p = p |> add_item(id) |> log("🎟 Nhặt được #{Data.item(id).name}!", "win")
      {p, %{reward | items: reward.items ++ [id]}}
    else
      {p, reward}
    end
  end

  # Xâm lăng (B-20): con đầu đàn rơi thêm đồ theo `RULES.raids.<loại>.drops`
  defp raid_drop(p, %{raid: key, boss: true}, reward) when is_binary(key) do
    Enum.reduce(HacLong.Raids.drops(key), {p, reward}, fn {id, c}, {p, reward} ->
      if chance(c) do
        {p |> add_item(id) |> log("💎 Nhặt được #{Data.item(id).name}!", "win"),
         %{reward | items: reward.items ++ [id]}}
      else
        {p, reward}
      end
    end)
  end

  defp raid_drop(p, _m, reward), do: {p, reward}

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
         %{} = g <-
           m.level
           |> Gear.roll(Gear.weights(), nil, if(@loot_own_class, do: p.cls))
           |> Gear.excellent(Gear.exc_chance(m))
           |> Gear.luck_skill(m)
           |> Gear.ancient(m) do
      label = Gear.label(g)
      keep = HacLong.Game.AutoHunt.filter_keep(p)

      # Menu → Cài đặt "Tự hủy đồ rơi": món không thuộc loại giữ lại thì bỏ luôn, không vào túi
      case if(keep && not HacLong.Game.AutoHunt.good?(p, Gear.resolve(g), keep),
             do: :trash,
             else: Gear.add(p, g)
           ) do
        :trash ->
          {log(p, "🗑 Tự hủy #{label} (không thuộc loại giữ lại).", "info"), reward}

        {p, :kept} ->
          # `gear_ids`: món vào túi, client cho bấm xem / hủy ngay trên bảng kết quả
          {log(p, "🎁 Nhặt được #{label}!", "win"),
           Map.merge(reward, %{gear: [label], gear_ids: [g.uid]})}

        {p, :mailed} ->
          {log(p, "🎁 Nhặt được #{label}, túi trang bị đầy nên gửi vào Hộp thư.", "good"),
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

    # lần đầu hạ trùm vùng: chắc chắn một món đồ có dòng cộng thêm đúng lớp (danh hiệu ở thành tựu)
    {p, reward} =
      if is_integer(p.battle.zone),
        do: boss_gear(p, m, reward),
        else: {p, reward}

    p =
      if m.final,
        do: %{p | victory: true} |> log("Hắc Long đã gục ngã. Vùng đất được giải phóng!", "win"),
        else: log(p, "🏆 Lần đầu hạ #{m.name}! Nhận danh hiệu Diệt #{m.name}.", "win")

    {p, reward}
  end

  defp boss_gear(p, m, reward) do
    # vài lần thử: lớp nào cũng có ít nhất vũ khí / giáp hợp lớp
    g =
      Enum.find_value(1..8, fn _ ->
        m.level
        |> Gear.roll(@boss_weights, nil, p.cls)
        |> Gear.excellent(Gear.exc_chance(m))
        |> Gear.luck_skill(m)
        |> Gear.ancient(m)
      end)

    case g do
      nil ->
        {p, reward}

      g ->
        label = Gear.label(g)

        case Gear.add(p, g) do
          {p, :kept} ->
            {log(p, "🎁 #{m.name} để lại #{label}!", "win"),
             reward
             |> Map.update(:gear, [label], &(&1 ++ [label]))
             |> Map.update(:gear_ids, [g.uid], &(&1 ++ [g.uid]))}

          {p, :mailed} ->
            {log(p, "🎁 #{m.name} để lại #{label}, túi trang bị đầy nên gửi vào Hộp thư.", "good"),
             Map.update(reward, :gear, [label], &(&1 ++ [label]))}
        end
    end
  end

  # Trùm vùng hạ lại được: lần đầu mỗi ngày (giờ Việt Nam) cho ngọc theo `RULES.boss_rewards.daily`.
  defp boss_daily(%{battle: %{zone: zi}, daily: %{} = d} = p, %{boss: true} = m, reward)
       when is_integer(zi) do
    done = Map.get(d, :bosses) || []

    case m.id not in done &&
           @boss_rw.daily |> Enum.filter(&(&1.from_zone <= zi)) |> List.last() do
      %{item: item, n: n} ->
        p = %{p | daily: Map.put(d, :bosses, done ++ [m.id])} |> add_item(item, n)
        p = log(p, "🎖 Thưởng hạ #{m.name} hôm nay: #{Data.item(item).name} ×#{n}.", "win")
        {p, %{reward | items: reward.items ++ [item]}}

      _ ->
        {p, reward}
    end
  end

  defp boss_daily(p, _m, reward), do: {p, reward}

  defp lose(p) do
    # Hỗn Chiến Thành (B-19): gục là bị loại, không mất vàng
    event? = (m = p[:pos] && HacLong.World.Maps.get(p.pos.map)) && m[:event] != nil
    lost = if event?, do: 0, else: floor(p.gold * @char.death_gold_loss)
    p = %{p | gold: p.gold - lost, deaths: p.deaths + 1}

    p =
      if event?,
        do: log(p, "💀 Bạn đã gục ngã và bị loại khỏi sự kiện. Không mất vàng; về Làng.", "bad"),
        else: log(p, "💀 Bạn đã gục ngã... Mất #{lost} vàng. Dân làng đưa bạn về nhà trọ.", "bad")

    p = %{p | hp: round(derived(p).maxHp * @char.death_hp)}
    finish(p, "lose")
  end

  defp finish(p, result) do
    p =
      update_in(p.battle, &%{&1 | over: true, result: result})
      |> Crafting.tick()
      |> Blessing.tick()

    {%{ok: true, result: result}, p}
  end

  def leave_battle(%{battle: %{over: true}} = p), do: {ok(), %{p | battle: nil}}
  def leave_battle(%{battle: nil} = p), do: {ok(), p}
  def leave_battle(p), do: {err("Trận đấu chưa kết thúc."), p}

  def gain_xp(p, xp), do: level_up(%{p | xp: p.xp + xp}, 0)

  defp level_up(p, levels) do
    if p.level < @max_level and p.xp >= xp_need(p) do
      %{
        p
        | xp: p.xp - xp_need(p),
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
      # thân theo lớp (Tiên Nữ: thân nữ), không có thì thân nam mặc định ở doll.js
      body: Data.class(p.cls)[:body],
      weapon: doll.(p.equip.weapon),
      armor: doll.(p.equip.armor),
      shield: doll.(p.equip.shield),
      wing: wing_look(p),
      pet: Map.get(p, :pet),
      aura: aura(p)
    }
  end

  @doc """
  Hào quang theo đồ (chỉ để vẽ, docs/FX_PLAN.md đợt 3, giống MU): mặc đủ bộ giáp (`set_bonus/1`: đủ món của bộ cho lớp
  này) và mọi món của bộ đều từ +7 → 7 (xanh dương), +9 → 9 (vàng), +11 → 11 (cam đỏ); không thì 0.
  """
  def aura(p) do
    sb = set_bonus(p)

    if sb.need > 0 and sb.have >= sb.need do
      lv =
        for {_slot, id} <- p.equip,
            id,
            it = Gear.item(p, id),
            it[:set] == sb.name and it.tier == sb.tier,
            do: upgrade_level(p, id)

      lv = Enum.min(lv, fn -> 0 end)
      Enum.find([11, 9, 7], 0, &(lv >= &1))
    else
      0
    end
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
  # Ép kiểu MU theo bảng `UPGRADE` (DECISIONS B-13): +1..+6 Ước Nguyện, +7..+9 Tâm Linh, +10/+11 Máy Hỗn Nguyên.

  def max_upgrade, do: Data.upgrade().max

  @doc "Cấp tính kiểu cũ: từ `double_from` (+10) mỗi cấp tính gấp đôi (chỉ còn dùng khi bước ép không có `eff`)."
  def effective_level(l), do: l + max(0, l - Data.upgrade().double_from + 1)

  @doc """
  Cấp tính chỉ số đồ đã ép +`l` (`eff` của bước trong `UPGRADE`): chỉ số cộng = eff × `bonus_pct` × chỉ số gốc.
  +1..+6 tăng đều, +7 → +11 tăng mạnh dần (DECISIONS "Ép +7 → +11 chênh lệch lớn").
  """
  def upgrade_eff(0), do: 0
  def upgrade_eff(l), do: (Data.upgrade_step(l) || %{})[:eff] || effective_level(l)

  defp upgrades(p), do: Map.get(p, :upgrades) || %{}

  def upgrade_level(p, id), do: Map.get(upgrades(p), id, 0)

  @doc "Tấn công/phòng thủ cộng thêm: mỗi cấp +8% chỉ số gốc của món đồ (ít nhất +1)."
  def upgrade_bonus(p, id) do
    case {upgrade_level(p, id), Gear.item(p, id)} do
      {0, _} ->
        0

      {_, nil} ->
        0

      # B-28: món chỉ có máu (nhẫn máu): ép cộng máu (`upgrade_hp/2`), không cộng thủ
      {l, it} ->
        if hp_only?(it),
          do: 0,
          else: round(upgrade_eff(l) * max(1, round((it[:atk] || it[:def] || 0) * @up.bonus_pct)))
    end
  end

  defp hp_only?(it),
    do: is_number(it[:hp]) and not is_number(it[:atk]) and not is_number(it[:def])

  @doc "Máu cộng thêm khi ép món chỉ có máu (nhẫn máu, B-28): mỗi cấp hiệu dụng + bonus_pct máu gốc."
  def upgrade_hp(p, id) do
    case {upgrade_level(p, id), Gear.item(p, id)} do
      {l, %{hp: hp} = it} when l > 0 and is_number(hp) ->
        if hp_only?(it), do: round(upgrade_eff(l) * max(1, round(hp * @up.bonus_pct))), else: 0

      _ ->
        0
    end
  end

  @doc """
  Giá nâng món đồ (id đồ thường hoặc thông tin món đồ) từ cấp `level` lên cấp tiếp theo:
  `%{gold, items, rate, fail, at}` hoặc `nil` nếu đã tối đa. Ép kiểu MU (bảng `UPGRADE`,
  DECISIONS B-13):

  - +1 → +6: một Ngọc Ước Nguyện, luôn thành công.
  - +7 → +9: một Ngọc Tâm Linh, tỉ lệ `rate`; thất bại về +0 (`"reset"`).
  - +10, +11: ở Máy Hỗn Nguyên (`at: "chaos"`), Hỗn Nguyên + Ước Nguyện + Tâm Linh; thất bại vỡ đồ.

  May mắn (Phase 15d) cộng tỉ lệ các bước không chắc chắn. Ngọc và vàng mất cả khi thất bại.
  """
  def upgrade_cost(id, level) when is_binary(id), do: upgrade_cost(Data.item(id), level)

  def upgrade_cost(it, level) do
    n = level + 1

    case Data.upgrade_step(n) do
      nil ->
        nil

      step ->
        %{
          gold: round(max(it.price, @up.cost_min_price) * @up.cost_pct * n),
          items: step.items,
          rate:
            Gear.luck_rate(it, step.rate, step[:luck] || Gear.luck_skill_rules().luck_upgrade),
          fail: step.fail,
          at: step.at
        }
    end
  end

  @doc """
  Ép món đang mặc ở ô `slot`. Bước có thể vỡ đồ thì phải gửi `confirm` (client hỏi lại trước).
  `at`: nơi ép (`"smith"` Thợ Rèn, `"chaos"` Máy Hỗn Nguyên), phải đúng `at` của bước. Kết quả có
  `upgrade: %{result: "success" | "down" | "reset" | "destroy" | "fail", level}`; ép thành công
  từ `announce_from` thì kèm `announce` (Session đưa lên kênh chat hệ thống).
  """
  def upgrade(p, target, confirm \\ false, at \\ "smith") do
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
        {err("Túi trang bị đầy (#{Gear.max_bag()} món): món ép riêng cần một chỗ."), p}

      p.battle ->
        {err("Đang trong trận."), p}

      cost == nil ->
        {err("#{it.name} đã nâng cấp tối đa."), p}

      cost.at != at ->
        {err(
           if cost.at == "chaos",
             do: "Ép lên +#{level + 1} ở Lão Hỗn Nguyên (Máy Hỗn Nguyên).",
             else: "Ép lên +#{level + 1} ở Thợ Rèn."
         ), p}

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
    if it && it.slot in @item_slots && Map.get(p.inv, id, 0) > 0, do: {id, nil}, else: {nil, nil}
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
  vũ khí +`line_value/1` tấn công, giáp / khiên / cánh +`line_value/1` phòng thủ, tối đa `max_lines`. Tỉ lệ `rate`;
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
        {err("Túi trang bị đầy (#{Gear.max_bag()} món): món ép riêng cần một chỗ."), p}

      true ->
        hp_ratio = p.hp / derived(p).maxHp
        {p, uid} = forge_instance(p, id, slot)
        p = take_item(p, l.jewel)
        stat = if it.slot == "weapon", do: "tấn công", else: "phòng thủ"

        {r, p} =
          if chance(l.rate) do
            {ok(
               "💚 #{it.name}: thêm dòng +#{line_value(it)} #{stat} (#{lines + 1}/#{l.max_lines})."
             )
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

  @doc "Tấn công / phòng thủ cộng thêm từ dòng cộng thêm (Ngọc Sinh Mệnh) của món `id`."
  def life_bonus(p, id) do
    if Gear.instance?(id),
      do: ((Gear.find(p, id) || %{})[:opt] || 0) * line_value(Gear.item(p, id)),
      else: 0
  end

  @doc """
  Giá trị một dòng cộng thêm của món `it`: `per_line_pct` × công (vũ khí, dây chuyền) hoặc thủ gốc, ít nhất `per_line`
  (từ "Cân bằng cuối game": dòng cộng thêm theo bậc đồ thay vì +4 phẳng).
  """
  def line_value(nil), do: @up.life.per_line

  def line_value(it),
    do: max(@up.life.per_line, round((it[:atk] || it[:def] || 0) * @up.life.per_line_pct))

  @doc """
  Vứt đồ: `n` món đồ thường `id`, hoặc món đồ hiếm `id` (uid). Không vứt đồ đang mặc, đang khóa,
  đang cất trong tủ.
  """
  def discard(p, id, n \\ 1)

  # trận đã xong (bảng kết quả) thì vứt được: hủy đồ vừa nhặt ngay trên bảng
  def discard(%{battle: %{over: over}} = p, _id, _n) when over != true,
    do: {err("Đang trong trận."), p}

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
    case bag_uid(p, id) do
      "#" <> _ = uid -> discard(p, uid, n)
      id -> discard_stack(p, id, n)
    end
  end

  defp discard_stack(p, id, n) do
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

      cost.fail == "reset" ->
        p = put_upgrade(p, uid, 0)

        {ok("💥 Ép thất bại, #{it.name} về +0.")
         |> Map.put(:upgrade, %{result: "reset", level: 0}), p}

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
    %{p | equip: Map.put(p.equip, slot, Data.starters(p.cls)[slot])}
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
  Phase 15b: đổi đồ cũ đã thay (`Data.legacy?/1`) sang đồ Item.txt cùng ô, cùng bậc, đúng lớp
  (`Data.replacement/2`) ở mọi chỗ: đang mặc, túi, đồ hiếm (`gear.base`, giữ `uid`, độ hiếm, chỉ số
  cộng, cấp nâng +N, khóa, Ngọc Sinh Mệnh), cấp nâng của đồ thường, Tủ Đồ. Có đổi thì các ô mới
  (mũ / quần / găng / giày) còn trống được phát đồ khởi đầu như nhân vật mới. Không có gì để đổi thì
  trả nguyên `p`. Chạy mỗi lần nạp nhân vật (`Characters.load/1`).
  """
  def migrate_items(p) do
    swap = fn id -> (is_binary(id) && Data.replacement(id, p.cls)) || id end
    gear = Map.get(p, :gear) || []
    storage = Map.get(p, :storage)

    legacy? =
      Enum.any?(Map.values(p.equip), &(&1 && Data.legacy?(&1))) or
        Enum.any?(Map.keys(p.inv), &Data.legacy?/1) or
        Enum.any?(gear, &Data.legacy?(&1.base)) or
        Enum.any?(Map.keys(upgrades(p)), &Data.legacy?/1) or
        (is_map(storage) and Enum.any?(Map.keys(storage.inv), &Data.legacy?/1))

    if legacy? do
      merge = fn m ->
        Enum.reduce(m, %{}, fn {id, n}, acc -> Map.update(acc, swap.(id), n, &(&1 + n)) end)
      end

      equip = Map.new(p.equip, fn {slot, id} -> {slot, swap.(id)} end)

      fresh =
        for {slot, id} <- Data.starters(p.cls), equip[slot] == nil, into: %{}, do: {slot, id}

      p
      |> Map.put(:equip, Map.merge(equip, fresh))
      |> Map.put(:inv, merge.(p.inv))
      |> Map.put(:gear, Enum.map(gear, &%{&1 | base: swap.(&1.base)}))
      |> Map.put(:upgrades, Map.new(upgrades(p), fn {id, n} -> {swap.(id), n} end))
      |> then(
        &if(is_map(storage),
          do: Map.put(&1, :storage, %{storage | inv: merge.(storage.inv)}),
          else: &1
        )
      )
    else
      p
    end
  end

  @doc """
  Dữ liệu cũ (cấp nâng theo loại đồ thường, `upgrades[id]`): tách mỗi món cùng loại (đang mặc và
  trong túi) thành bản riêng giữ nguyên cấp. Chạy lúc nạp nhân vật.
  """
  def split_upgrades(p) do
    Enum.reduce(upgrades(p), p, fn {id, level}, p ->
      it = not Gear.instance?(id) && Data.item(id)

      if it && it.slot in @item_slots && level > 0 do
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
    id = bag_uid(p, id)
    slot = Enum.find(@equip_slots, &(p.equip[String.to_existing_atom(&1)] == id))
    it = Gear.item(p, id)

    cond do
      it == nil or it.slot not in @item_slots ->
        {err("Chỉ khóa được đồ mặc được (vũ khí, giáp, khiên, cánh, nhẫn…)."), p}

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
        {err("Túi trang bị đầy (#{Gear.max_bag()} món), không tách món này ra để khóa được."), p}

      true ->
        g = Gear.plain(id) |> Map.put(:locked, true)
        p = take_item(p, id)
        {ok("🔒 Đã khóa #{it.name}."), Map.put(p, :gear, (Map.get(p, :gear) || []) ++ [g])}
    end
  end

  def lock(p, _id, _on?), do: {err("Không có món này."), p}

  # ---------- Đồ đạc ----------
  @doc """
  Thêm `n` món `id` vào túi. Trang bị (`gear_item?/1`) luôn là từng món riêng trong túi trang bị (đồ trắng, 0 dòng;
  túi đầy thì gửi Hộp thư như đồ rơi), không xếp chồng; món khác (bình, ngọc, nguyên liệu, vé…) xếp chồng trong `inv`.
  """
  def add_item(p, id, n \\ 1) do
    if gear_item?(id),
      do: Enum.reduce(1..n//1, p, fn _, p -> p |> Gear.add(Gear.plain(id)) |> elem(0) end),
      else: %{p | inv: Map.update(p.inv, id, n, &(&1 + n))}
  end

  @doc """
  Lệnh gửi mã loại trang bị (vd. `"item_1_0"`, test / công cụ cũ) mà túi không còn chồng đồ thường loại đó: dùng món
  riêng cùng loại đầu tiên trong túi. Mã khác trả nguyên.
  """
  def bag_uid(p, id) do
    if gear_item?(id) and Map.get(p.inv, id, 0) == 0,
      do: Enum.find_value(Gear.bag(p), id, &(&1.base == id && &1.uid)),
      else: id
  end

  @doc "Món `id` (mã loại, không phải `uid`) là trang bị mặc được: vũ khí, giáp, khiên, cánh, nhẫn, dây chuyền."
  def gear_item?(id) do
    it = is_binary(id) and not Gear.instance?(id) and Data.item(id)
    is_map(it) and it.slot in @item_slots
  end

  @doc """
  Dữ liệu cũ: trang bị còn xếp chồng thành từng món riêng: đang mặc (đồ khởi đầu, đồ mua), trong túi (túi đầy thì
  phần dư gửi Hộp thư qua `mail_out`, không mất món nào), trong Tủ Đồ (thành món cất tủ). Chạy lúc nạp nhân vật và
  tạo nhân vật mới; không có gì để đổi thì trả nguyên `p`.
  """
  def instance_gear(p) do
    p =
      Enum.reduce(@equip_slots, p, fn s, p ->
        slot = String.to_existing_atom(s)
        if gear_item?(p.equip[slot]), do: p |> ensure_instance(slot) |> elem(0), else: p
      end)

    {gear_inv, rest} = Enum.split_with(p.inv, fn {id, _} -> gear_item?(id) end)
    p = Enum.reduce(gear_inv, %{p | inv: Map.new(rest)}, fn {id, n}, p -> add_item(p, id, n) end)

    case Map.get(p, :storage) do
      %{inv: inv} = st ->
        {gear_st, rest} = Enum.split_with(inv, fn {id, _} -> gear_item?(id) end)
        stored = for {id, n} <- gear_st, _ <- 1..n//1, do: Map.put(Gear.plain(id), :stored, true)

        if stored == [],
          do: p,
          else:
            %{p | storage: %{st | inv: Map.new(rest)}}
            |> Map.put(:gear, Gear.list(p) ++ stored)

      _ ->
        p
    end
  end

  def take_item(p, id, n \\ 1) do
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

      not class_ok?(it, p.cls) ->
        {err("#{it.name} không dành cho #{Data.class(p.cls).name}."), p}

      not count_ok?(n) ->
        {err("Số lượng không hợp lệ."), p}

      it[:level] && p.level < it.level ->
        {err("Cần cấp #{it.level}."), p}

      not buy_level_ok?(p, it) ->
        {err("Cần cấp #{it.buy_level} (hoặc đã chuyển sinh) mới mua được #{it.name}."), p}

      p.gold < price(p, id) * n ->
        {err("Không đủ vàng."), p}

      gear_item?(id) and length(Gear.bag(p)) + n > Gear.max_bag() ->
        {err("Túi trang bị đầy (#{Gear.max_bag()} món). Bán bớt đã."), p}

      true ->
        {ok(if(n > 1, do: "Đã mua #{n} #{it.name}.", else: "Đã mua #{it.name}.")),
         %{p | gold: p.gold - price(p, id) * n} |> add_item(id, n)}
    end
  end

  @doc """
  Mua được món có `buy_level` (bình Vừa / Lớn, DECISIONS "Bình máu / mana hồi số"): đủ cấp, hoặc đã chuyển sinh
  ít nhất một lần (cấp về 1 nhưng máu vẫn cao).
  """
  def buy_level_ok?(p, it),
    do: it[:buy_level] == nil or p.level >= it.buy_level or (Map.get(p, :rebirths) || 0) > 0

  @doc """
  Giá mua ở cửa hàng cho nhân vật `p`: bình thuốc `giá × (1 + potion_price_per_level × (cấp − 1))` (từ khi bình hồi
  số cố định, `potion_price_per_level` = 0: giá cố định); giá bán lại vẫn theo giá gốc.
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
    case bag_uid(p, id) do
      "#" <> _ = uid -> sell(p, uid)
      id -> sell_stack(p, id)
    end
  end

  defp sell_stack(p, id) do
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

  @doc """
  Mặc món `id`. `hand: "left"`: vũ khí 1 tay cầm ở tay trái (ô `shield`, thay khiên) — chỉ lớp trong
  `RULES.dual_wield.classes`, tay phải đang cầm vũ khí 1 tay (B-42).
  """
  def equip(p, id, hand \\ nil) do
    id = bag_uid(p, id)
    it = Gear.item(p, id)
    gear? = Gear.instance?(id)
    right = Gear.item(p, p.equip.weapon)
    left? = hand == "left" and is_map(it) and it.slot == "weapon"

    owned =
      if gear?,
        do: it != nil and not Gear.equipped?(p, id) and not Gear.stored?(p, id),
        else: Map.get(p.inv, id, 0) > 0

    cond do
      it == nil or not owned or it.slot not in @item_slots ->
        {err("Không trang bị được."), p}

      it[:cls] && it.cls != p.cls ->
        {err("#{it.name} dành cho #{Data.class(it.cls).name}."), p}

      (why = can_wear(p, it)) != :ok ->
        {err(elem(why, 1)), p}

      it.slot == "shield" and two_handed?(right) ->
        {err("#{right.name} là vũ khí 2 tay: không cầm khiên được."), p}

      left? and not dual_class?(p.cls) ->
        {err("#{Data.class(p.cls).name} không cầm 2 vũ khí được."), p}

      left? and two_handed?(it) ->
        {err("#{it.name} là vũ khí 2 tay: không cầm ở tay trái được."), p}

      left? and right == nil ->
        {err("Cầm vũ khí ở tay phải trước."), p}

      left? and two_handed?(right) ->
        {err("#{right.name} là vũ khí 2 tay: không cầm thêm vũ khí được."), p}

      left? and not dual_pair?(right, it) ->
        {err("Gậy chỉ cầm cùng gậy (không cầm gậy với kiếm / rìu / chùy)."), p}

      true ->
        slot = if left?, do: :shield, else: equip_slot(p, it)
        hp_ratio = p.hp / derived(p).maxHp
        old = p.equip[slot]

        # đồ ngẫu nhiên luôn nằm trong `gear`, chỉ đồ thường mới lấy ra/cất vào `inv`
        p = if gear?, do: p, else: take_item(p, id)
        p = if old && not Gear.instance?(old), do: add_item(p, old), else: p
        p = %{p | equip: Map.put(p.equip, slot, id)}

        # vũ khí 2 tay (B-41): khiên / vũ khí tay trái đang cầm về túi; tay phải đổi loại không hợp với
        # vũ khí tay trái (gậy với kiếm…, B-42) thì vũ khí tay trái về túi
        lw = left_weapon(p)
        mismatch = slot == :weapon and lw != nil and not dual_pair?(it, lw)
        off = slot == :weapon and ((two_handed?(it) and p.equip.shield != nil) or mismatch)

        note =
          cond do
            off && mismatch && not two_handed?(it) ->
              " Vũ khí tay trái về túi (gậy chỉ cầm cùng gậy)."

            off ->
              " #{left_name(p)} về túi (vũ khí 2 tay)."

            true ->
              ""
          end

        p = if off, do: free_shield(p), else: p
        {ok("Đã trang bị #{it.name}.#{note}"), keep_hp_ratio(p, hp_ratio)}
    end
  end

  @doc "Vũ khí `it` cầm 2 tay (`hands: 2`: cung, nỏ, món rộng 2 ô trong Item.txt; B-41): không cầm khiên cùng."
  def two_handed?(it), do: is_map(it) and it[:hands] == 2

  @doc "Lớp `cls` cầm được 2 vũ khí 1 tay (`RULES.dual_wield.classes`, B-42)."
  def dual_class?(cls), do: cls in @dual.classes

  def dual_rules, do: @dual

  @doc """
  Hai vũ khí `a` (tay phải), `b` (tay trái) cầm cùng được không: `dual_wield.staff_pair_only` thì gậy (nhóm 5 Item.txt)
  chỉ cặp với gậy; kiếm / rìu / chùy… cặp tự do.
  """
  def dual_pair?(a, b) do
    not Map.get(@dual, :staff_pair_only, false) or staff?(a) == staff?(b)
  end

  @doc "Gậy (nhóm 5 trong Item.txt)."
  def staff?(it), do: is_map(it) and String.starts_with?(it[:ref] || "", "5/")

  @doc "Vũ khí đang cầm ở tay trái (ô `shield`, cầm 2 vũ khí) hoặc nil (trống / khiên)."
  def left_weapon(p) do
    it = Gear.item(p, p.equip[:shield])
    if is_map(it) and it.slot == "weapon", do: it
  end

  defp left_name(p), do: if(left_weapon(p), do: "Vũ khí tay trái", else: "Khiên")

  defp free_shield(p) do
    old = p.equip.shield
    p = if Gear.instance?(old), do: p, else: add_item(p, old)
    %{p | equip: Map.put(p.equip, :shield, nil)}
  end

  @doc """
  Nhân vật có trước luật 2 tay (B-41) đang cầm vũ khí 2 tay cùng khiên: khiên về túi (khiên là món riêng trong túi
  trang bị nên không mất; túi đầy vẫn giữ được, như khi tháo đồ). Chạy lúc nạp nhân vật.
  """
  def two_hand_fix(p) do
    lw = left_weapon(p)

    if p.equip[:shield] &&
         (two_handed?(Gear.item(p, p.equip[:weapon])) or
            (lw &&
               (two_handed?(lw) or not dual_class?(p.cls) or
                  not dual_pair?(Gear.item(p, p.equip[:weapon]), lw)))),
       do: free_shield(p),
       else: p
  end

  def unequip(p, slot) when slot in @removable do
    key = String.to_existing_atom(slot)

    case p.equip[key] do
      nil ->
        {err("Không tháo được."), p}

      old ->
        hp_ratio = p.hp / derived(p).maxHp
        p = if Gear.instance?(old), do: p, else: add_item(p, old)
        p = %{p | equip: Map.put(p.equip, key, nil)}

        # tháo đồ giữ tỉ lệ máu như lúc mặc (đầy máu thì vẫn đầy máu theo máu tối đa mới, không vượt máu tối đa)
        {ok("Đã tháo #{Gear.item(p, old).name}."), keep_hp_ratio(p, hp_ratio)}
    end
  end

  def unequip(p, _slot), do: {err("Không tháo được."), p}

  # máu theo tỉ lệ `ratio` của máu tối đa hiện tại (mặc / tháo / ép đồ), không quá máu tối đa; mana không vượt mana tối đa
  defp keep_hp_ratio(p, ratio) do
    d = derived(p)
    %{p | hp: min(round(min(ratio, 1) * d.maxHp), d.maxHp), mp: min(p.mp, d.maxMp)}
  end

  @doc "Ngoài trận: máu / mana không vượt mức tối đa (sau khi đổi đồ, thú cưng, cánh, điểm…)."
  def cap_vitals(%{battle: nil} = p) do
    d = derived(p)

    if p.hp > d.maxHp or p.mp > d.maxMp,
      do: %{p | hp: min(p.hp, d.maxHp), mp: min(p.mp, d.maxMp)},
      else: p
  end

  def cap_vitals(p), do: p

  def use_potion(p, id) do
    it = Data.item(id)
    mana? = it != nil and it[:mana] != nil

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

  @doc """
  Chúa tể phải hạ trước lần chuyển sinh kế: đã chuyển sinh `n` ≥ `rebirth_lord_from` lần thì phải từng hạ (Sổ quái)
  chúa tể vùng chuyển sinh `n`. Trả `%{id, name, realm}` hoặc nil (không cần / đã hạ / đã tối đa).
  """
  def rebirth_need(p) do
    n = Map.get(p, :rebirths) || 0

    # chuyển sinh vô hạn (DECISIONS "Chuyển sinh vô hạn"): quá mốc tối đa thì hạ lại chúa tể vùng cuối,
    # tổng số lần hạ ≥ n − max + 1
    k = min(n, @max_rebirths)
    times = max(1, n - @max_rebirths + 1)

    with true <- n >= @char.rebirth_lord_from,
         %{} = lord <- realm_lord(k),
         have when have < times <- Bestiary.count(p, lord.id) do
      %{id: lord.id, name: lord.name, realm: k, times: times, have: have}
    else
      _ -> nil
    end
  end

  @doc """
  Điểm tiềm năng cộng thêm sau lần chuyển sinh thứ `n`: `n × rebirth_points` tới mốc tối đa, sau đó mỗi lần chỉ thêm
  `endless_points` (DECISIONS "Chuyển sinh vô hạn").
  """
  def rebirth_bonus(n) when n <= @max_rebirths, do: n * @rebirth_points

  def rebirth_bonus(n),
    do: @max_rebirths * @rebirth_points + (n - @max_rebirths) * @char.endless_points

  # tên bản đồ có chúa tể `id` (bản đồ cuối của vùng chuyển sinh), nil nếu không thấy
  defp lord_map_name(id) do
    Enum.find_value(HacLong.World.Maps.ids(), fn mid ->
      m = HacLong.World.Maps.get(mid)
      if Enum.any?(m.spawns, &(&1.monster == id)), do: m.name
    end)
  end

  @doc "Chúa tể của vùng chuyển sinh `k` (quái `r<k>_…` có `lord: true`, scripts/gen_realms.py)."
  def realm_lord(k) do
    prefix = "r#{k}_"
    Enum.find(Data.side_monsters(), &(String.starts_with?(&1.id, prefix) and &1[:lord] == true))
  end

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

      need = rebirth_need(p) ->
        {err(
           "Cần hạ #{need.name} ở vùng chuyển sinh #{need.realm}" <>
             if(need.times > 1, do: " (đã hạ #{need.have}/#{need.times} lần)", else: "") <>
             " trước khi chuyển sinh lần #{n + 1}."
         ), p}

      true ->
        n = n + 1
        p = %{p | level: 1, xp: 0, stats: Data.class(p.cls).base, points: rebirth_bonus(n)}
        p = Map.put(p, :rebirths, n)
        d = derived(p)

        off = length(inactive_slots(p))

        {ok(
           "🔄 Chuyển sinh lần #{n}! Trở về cấp 1 với #{p.points} điểm tiềm năng cộng thêm." <>
             if(off > 0,
               do:
                 " #{off} món đang mặc chưa đủ cấp / chỉ số: không có tác dụng tới khi đủ (viền đỏ ⛔).",
               else: ""
             )
         ), Map.merge(p, %{hp: d.maxHp, mp: d.maxMp})}
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

  # tên các hiệu ứng, cách nhau dấu phẩy (tính trước để câu nhật ký dịch được theo mẫu)
  defp effect_list(effs), do: Enum.map_join(effs, ", ", &@effect_names[&1.id])
end

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
  - Cộng điểm theo `strategy`: `"str"`, `"agi"`, `"vit"` (dồn hết) hoặc `"balanced"`.
  - `equipment`: danh sách template (vd. bộ đồ t0 từ `data/items/phase1.json`) để so Q14.
  """

  alias Mu.Game.{Config, Data, Drops, Engine, Rng}

  @milestones [2, 5, 10]

  @defaults %{
    strategy: "balanced",
    walk_ms: 2000,
    potion_below: 0.4,
    equipment: [],
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
      damage_taken_per_kill: avg.(&(&1.damage_taken / max(&1.kills, 1))),
      hit_rate: avg.(&(&1.hits / max(&1.swings, 1)))
    }
  end

  @doc "Một lần mô phỏng với `seed`."
  def once(seed, opts) do
    opts = Map.merge(@defaults, opts)
    c = start_character()
    potion = potion_heal()

    st = %{
      strategy: opts.strategy,
      rng: Rng.new(seed),
      c: c,
      hp: Engine.derived(c, opts.equipment).hp_max,
      t: 0,
      kills: 0,
      potions: 0,
      deaths: 0,
      zen: 0,
      items: 0,
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

  # một trận với một Spider, theo thời gian (ms)
  defp fight(st, opts, potion) do
    spider = Data.monster("spider")
    m = Engine.monster_stats(spider)
    combat = Config.get(["combat"])
    d = Engine.derived(st.c, opts.equipment)
    st = %{st | t: st.t + opts.walk_ms}
    duel(st, opts, potion, d, m, spider, spider["hp"], st.t, st.t + combat["baseCooldownMs"], 0)
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
        st = %{st | t: p_next}
        {res, rng} = Engine.roll_attack(st.rng, d, m)
        st = %{st | rng: rng, swings: st.swings + 1, hits: st.hits + if(res.hit, do: 1, else: 0)}

        duel(
          st,
          opts,
          potion,
          d,
          m,
          spider,
          mhp - res.dmg,
          p_next + d.cooldown_ms,
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
    {drop, rng} = Drops.roll(st.rng, "spider")
    exp = Engine.exp_gain(spider["experience"], st.c.level, spider["level"])
    {c, levels} = Engine.add_exp(st.c, exp)
    c = allocate(c, st.strategy)

    st = %{
      st
      | rng: rng,
        c: c,
        kills: st.kills + 1,
        zen: st.zen + drop.zen,
        items: st.items + length(drop.items)
    }

    # lên cấp hồi đầy (G10)
    st = if levels > 0, do: %{st | hp: Engine.derived(c).hp_max}, else: st

    Enum.reduce(@milestones, st, fn lv, st ->
      if c.level >= lv and not Map.has_key?(st.at, lv),
        do:
          put_in(st.at[lv], %{kills: st.kills, ms: st.t, potions: st.potions, deaths: st.deaths}),
        else: st
    end)
  end

  defp allocate(%{free_stat_points: 0} = c, _strategy), do: c

  defp allocate(c, strategy) do
    stat =
      case strategy do
        "str" -> "strength"
        "agi" -> "agility"
        "vit" -> "vitality"
        _ -> Enum.at(~w(strength agility vitality), rem(c.free_stat_points, 3))
      end

    {:ok, c} = Engine.alloc(c, stat, 1)
    allocate(c, strategy)
  end

  defp start_character do
    cls = Data.class(Config.get(["newCharacter", "class"]))

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

  defp potion_heal do
    Enum.find(item_templates(), &(&1["templateId"] == "hp_potion_small"))["effect"]["hp"]
  end
end

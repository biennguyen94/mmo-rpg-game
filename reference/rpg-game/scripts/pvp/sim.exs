# Mô phỏng đồ sát đúng đường server (Session.slay_turn): Slay.opponent (bản sao), Engine.start_with_monster + live,
# luân phiên lượt (người tấn công đi trước), trạng thái trận mỗi bên giữ như Slay (`fx`), hiệu ứng chéo
# (Engine.pvp_aim / pvp_turn_start / pvp_take_debuffs / pvp_defend / pvp_receive).
Code.require_file(Path.join(__DIR__, "build.exs"))

defmodule SlaySim do
  alias HacLong.Game.{Commands, Engine}
  alias HacLong.Slay

  # như Session.slay_turn: máu bản sao đệm trong lượt để biết đủ sát thương (cả phần lố)
  @pad 10_000_000

  def enter(p, foe, uid) do
    {_, p} = Engine.start_with_monster(p, 0, Slay.opponent(foe, uid))
    b = Map.merge(p.battle, %{live: true, encounter: %{slay: 1, foe: uid, mine: false, until: 0}})
    %{p | battle: b}
  end

  # một trận: a đánh trước. Trả %{winner, turns, st}
  def fight(a, b, cap \\ 200) do
    ps = %{1 => enter(a, b, 2), 2 => enter(b, a, 1)}
    chars = %{1 => a, 2 => b}
    # DEF_SHIELD: người bị đánh (2) vào trận có khiên = X × máu tối đa (hết khi vỡ)
    sh = String.to_float(System.get_env("DEF_SHIELD") || "0.0")
    fx2 = if sh > 0, do: %{effects: [%{id: "shield", turns: 999, power: round(sh * ps[2].hp)}], turn: 0, pstun_free: 0, pet_revived: false}
    st = %{mismatch: 0, turns: 0, stunned: 0, reduced: 0, saved: 0, pots: 0}
    loop(ps, chars, %{1 => ps[1].hp, 2 => ps[2].hp}, %{1 => nil, 2 => fx2}, 1, 0, cap, st)
  end

  defp loop(_ps, _c, hp, _fx, _uid, n, cap, st) when n >= cap,
    do: %{winner: :draw, turns: n, st: st, hp: hp}

  defp loop(ps, chars, hp, fx, uid, n, cap, st) do
    foe_id = 3 - uid

    p =
      %{ps[uid] | hp: hp[uid]}
      |> put_in([:battle, :monster, :hp], hp[foe_id] + @pad)
      |> put_in([:battle, :log], [])
      |> Engine.pvp_put_fx(fx[uid])

    foe = Engine.pvp_victim(chars[foe_id], fx[foe_id], hp[foe_id])
    # CROSS=0: như trước khi có hiệu ứng chéo (để so sánh)
    cross? = System.get_env("CROSS") != "0"
    p = if cross?, do: Engine.pvp_aim(p, foe), else: p
    stunned? = Engine.stunned?(p)
    p = Engine.pvp_turn_start(p)

    p2 =
      if p.hp > 0 do
        {act, sk} = Engine.auto_strike(p)
        # POT=1: như người chơi thật, máu dưới POT_PCT (mặc định 50%) thì uống bình máu (mất lượt)
        pot? =
          System.get_env("POT") == "1" and
            p.hp < Engine.derived(p).maxHp * String.to_float(System.get_env("POT_PCT") || "0.5") and
            Map.get(p.inv, "potion_l", 0) > 0

        # hết MP cho mọi kỹ năng đã hồi chiêu xong thì uống bình mana (POT=1)
        mana? =
          System.get_env("POT") == "1" and sk == nil and Map.get(p.inv, "mana_l", 0) > 0 and
            Enum.any?(Engine.skills(p), &(Engine.cooldown(p, &1.id) == 0 and (p.mp || 0) < Engine.skill_mp(p, &1)))

        strike = if sk, do: %{"act" => "skill", "skill" => sk}, else: %{"act" => act}

        cmd =
          cond do
            pot? -> %{"act" => "potion"}
            mana? -> %{"act" => "mana"}
            true -> strike
          end

        {r, p2} = Commands.run(p, cmd)

        # bình máu chưa dùng được (RULES.pvp.potion_cd / potion_max) thì đánh
        {used, p2} = if r[:ok] == false, do: {strike, elem(Commands.run(p, strike), 1)}, else: {cmd, p2}

        # HEAL_MULT=x: thử giảm hồi máu từ kỹ năng / thú khi đánh người (không đụng bình máu)
        hm = System.get_env("HEAL_MULT")

        if hm && used["act"] != "potion" && p2.hp > p.hp,
          do: %{p2 | hp: p.hp + round((p2.hp - p.hp) * String.to_float(hm))},
          else: p2
      else
        p
      end

    raw = hp[foe_id] + @pad - p2.battle.monster.hp
    # đòn mở màn (RULES.slay.first_strike_mult, như Session.slay_hit); FIRST_MULT=… để thử số khác
    first = System.get_env("FIRST_MULT")
    first = if first, do: String.to_float(first), else: HacLong.Game.Data.rules().slay.first_strike_mult
    raw = if n == 0, do: round(raw * first), else: raw

    shown =
      p2.battle.log
      |> Enum.flat_map(&Regex.scan(~r/(?:gây|cắn thêm) (\d+) sát thương/u, &1.text, capture: :all_but_first))
      |> Enum.map(fn [x] -> String.to_integer(x) end)
      |> Enum.sum()

    {p2, debuffs} = if cross?, do: Engine.pvp_take_debuffs(p2), else: {p2, []}
    # so sánh: NO_STUN=1 bỏ choáng chéo, NO_UNDYING=1 bỏ Bất Tử, NO_REVIVE=1 bỏ Long Vương Hồi Sinh
    debuffs = if System.get_env("NO_STUN") == "1", do: Enum.reject(debuffs, &(&1.id == "stun")), else: debuffs
    foe = if System.get_env("NO_UNDYING") == "1", do: put_in(foe, [:battle, :effects, :player], Enum.reject(foe.battle.effects.player, &(&1.id == "undying"))), else: foe
    foe = if System.get_env("NO_REVIVE") == "1", do: put_in(foe, [:battle, :pet_revived], true), else: foe
    {foe2, real} = if cross?, do: Engine.pvp_defend(foe, raw), else: {%{foe | hp: foe.hp - raw}, raw}
    foe2 = Engine.pvp_receive(foe2, debuffs)

    bad = if shown != raw, do: 1, else: 0

    st = %{
      st
      | mismatch: st.mismatch + bad,
        turns: st.turns + 1,
        stunned: st.stunned + if(stunned?, do: 1, else: 0),
        reduced: st.reduced + if(raw > 0 and real < raw, do: 1, else: 0),
        saved: st.saved + if(foe.hp - real <= 0 and foe2.hp > 0, do: 1, else: 0),
        pots: st.pots + if(Map.get(p2.inv, "potion_l", 0) < Map.get(p.inv, "potion_l", 0), do: 1, else: 0)
    }

    # theo từng bên (1 = người tấn công): sát thương thật gây ra, máu tự hồi trong lượt mình, lượt bị choáng
    by = Map.get(st, :by, %{})
    add = fn by, k, v -> Map.update(by, {uid, k}, v, &(&1 + v)) end

    by =
      by
      |> add.(:dealt, real)
      |> add.(:healed, max(0, p2.hp - p.hp))
      |> add.(:stunned, if(stunned?, do: 1, else: 0))
      |> add.(:turns, 1)

    st = Map.put(st, :by, by)

    hp = %{uid => max(p2.hp, 0), foe_id => max(foe2.hp, 0)}
    fx = %{fx | uid => Engine.pvp_fx(p2), foe_id => Engine.pvp_fx(foe2)}
    ps = Map.put(ps, uid, p2)

    cond do
      hp[foe_id] <= 0 -> %{winner: uid, turns: n + 1, st: st, hp: hp}
      hp[uid] <= 0 -> %{winner: foe_id, turns: n + 1, st: st, hp: hp}
      true -> loop(ps, chars, hp, fx, foe_id, n + 1, cap, st)
    end
  end
end

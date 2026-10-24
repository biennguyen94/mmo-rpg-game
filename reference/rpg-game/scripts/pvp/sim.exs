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
    st = %{mismatch: 0, turns: 0, stunned: 0, reduced: 0, saved: 0}
    loop(ps, chars, %{1 => ps[1].hp, 2 => ps[2].hp}, %{1 => nil, 2 => nil}, 1, 0, cap, st)
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
        cmd = if sk, do: %{"act" => "skill", "skill" => sk}, else: %{"act" => act}
        {r, p2} = Commands.run(p, cmd)
        if r[:ok] == false, do: elem(Commands.run(p, %{"act" => "attack"}), 1), else: p2
      else
        p
      end

    raw = hp[foe_id] + @pad - p2.battle.monster.hp

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
    foe =
      if System.get_env("ONE_SAVE") == "1" and foe.battle[:pet_revived],
        do: put_in(foe, [:battle, :effects, :player], Enum.reject(foe.battle.effects.player, &(&1.id == "undying"))),
        else: foe

    {foe2, real} = if cross?, do: Engine.pvp_defend(foe, raw), else: {%{foe | hp: foe.hp - raw}, raw}
    foe2 = Engine.pvp_receive(foe2, debuffs)

    # ONE_SAVE=1: mỗi trận được cứu một lần (Bất Tử hoặc Long Vương)
    foe2 =
      if System.get_env("ONE_SAVE") == "1" and foe.hp - real <= 0 and foe2.hp > 0,
        do:
          foe2
          |> put_in([:battle, :pet_revived], true)
          |> put_in([:battle, :effects, :player], Enum.reject(foe2.battle.effects.player, &(&1.id == "undying"))),
        else: foe2

    bad = if shown != raw, do: 1, else: 0

    st = %{
      st
      | mismatch: st.mismatch + bad,
        turns: st.turns + 1,
        stunned: st.stunned + if(stunned?, do: 1, else: 0),
        reduced: st.reduced + if(raw > 0 and real < raw, do: 1, else: 0),
        saved: st.saved + if(foe.hp - real <= 0 and foe2.hp > 0, do: 1, else: 0)
    }

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

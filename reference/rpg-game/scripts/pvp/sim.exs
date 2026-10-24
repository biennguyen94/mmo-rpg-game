# Mô phỏng đồ sát đúng đường server: Slay.opponent (bản sao), Engine.start_with_monster + live,
# luân phiên lượt (người tấn công đi trước), máu hai bên đồng bộ như Slay.acted, Session.slay_strike chạy Commands.
Code.require_file(Path.join(__DIR__, "build.exs"))

defmodule SlaySim do
  alias HacLong.Game.{Commands, Engine}
  alias HacLong.Slay

  def enter(p, foe, uid) do
    {_, p} = Engine.start_with_monster(p, 0, Slay.opponent(foe, uid))
    b = Map.merge(p.battle, %{live: true, encounter: %{slay: 1, foe: uid, mine: false, until: 0}})
    %{p | battle: b}
  end

  # một trận: a đánh trước. Trả %{winner, turns, stats}
  def fight(a, b, cap \\ 200) do
    pa = enter(a, b, 2)
    pb = enter(b, a, 1)
    loop(%{1 => pa, 2 => pb}, %{1 => pa.hp, 2 => pb.hp}, 1, 0, cap, %{mismatch: 0, turns: 0, fx: %{}})
  end

  defp loop(_ps, hp, _uid, n, cap, st) when n >= cap, do: %{winner: :draw, turns: n, st: st, hp: hp}

  defp loop(ps, hp, uid, n, cap, st) do
    foe = 3 - uid
    p = %{ps[uid] | hp: hp[uid]} |> put_in([:battle, :monster, :hp], hp[foe]) |> put_in([:battle, :log], [])
    {act, sk} = Engine.auto_strike(p)
    cmd = if sk, do: %{"act" => "skill", "id" => sk}, else: %{"act" => act}
    {r, p2} = Commands.run(p, cmd)
    {_, p2} = if r[:ok] == false, do: Commands.run(p, %{"act" => "attack"}), else: {r, p2}
    lost = hp[foe] - p2.battle.monster.hp

    shown =
      p2.battle.log
      |> Enum.flat_map(&Regex.scan(~r/(?:gây|cắn thêm) (\d+) sát thương/u, &1.text, capture: :all_but_first))
      |> Enum.map(fn [x] -> String.to_integer(x) end)
      |> Enum.sum()

    # đòn lố (máu về 0) thì máu mất < sát thương hiện
    bad = if p2.battle.monster.hp > 0 and shown != lost, do: 1, else: 0
    fx = Enum.reduce(get_in(p2, [:battle, :effects, :monster]) || [], st.fx, &Map.update(&2, "foe:" <> &1.id, 1, fn c -> c + 1 end))
    fx = Enum.reduce(get_in(p2, [:battle, :effects, :player]) || [], fx, &Map.update(&2, "self:" <> &1.id, 1, fn c -> c + 1 end))
    st = %{st | mismatch: st.mismatch + bad, turns: st.turns + 1, fx: fx}
    hp = %{uid => p2.hp, foe => max(p2.battle.monster.hp, 0)}
    ps = Map.put(ps, uid, p2)

    cond do
      hp[foe] <= 0 -> %{winner: uid, turns: n + 1, st: st, hp: hp}
      hp[uid] <= 0 -> %{winner: foe, turns: n + 1, st: st, hp: hp}
      true -> loop(ps, hp, foe, n + 1, cap, st)
    end
  end
end

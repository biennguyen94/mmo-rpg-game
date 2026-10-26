# Đánh chúa tể vùng chuyển sinh (cần hạ để chuyển sinh tiếp) theo lớp, đồ theo hồ sơ mốc (Max.tier/2), bot đánh như
# hành trình (`Brain.fight/1`: kỹ năng mạnh nhất, uống bình dưới 35% máu). In tỉ lệ thắng, số lượt, máu còn lại.
#   KS=1,3,5,7,9 N=20 mix run --no-start scripts/pvp/lords.exs
Code.require_file(Path.join(__DIR__, "build.exs"))
alias HacLong.Bots.Brain
alias HacLong.Game.{Data, Engine}

ks =
  (System.get_env("KS") || "1,2,3,4,5,6,7,8,9")
  |> String.split(",")
  |> Enum.map(&String.to_integer/1)

n = String.to_integer(System.get_env("N") || "20")

for k <- ks do
  :rand.seed(:exsss, {k, 3, 5})

  rows =
    for c <- ~w(dk dw elf mg) do
      {p, _} = Max.tier(c, k)
      d = Engine.derived(p)
      p = %{p | hp: d.maxHp, battle: nil} |> Map.put(:mp, d.maxMp)

      case Engine.rebirth_need(p) do
        nil ->
          {c, nil}

        %{id: id, name: name} ->
          res =
            for _ <- 1..n do
              {_, q} =
                Engine.start_side_encounter(
                  p,
                  Map.put(Data.side_monster(id), :lord, true),
                  "x",
                  "forest"
                )

              q =
                Enum.reduce_while(1..300, q, fn _, q ->
                  if q.battle.over do
                    {:halt, q}
                  else
                    cmd = Brain.fight(q)
                    {:cont, elem(Engine.act(q, cmd["act"], cmd["skill"]), 1)}
                  end
                end)

              {q.battle.result == "win", q.battle.turn,
               q.battle.monster.hp / q.battle.monster.maxHp}
            end

          w = Enum.count(res, &elem(&1, 0))
          t = Enum.sum(Enum.map(res, &elem(&1, 1))) / n
          left = Enum.sum(for {false, _, l} <- res, do: l) / max(n - w, 1)
          {c, {name, w * 100 / n, t, left}}
      end
    end

  name = Enum.find_value(rows, fn {_, r} -> r && elem(r, 0) end)

  if name,
    do:
      IO.puts(
        "r#{k} #{name}: " <>
          Enum.map_join(rows, "  ", fn
            {c, nil} ->
              "#{c} —"

            {c, {_, w, t, l}} ->
              "#{c} thắng #{round(w)}% (#{Float.round(t, 1)} lượt, thua thì trùm còn #{round(l * 100)}%)"
          end)
      )
end

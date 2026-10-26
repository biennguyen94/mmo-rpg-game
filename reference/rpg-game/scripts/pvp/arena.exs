# Đấu trường chéo 4 lớp theo mốc (đồ ngang nhau, Max.tier/2): người thách đấu đánh tự động (kỹ năng mạnh nhất, uống
# bình máu dưới 50%; POT=0 không uống), đối thủ máy chạy như người thật (`battle.mirror`: kỹ năng, thú, buff, hồi máu;
# không uống bình), như Session.
#   KS=0,3,6,10 N=24 POT=0 mix run --no-start scripts/pvp/arena.exs
Code.require_file(Path.join(__DIR__, "balance.exs"))
alias HacLong.Arena
alias HacLong.Game.{Commands, Engine}

ks = (System.get_env("KS") || "0,3,6,10") |> String.split(",") |> Enum.map(&String.to_integer/1)
n = String.to_integer(System.get_env("N") || "24")
classes = PvpBalance.classes()

char = fn c, k ->
  {p, _} = Max.tier(c, k)
  d = Engine.derived(p)

  %{
    p
    | hp: d.maxHp,
      battle: nil,
      inv: p.inv |> Map.put("potion_l", 100) |> Map.put("mana_l", 100)
  }
  |> Map.put(:mp, d.maxMp)
end

fight = fn a, b ->
  {_, p} = Engine.start_with_monster(a, 1, Arena.opponent(b, 2))
  p = put_in(p.battle[:mirror], Engine.mirror(b, Arena.opponent(a, 1)))

  p =
    Enum.reduce_while(1..200, p, fn _, p ->
      if p.battle.over do
        {:halt, p}
      else
        low? =
          System.get_env("POT") != "0" and p.hp < Engine.derived(p).maxHp * 0.5 and
            Map.get(p.inv, "potion_l", 0) > 0

        {r, p2} = if low?, do: Commands.run(p, %{"act" => "potion"}), else: {%{ok: false}, p}

        p2 =
          if r[:ok] == false do
            {act, k} = Engine.auto_strike(p)
            elem(Engine.act(p, act, k), 1)
          else
            p2
          end

        {:cont, p2}
      end
    end)

  p.battle.result
end

for k <- ks do
  :rand.seed(:exsss, {k + 1, 5, 9})
  ps = Map.new(classes, &{&1, char.(&1, k)})

  tab =
    for a <- classes, b <- classes, a != b, into: %{} do
      res = for _ <- 1..n, do: fight.(ps[a], %{ps[b] | name: "#{b}x"})
      {{a, b}, Enum.count(res, &(&1 == "win")) / max(Enum.count(res, &(&1 in ~w(win lose))), 1)}
    end

  # tỉ lệ thắng của lớp: khi thách đấu + khi bị thách đấu
  tot =
    Enum.map_join(classes, "  ", fn c ->
      x = for({{a, b}, w} <- tab, a == c, do: w) ++ for({{a, b}, w} <- tab, b == c, do: 1 - w)
      "#{c} #{round(Enum.sum(x) / length(x) * 100)}%"
    end)

  IO.puts("r#{k}: #{tot}")

  for a <- classes,
      do:
        IO.puts(
          "    #{a} thách: " <>
            Enum.map_join(classes -- [a], " ", &"#{&1} #{round(tab[{a, &1}] * 100)}%")
        )
end

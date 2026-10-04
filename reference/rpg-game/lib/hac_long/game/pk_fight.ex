defmodule HacLong.Game.PkFight do
  @moduledoc """
  Trận PK cược vàng (Phase 5, H7 + H8): hai **bản sao chỉ số** (`HacLong.Arena.opponent/2`) tự đánh
  nhau theo cùng một luật, không ai điều khiển. Hàm thuần, ngẫu nhiên qua `HacLong.Game.Rng`.

  - Người mời (`a`) đánh trước, rồi hai bên thay phiên. Mỗi bên dùng kỹ năng của lớp ở lượt thứ
    `RULES.pk.special_every` (×`special_mult`, không chí mạng, không né được); đòn thường có thể bị né
    (`dodge`) và chí mạng (`crit`, hệ số `RULES.combat.monster_crit_mult`).
  - Hết máu thì thua. Quá `RULES.pk.rounds` lượt thì bên còn **% máu** cao hơn thắng; bằng nhau là hòa.

  Trả về `%{winner: :a | :b | :draw, rounds, hp: %{a, b}, log: [%{text, kind}]}`.
  """

  alias HacLong.Game.{Data, Engine, Rng}

  @pk Data.rules().pk
  @crit_mult Data.rules().combat.monster_crit_mult

  def fight(a, b) do
    st = %{a: Map.put(a, :hp, a.maxHp), b: Map.put(b, :hp, b.maxHp), log: [], round: 1}
    st = loop(st, :a)

    winner =
      cond do
        st.a.hp <= 0 -> :b
        st.b.hp <= 0 -> :a
        ratio(st.a) > ratio(st.b) -> :a
        ratio(st.b) > ratio(st.a) -> :b
        true -> :draw
      end

    end_text =
      case winner do
        :draw -> "Hết #{@pk.rounds} lượt, hai bên ngang nhau: hòa."
        w -> "🏆 #{st[w].name} thắng!"
      end

    %{
      winner: winner,
      rounds: min(st.round, @pk.rounds),
      hp: %{a: max(st.a.hp, 0), b: max(st.b.hp, 0)},
      log: Enum.reverse([%{text: end_text, kind: "win"} | st.log])
    }
  end

  defp ratio(x), do: x.hp / x.maxHp

  # một lượt = cả hai bên đánh một lần (người mời trước)
  defp loop(st, side) do
    cond do
      st.a.hp <= 0 or st.b.hp <= 0 -> st
      st.round > @pk.rounds -> st
      true -> st |> strike(side, other(side)) |> next(side)
    end
  end

  defp next(st, :a), do: loop(st, :b)
  defp next(st, :b), do: loop(%{st | round: st.round + 1}, :a)

  defp other(:a), do: :b
  defp other(:b), do: :a

  defp strike(st, me, them) do
    m = st[me]
    t = st[them]

    if t.hp <= 0 do
      st
    else
      special = rem(st.round, @pk.special_every) == 0

      cond do
        not special and chance(t.dodge) ->
          say(st, "#{t.name} né được đòn của #{m.name}.", "info")

        special ->
          dmg = Engine.damage(m.atk, t.def, @pk.special_mult)

          st
          |> hurt(them, dmg)
          |> say("🔥 #{m.name} dùng #{m.special.name}: #{t.name} mất #{dmg} máu.", kind(me))

        true ->
          crit = chance(m.crit)
          dmg = Engine.damage(m.atk, t.def, if(crit, do: @crit_mult, else: 1))

          st
          |> hurt(them, dmg)
          |> say(
            "#{m.name} đánh #{t.name} #{dmg} máu#{if crit, do: " (chí mạng)", else: ""}.",
            kind(me)
          )
      end
    end
  end

  defp kind(:a), do: "hit"
  defp kind(:b), do: "hurt"

  defp hurt(st, who, dmg), do: put_in(st, [who, :hp], st[who].hp - dmg)
  defp say(st, text, kind), do: %{st | log: [%{text: text, kind: kind} | st.log]}
  defp chance(p), do: Rng.uniform() < p
end

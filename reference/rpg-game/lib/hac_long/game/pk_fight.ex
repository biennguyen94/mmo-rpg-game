defmodule HacLong.Game.PkFight do
  @moduledoc """
  Trận PK cược vàng (Phase 5, H7 + H8): hai nhân vật tự đánh nhau, không ai điều khiển. Hàm thuần, ngẫu nhiên qua
  `HacLong.Game.Rng`.

  DECISIONS "Cân bằng đánh người": dùng đúng bộ máy trận thật (`Engine.act/3`, chế độ `live` như đồ sát): mỗi bên đánh
  bản sao chỉ số của bên kia (`HacLong.Arena.opponent/2`), mỗi lượt dùng kỹ năng mạnh nhất đang dùng được
  (`Engine.auto_strike/1`), không có thì đánh thường; luật đánh người (`RULES.pvp`) áp như mọi trận đánh người.
  **Hai bên ra đòn cùng lúc** trong một lượt (không ai được lợi vì đánh trước): sát thương và hồi máu của cả lượt cộng
  rồi mới tính ai gục. Bị choáng thì mất lượt sau, vừa thoát choáng thì kháng `RULES.pvp.stun_immune` lượt.

  - Hết máu thì thua; cả hai cùng gục trong một lượt thì bên bị đánh lố ít hơn (so với máu tối đa) thắng, bằng nhau là
    hòa. Quá `RULES.pk.rounds` lượt thì bên còn **% máu** cao hơn thắng; bằng nhau
    là hòa.

  `fight(pa, pb, a_id, b_id)`: `pa`, `pb` là nhân vật (người mời trước). Trả về
  `%{winner: :a | :b | :draw, rounds, hp: %{a, b}, log: [%{text, kind}]}`.
  """

  alias HacLong.Arena
  alias HacLong.Game.{BattleText, Data, Engine}

  @pk Data.rules().pk
  @immune Data.rules().pvp.stun_immune

  def fight(pa, pb, a_id \\ 1, b_id \\ 2) do
    st = %{
      a: side(pa, Arena.opponent(pb, b_id)),
      b: side(pb, Arena.opponent(pa, a_id)),
      log: [],
      round: 1,
      # lượt cuối: máu (có thể âm) / máu tối đa, để phân thắng thua khi cả hai cùng gục
      over: %{a: 0, b: 0}
    }

    st = loop(st)
    ha = st.a.p.hp
    hb = st.b.p.hp

    winner =
      cond do
        ha <= 0 and hb <= 0 and st.over.a > st.over.b -> :a
        ha <= 0 and hb <= 0 and st.over.b > st.over.a -> :b
        ha <= 0 and hb <= 0 -> :draw
        ha <= 0 -> :b
        hb <= 0 -> :a
        ha / st.a.max > hb / st.b.max -> :a
        hb / st.b.max > ha / st.a.max -> :b
        true -> :draw
      end

    end_text =
      case winner do
        :draw when ha <= 0 -> "Hai bên cùng gục: hòa."
        :draw -> "Hết #{@pk.rounds} lượt, hai bên ngang nhau: hòa."
        w -> "🏆 #{st[w].p.name} thắng!"
      end

    %{
      winner: winner,
      rounds: min(st.round, @pk.rounds),
      hp: %{a: max(ha, 0), b: max(hb, 0)},
      log: Enum.reverse([%{text: end_text, kind: "win"} | st.log])
    }
  end

  # một bên: nhân vật trong trận `live` với bản sao bên kia, cờ choáng, lượt hết kháng choáng
  defp side(p, foe) do
    d = Engine.derived(p)
    p = %{p | battle: nil, hp: d.maxHp} |> Map.put(:mp, d.maxMp)
    {_, p} = Engine.start_with_monster(p, 1, foe)
    %{p: put_in(p, [:battle, :live], true), max: d.maxHp, stunned: false, free: 0}
  end

  defp loop(st) do
    if st.a.p.hp <= 0 or st.b.p.hp <= 0 or st.round > @pk.rounds do
      st
    else
      {a, dealt_a, stun_b, log_a} = strike(st.a, st.b.p.name, st.round)
      {b, dealt_b, stun_a, log_b} = strike(st.b, st.a.p.name, st.round)

      # cùng lúc: máu mới = máu sau đòn của mình (hồi máu) − đòn bên kia
      ra = a.p.hp - dealt_b
      rb = b.p.hp - dealt_a
      ha = max(ra, 0)
      hb = max(rb, 0)
      a = sync(a, ha, hb) |> stun(stun_a, st.round)
      b = sync(b, hb, ha) |> stun(stun_b, st.round)
      over = %{a: ra / a.max, b: rb / b.max}
      loop(%{st | a: a, b: b, log: log_b ++ log_a ++ st.log, round: st.round + 1, over: over})
    end
  end

  # một bên ra đòn: trả bên đó sau lượt, sát thương gây cho bên kia, có làm choáng bên kia không, các dòng nhật ký
  defp strike(%{stunned: true} = s, _foe, round) do
    s = %{s | stunned: false, free: round + 1 + @immune}
    {s, 0, false, [%{text: "💫 #{s.p.name} bị choáng, mất lượt.", kind: "info"}]}
  end

  # máu đệm cho bản sao lúc tính đòn: Engine chặn máu ở 0, cần biết đòn lố bao nhiêu khi cả hai cùng gục
  @pad 10_000_000

  defp strike(s, foe, _round) do
    # nhật ký trống: lấy đúng các dòng của lượt này (kỹ năng, chí mạng, nhiều đòn, trượt, thú cưng…)
    p = update_in(s.p, [:battle, :monster, :hp], &(&1 + @pad)) |> put_in([:battle, :log], [])
    before = p.battle.monster.hp

    {act, skill} = Engine.auto_strike(p)
    {_, p2} = Engine.act(p, act, skill)
    dealt = before - p2.battle.monster.hp
    stunned? = Enum.any?(get_in(p2, [:battle, :effects, :monster]) || [], &(&1.id == "stun"))
    p2 = update_in(p2, [:battle, :effects], &drop_stun/1)

    # người xem đọc ở ngôi thứ ba: "Bạn" → tên người đánh, đối thủ giữ tên
    lines = BattleText.view(p2.battle.log, p.name, foe, foe)

    lines =
      if lines == [],
        do: [%{text: "#{p.name} ra đòn nhưng không trúng.", kind: "info"}],
        else: lines

    healed = p2.hp - p.hp

    heal =
      if healed > 0 and not Enum.any?(lines, &(&1.text =~ ~r/hồi|Hút/u)),
        do: [%{text: "#{p.name} hồi #{healed} máu.", kind: "good"}],
        else: []

    {%{s | p: p2}, dealt, stunned?, Enum.reverse(lines ++ heal)}
  end

  defp drop_stun(nil), do: nil

  defp drop_stun(fx),
    do: Map.update(fx, :monster, [], &Enum.reject(&1, fn e -> e.id == "stun" end))

  defp sync(s, hp, foe_hp) do
    p = %{s.p | hp: hp} |> put_in([:battle, :monster, :hp], foe_hp)
    %{s | p: p}
  end

  # bị bên kia làm choáng: mất lượt sau, trừ khi vừa thoát choáng (còn kháng)
  defp stun(s, true, round) when round + 1 >= s.free, do: %{s | stunned: true}
  defp stun(s, _, _), do: s
end

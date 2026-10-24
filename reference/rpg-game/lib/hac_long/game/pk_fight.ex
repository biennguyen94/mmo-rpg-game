defmodule HacLong.Game.PkFight do
  @moduledoc """
  Trận PK cược vàng (Phase 5, H7 + H8): hai nhân vật tự đánh nhau, không ai điều khiển. Hàm thuần, ngẫu nhiên qua
  `HacLong.Game.Rng`.

  DECISIONS "Cân bằng đánh người": dùng đúng bộ máy trận thật (`Engine.act/3`, chế độ `live` như đồ sát): mỗi bên đánh
  bản sao chỉ số của bên kia (`HacLong.Arena.opponent/2`), mỗi lượt dùng kỹ năng mạnh nhất đang dùng được
  (`Engine.auto_strike/1`), không có thì đánh thường; luật đánh người (`RULES.pvp`) áp như mọi trận đánh người.
  **Hai bên ra đòn cùng lúc** trong một lượt (không ai được lợi vì đánh trước): sát thương và hồi máu của cả lượt cộng
  rồi mới tính ai gục. Hiệu ứng chéo như đồ sát (`Engine.pvp_*`): bị choáng thì mất lượt sau, vừa thoát choáng thì kháng
  `RULES.pvp.stun_immune` lượt; suy yếu / độc chuyển sang người kia; đòn đi qua thủ thế / thú / khiên / bất tử / Long Vương.

  - Hết máu thì thua; cả hai cùng gục trong một lượt thì bên bị đánh lố ít hơn (so với máu tối đa) thắng, bằng nhau là
    hòa. Quá `RULES.pk.rounds` lượt thì bên còn **% máu** cao hơn thắng; bằng nhau
    là hòa.

  `fight(pa, pb, a_id, b_id)`: `pa`, `pb` là nhân vật (người mời trước). Trả về
  `%{winner: :a | :b | :draw, rounds, hp: %{a, b}, log: [%{text, kind}]}`.
  """

  alias HacLong.Arena
  alias HacLong.Game.{BattleText, Data, Engine}

  @pk Data.rules().pk

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

  # một bên: nhân vật trong trận `live` với bản sao bên kia
  defp side(p, foe) do
    d = Engine.derived(p)
    p = %{p | battle: nil, hp: d.maxHp} |> Map.put(:mp, d.maxMp)
    {_, p} = Engine.start_with_monster(p, 1, foe)
    %{p: put_in(p, [:battle, :live], true), max: d.maxHp}
  end

  defp loop(st) do
    if st.a.p.hp <= 0 or st.b.p.hp <= 0 or st.round > @pk.rounds do
      st
    else
      # bản sao né theo buff của người kia, kháng choáng nếu người kia vừa thoát choáng
      a = %{st.a | p: Engine.pvp_aim(st.a.p, st.b.p)}
      b = %{st.b | p: Engine.pvp_aim(st.b.p, st.a.p)}
      {a, dealt_a, log_a} = strike(a, b.p.name)
      {b, dealt_b, log_b} = strike(b, a.p.name)

      # cùng lúc (DECISIONS "Đồ sát: hiệu ứng chéo"): đòn của mỗi bên đi qua phần đỡ đòn của bên kia (thủ thế, thú, khiên,
      # bất tử, Long Vương); choáng / suy yếu / độc đặt lên bản sao chuyển sang người kia
      {ap, deb_a} = Engine.pvp_take_debuffs(a.p)
      {bp, deb_b} = Engine.pvp_take_debuffs(b.p)
      {bp, def_b} = defend(bp, dealt_a, ap.name)
      {ap, def_a} = defend(ap, dealt_b, bp.name)
      ap = Engine.pvp_receive(ap, deb_b)
      bp = Engine.pvp_receive(bp, deb_a)

      ra = ap.hp
      rb = bp.hp
      a = sync(%{a | p: ap}, max(ra, 0), max(rb, 0))
      b = sync(%{b | p: bp}, max(rb, 0), max(ra, 0))
      over = %{a: ra / a.max, b: rb / b.max}
      log = def_a ++ log_b ++ def_b ++ log_a ++ st.log
      loop(%{st | a: a, b: b, log: log, round: st.round + 1, over: over})
    end
  end

  # máu đệm cho bản sao lúc tính đòn: Engine chặn máu ở 0, cần biết đòn lố bao nhiêu khi cả hai cùng gục
  @pad 10_000_000

  # một bên ra đòn (bị choáng thì Engine bỏ lượt): trả bên đó sau lượt, sát thương gây cho bên kia (chưa qua phần đỡ đòn
  # của họ), các dòng nhật ký (mới nhất trước)
  defp strike(s, foe) do
    # nhật ký trống: lấy đúng các dòng của lượt này (kỹ năng, chí mạng, nhiều đòn, trượt, thú cưng…); độc đầu lượt
    p =
      update_in(s.p, [:battle, :monster, :hp], &(&1 + @pad))
      |> put_in([:battle, :log], [])
      |> Engine.pvp_turn_start()

    before = p.battle.monster.hp

    p2 =
      if p.hp > 0 do
        {act, skill} = Engine.auto_strike(p)
        elem(Engine.act(p, act, skill), 1)
      else
        p
      end

    dealt = before - p2.battle.monster.hp

    # người xem đọc ở ngôi thứ ba: "Bạn" → tên người đánh, đối thủ giữ tên
    lines = BattleText.view(p2.battle.log, p.name, foe, foe)

    lines =
      if lines == [],
        do: [%{text: "#{p.name} ra đòn nhưng không trúng.", kind: "info"}],
        else: lines

    healed = p2.hp - s.p.hp

    heal =
      if healed > 0 and not Enum.any?(lines, &(&1.text =~ ~r/hồi|Hút/u)),
        do: [%{text: "#{p.name} hồi #{healed} máu.", kind: "good"}],
        else: []

    {%{s | p: p2}, dealt, Enum.reverse(lines ++ heal)}
  end

  # người bị đánh `p` đỡ `dmg` của `foe`: dòng nhật ký ngôi thứ ba (mới nhất trước)
  defp defend(p, dmg, foe) do
    {p, real} = Engine.pvp_defend(put_in(p, [:battle, :log], []), dmg)

    extra =
      if dmg > 0 and real < dmg,
        do: [
          %{
            text: "🛡 #{p.name} chỉ mất #{real} máu (thủ thế / khiên / thú che chắn).",
            kind: "good"
          }
        ],
        else: []

    {p, Enum.reverse(BattleText.view(p.battle.log, p.name, foe, foe) ++ extra)}
  end

  defp sync(s, hp, foe_hp) do
    p = %{s.p | hp: hp} |> put_in([:battle, :monster, :hp], foe_hp)
    %{s | p: p}
  end
end

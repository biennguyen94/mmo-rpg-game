defmodule HacLong.Game.Awaken do
  @moduledoc """
  Trùm "Thức Tỉnh" (DECISIONS "Trùm Thức Tỉnh theo sức người đánh"): nhân vật quá mạnh so với trùm (ước tính hạ bản thường
  trong ≤ `trigger_turns` lượt) gặp bản Thức Tỉnh — máu / công / thủ nhân thêm, thưởng kinh nghiệm / vàng nhân thêm, thêm
  vật phẩm khi hạ. Người chơi thường vẫn gặp bản thường. Cấu hình chung ở `RULES.awaken`, mỗi trùm bật bằng khóa riêng
  (`RULES.awaken.bosses.<khóa>`: `hp`, `atk`, `def`, `reward`, `items`).

  Ước tính số lượt (`turns/2`): đòn kỹ năng mạnh nhất đang mang (hệ số × thông thạo), × cánh, × sát thương kỹ năng,
  × kỳ vọng chí mạng, trừ thủ trùm như `Engine.damage/4` (đòn trung bình). Không tính khắc hệ, thời tiết, bùa: chỉ để
  phân biệt người thường (hàng chục lượt) với nhân vật cuối game (vài lượt).
  """

  alias HacLong.Game.{Data, Engine, Mastery}

  def rules, do: Data.rules().awaken

  @doc "Cấu hình Thức Tỉnh của trùm `key` (vd \"secret\"), nil nếu trùm đó không bật."
  def config(key), do: rules().bosses[String.to_atom(key)]

  @doc "Ước tính số lượt nhân vật `p` cần để hạ quái `m` (máu đầy)."
  def turns(p, m) do
    d = Engine.derived(p)

    best =
      p
      |> Engine.skills()
      |> Enum.map(fn k ->
        {(k[:mult] || 1) * Mastery.mult(Mastery.level(p, k.id)), k[:def_mult]}
      end)
      |> Enum.max_by(&elem(&1, 0), fn -> {1, nil} end)

    {mult, def_mult} = best
    crit = 1 + min(d.crit, 1) * max(d.critMult - 1, 0)
    raw = d.atk * mult * (1 + d.wingDmg) * (1 + d.skillDmg) * crit
    dfn = m.def * (1 - d.ignoreDef) * (def_mult || 1)
    soft = Data.rules().combat.soft_floor
    hit = if raw > 0, do: max(raw * raw / (raw + max(dfn, 0)), raw * soft), else: 0
    m.maxHp / max(hit, 1)
  end

  @doc """
  Trận đang đánh trùm `key` (`p.battle.monster`): nhân vật đủ mạnh thì đổi trùm thành bản Thức Tỉnh (đánh dấu
  `awakened: true`, tên thêm `RULES.awaken.suffix`, ghi một dòng nhật ký). Gọi sau khi đã nhân theo chuyển sinh.
  """
  def maybe(%{battle: %{monster: m}} = p, key) do
    cfg = config(key)

    if cfg && !m[:awakened] && turns(p, m) <= rules().trigger_turns do
      up = fn v, f -> if is_number(v), do: round(v * f), else: v end

      m =
        m
        |> Map.merge(%{
          maxHp: up.(m.maxHp, cfg.hp),
          hp: up.(m.maxHp, cfg.hp),
          atk: up.(m.atk, cfg.atk),
          def: up.(m.def, cfg.def),
          xp: up.(m[:xp], cfg.reward),
          # máu chung (phòng sự kiện, tổ đội): máu gốc và phần cộng thêm của người này (`shared_max/3`)
          base_max: m.maxHp,
          awaken_extra: up.(m.maxHp, cfg.hp) - m.maxHp,
          gold: up.(m[:gold], cfg.reward),
          name: m.name <> rules().suffix,
          awakened: true
        })

      p = put_in(p.battle.monster, m)

      line = %{
        text:
          "🔥 #{m.name}: cảm nhận sức mạnh của #{p.name}, trùm thức tỉnh! (máu ×#{cfg.hp}, thủ ×#{cfg.def}, công ×#{cfg.atk})",
        kind: "bad"
      }

      put_in(p.battle.log, p.battle.log ++ [line])
    else
      p
    end
  end

  def maybe(p, _key), do: p

  @doc """
  Máu chung khi nhiều người cùng đánh (phòng sự kiện, tổ đội): máu gốc `base` cộng phần thêm `extra` của MỖI người mạnh
  đã vào trận (`boosted`: những người đã cộng, mỗi người một lần). Trả `{max_mới, máu_mới, boosted_mới}` từ `{max, hp}`.
  """
  def shared_max({max, hp}, boosted, uid, extra) do
    if is_integer(extra) and extra > 0 and not MapSet.member?(boosted, uid),
      do: {max + extra, hp + extra, MapSet.put(boosted, uid)},
      else: {max, hp, boosted}
  end

  @doc "Vật phẩm thưởng thêm khi hạ bản Thức Tỉnh của trùm `key`."
  def items(key), do: (config(key) || %{})[:items] || %{}
end

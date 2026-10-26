defmodule HacLong.Game.Mastery do
  @moduledoc """
  Thông thạo kỹ năng (DECISIONS "Thông thạo kỹ năng", `RULES.skill_mastery`): mỗi kỹ năng (lớp + tháp) có cấp 1..`max`,
  luyện bằng cách dùng trong trận với quái. Thông số kỹ năng trong dữ liệu là của cấp `max`; cấp thấp hơn yếu hơn
  (hệ số sát thương, MP, hồi chiêu, tác dụng phụ). Lên các cấp `break` cần đột phá bằng Bí Kíp (hoặc Ngọc Tâm Linh).

  Lưu ở nhân vật: `skill_mastery: %{"id kỹ năng" => %{lv, xp}}`; thiếu kỹ năng nào thì là cấp 1, 0 điểm. Hàm thuần.
  """

  alias HacLong.Game.Data

  @r Data.rules().skill_mastery
  @max @r.max

  def max, do: @max
  def rules, do: @r

  @doc "Cấp và điểm của kỹ năng `id`."
  def entry(p, id) do
    case (Map.get(p, :skill_mastery) || %{})[id] do
      %{lv: lv, xp: xp} -> %{lv: lv, xp: xp}
      _ -> %{lv: 1, xp: 0}
    end
  end

  def level(p, id), do: entry(p, id).lv

  @doc "Tổng điểm cần để lên cấp `lv` (cấp 1: 0)."
  def need(lv) when lv <= 1, do: 0
  def need(lv), do: Enum.at(@r.need, min(lv, @max) - 2)

  @doc "Hệ số sát thương / hồi máu của kỹ năng ở cấp `lv` so với thông số trong dữ liệu (cấp max = 1)."
  def mult(lv), do: @r.mult_min + (1 - @r.mult_min) * (min(lv, @max) - 1) / (@max - 1)

  def mp_factor(lv), do: if(lv < @r.mp_level, do: @r.mp_low, else: 1)
  def cd_extra(lv), do: if(lv < @r.cd_level, do: @r.cd_low, else: 0)
  def effect(lv), do: if(lv < @max, do: @r.effect_low, else: 1)

  @doc "Cần đột phá để lên cấp `lv`? Trả `%{cost, alt}` hoặc nil."
  def break_cost(lv), do: Map.get(@r.break, String.to_atom(Integer.to_string(lv)))

  @doc """
  Dùng kỹ năng `skill` một lần với quái `m` (không phải người): cộng điểm, lên cấp nếu đủ (dừng ở cấp cần đột phá).
  Trả nhân vật kèm dòng nhật ký trận khi lên cấp / chờ đột phá.
  """
  def gain(p, skill, m) do
    pts = points(p, m)
    e = entry(p, skill.id)

    if pts == 0 or e.lv >= @max do
      p
    else
      xp = min(e.xp + pts, need(@max))
      {lv, waiting} = climb(e.lv, xp)
      p = put(p, skill.id, %{lv: lv, xp: xp})

      p =
        if lv > e.lv,
          do: log(p, "📘 #{skill.name} lên cấp #{lv}!", "good"),
          else: p

      # vừa đủ điểm nhưng cần đột phá: báo một lần (lúc vừa chạm mốc)
      if waiting && e.xp < need(lv + 1),
        do:
          log(
            p,
            "📘 #{skill.name} đủ điểm lên cấp #{lv + 1}: cần đột phá (Menu → Kỹ năng).",
            "info"
          ),
        else: p
    end
  end

  defp points(p, m) do
    base = if Map.get(p, :auto), do: @r.points_auto, else: @r.points
    big = m[:boss] || m[:elite] || m[:world]

    cond do
      m[:pvp] -> 0
      (m[:level] || 0) < p.level - @r.level_gap -> 0
      big -> base * @r.boss_mult
      true -> base
    end
  end

  # lên cấp theo điểm, dừng ở cấp cần đột phá (trả `waiting` = đã đủ điểm nhưng phải đột phá)
  defp climb(lv, xp) do
    cond do
      lv >= @max -> {lv, false}
      xp < need(lv + 1) -> {lv, false}
      break_cost(lv + 1) -> {lv, true}
      true -> climb(lv + 1, xp)
    end
  end

  @doc """
  Đột phá kỹ năng `id` (đã đủ điểm, đang chờ ở mốc `break`): `pay` "item" (Bí Kíp) hoặc "alt" (Ngọc Tâm Linh).
  `{result, p}`.
  """
  def break_through(p, id, pay) do
    sk = Enum.find(HacLong.Game.Engine.available_skills(p), &(&1.id == id))
    e = sk && entry(p, id)
    cost = e && break_cost(e.lv + 1)

    {item, n} =
      case {cost, pay} do
        {nil, _} -> {nil, 0}
        {c, "alt"} -> {@r.alt_item, c.alt}
        {c, _} -> {@r.item, c.cost}
      end

    cond do
      sk == nil ->
        {%{ok: false, msg: "Chưa học kỹ năng này."}, p}

      cost == nil or e.xp < need(e.lv + 1) ->
        {%{ok: false, msg: "#{sk.name} chưa tới lúc đột phá."}, p}

      Map.get(p.inv, item, 0) < n ->
        {%{ok: false, msg: "Cần #{n} #{Data.item(item).name} để đột phá."}, p}

      true ->
        {lv, _} = climb(e.lv + 1, e.xp)
        inv = Map.update!(p.inv, item, &(&1 - n))
        inv = if inv[item] <= 0, do: Map.delete(inv, item), else: inv
        p = %{p | inv: inv} |> put(id, %{lv: lv, xp: e.xp})

        {%{
           ok: true,
           msg: "📘 Đột phá thành công: #{sk.name} lên cấp #{lv}!",
           mastery: %{id: id, lv: lv}
         }, p}
    end
  end

  @doc """
  Nạp từ database: `raw` nil (nhân vật có trước tính năng) thì mọi kỹ năng đang có lên cấp max (gọi `legacy/1` sau
  khi dựng xong nhân vật); có dữ liệu thì đổi khóa chuỗi thành `%{lv, xp}`.
  """
  def load(nil), do: nil

  def load(raw) when is_map(raw) do
    for {id, v} <- raw, is_map(v), into: %{} do
      lv = v["lv"] || v[:lv] || 1
      xp = v["xp"] || v[:xp] || 0
      {to_string(id), %{lv: max(1, min(lv, @max)), xp: max(0, xp)}}
    end
  end

  def load(_), do: %{}

  @doc "Nhân vật cũ (chưa có `skill_mastery`): kỹ năng đang có = cấp max (DECISIONS: không ai bị yếu đi)."
  def legacy(%{skill_mastery: nil} = p) do
    full = %{lv: @max, xp: need(@max)}
    m = for k <- HacLong.Game.Engine.available_skills(p), into: %{}, do: {k.id, full}
    %{p | skill_mastery: m}
  end

  def legacy(p), do: p

  @doc "Mọi kỹ năng của lớp (kể cả chưa mở) lên cấp tối đa (quản trị, test)."
  def maxed(p) do
    c = Data.class(p.cls)
    full = %{lv: @max, xp: need(@max)}
    Map.put(p, :skill_mastery, Map.new(c.skills ++ (c[:tower_skills] || []), &{&1.id, full}))
  end

  @doc "Cho client (`view.mastery`): `%{id => %{lv, xp, prev, next, brk}}` mọi kỹ năng đã có."
  def view(p) do
    for k <- HacLong.Game.Engine.available_skills(p), into: %{} do
      e = entry(p, k.id)
      next = if e.lv < @max, do: need(e.lv + 1)
      brk = next && e.xp >= next && break_cost(e.lv + 1)
      {k.id, %{lv: e.lv, xp: e.xp, prev: need(e.lv), next: next, brk: brk || nil}}
    end
  end

  defp put(p, id, e),
    do: Map.put(p, :skill_mastery, Map.put(Map.get(p, :skill_mastery) || %{}, id, e))

  defp log(%{battle: %{log: l} = b} = p, text, kind),
    do: %{p | battle: %{b | log: Enum.take(l ++ [%{text: text, kind: kind}], -60)}}

  defp log(p, _text, _kind), do: p
end

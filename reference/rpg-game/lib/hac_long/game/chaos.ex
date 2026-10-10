defmodule HacLong.Game.Chaos do
  @moduledoc """
  Máy Hỗn Nguyên (Lão Hỗn Nguyên ở Làng): ghép đồ may rủi theo công thức `CHAOS` trong
  `priv/game_data/chaos.json`. Hàm thuần như `Engine`, số ngẫu nhiên qua `HacLong.Game.Rng`.

  Công thức: `items` (nguyên liệu trong túi), `gold` (phí), `rate` (tỉ lệ cơ bản), `out` (kết quả;
  `{cls}` thay bằng lớp nhân vật). Công thức có `gear` cần thêm đúng một món đồ trong túi
  (không mặc, không khóa) ở ô `slots`, cấp nâng ≥ `min_up` (và cánh cấp `tier` nếu có); mỗi cấp
  trên `min_up` cộng `per_up` vào tỉ lệ, tối đa `max_rate`.

  Công thức có `mode` (Phase 15f, `docs/ITEMS_PHASE15B.md` §9) không có `out`: thành công thì **chính món đồ**
  bỏ vào được thêm dòng (`"excellent"`: 1 dòng Excellent, tối đa 3; `"luck"`: dòng May mắn), giữ nguyên cấp nâng.

  Thất bại: **mất hết** nguyên liệu, món đồ và phí. Thành công ra cánh thì báo cả server.
  """

  alias HacLong.Game.{Data, Engine, Gear, Rng}

  @doc "Tỉ lệ thành công của công thức `r` với món đồ đặt vào (cấp nâng `up`)."
  def rate(r, up \\ 0) do
    extra = if r[:gear], do: (r[:per_up] || 0) * max(0, up - r.gear.min_up), else: 0
    min(r[:max_rate] || 1.0, r.rate + extra) |> Float.round(3)
  end

  @doc "Món ra của công thức với lớp nhân vật `cls`."
  def output(%{mode: _}, _cls), do: nil
  def output(r, cls), do: String.replace(r.out, "{cls}", cls)

  @doc """
  Ghép theo công thức `id`, với món đồ `uid` (công thức cần đồ). Trả về `{kết_quả, nhân_vật}`;
  kết quả có `chaos: %{result: "success" | "fail", out}`.
  """
  def combine(p, id, uid) do
    r = is_binary(id) && Data.chaos(id)

    with {:ok, r} <- (r && {:ok, r}) || {:error, "Không có công thức này."},
         :ok <- if(p.battle, do: {:error, "Đang trong trận."}, else: :ok),
         {:ok, g, up} <- gear_input(p, r, uid) do
      if r[:mode], do: transform(p, r, g, up), else: make(p, r, g, up)
    else
      {:error, msg} -> {%{ok: false, msg: msg}, p}
    end
  end

  # công thức ra món mới (`out`)
  defp make(p, r, g, up) do
    with out = output(r, p.cls),
         %{} = out_item <- Data.item(out) || {:error, "Lớp này chưa có kết quả cho công thức."},
         :ok <- enough(p, r) do
      p = pay(p, r, g)
      rate = rate(r, up)

      if Rng.uniform() < rate do
        success(p, r, out, out_item)
      else
        what = if g, do: "#{Gear.resolve(g).name} +#{up}, ", else: ""

        {%{
           ok: true,
           msg:
             "💥 Ghép #{r.name} thất bại (#{round(rate * 100)}%). Mất #{what}nguyên liệu và #{r.gold} vàng.",
           chaos: %{result: "fail", out: out}
         }, p}
      end
    else
      {:error, msg} -> {%{ok: false, msg: msg}, p}
    end
  end

  # công thức `mode`: thêm dòng cho chính món `g` (cấp nâng `up` giữ nguyên khi thành công)
  defp transform(p, r, g, up) do
    it = Gear.resolve(g)

    with :ok <- mode_ok(r.mode, g, it),
         :ok <- enough(p, r) do
      p = pay(p, r, nil)
      rate = rate(r, up)

      if Rng.uniform() < rate do
        g2 = add_line(r.mode, g)
        p = Map.put(p, :gear, Enum.map(Gear.list(p), &if(&1.uid == g.uid, do: g2, else: &1)))

        {%{
           ok: true,
           msg: "✨ #{r.name} thành công: #{Gear.resolve(g2).name} +#{up} #{line_text(r.mode)}!",
           chaos: %{result: "success", out: g.base}
         }, p}
      else
        p = p |> Gear.remove(g.uid)
        p = Map.put(p, :upgrades, Map.delete(Map.get(p, :upgrades) || %{}, g.uid))

        {%{
           ok: true,
           msg:
             "💥 #{r.name} thất bại (#{round(rate * 100)}%). Mất #{it.name} +#{up}, nguyên liệu và #{r.gold} vàng.",
           chaos: %{result: "fail", out: g.base}
         }, p}
      end
    else
      {:error, msg} -> {%{ok: false, msg: msg}, p}
    end
  end

  defp mode_ok("excellent", g, it) do
    if length(g[:exc] || []) < min(3, length(Gear.exc_pool(it.slot))),
      do: :ok,
      else: {:error, "#{it.name} đã đủ dòng Excellent."}
  end

  defp mode_ok("luck", g, it),
    do: if(g[:luck], do: {:error, "#{it.name} đã có May mắn."}, else: :ok)

  defp mode_ok(_, _, _), do: {:error, "Công thức không hợp lệ."}

  defp add_line("excellent", g), do: Gear.add_exc_line(g)
  defp add_line("luck", g), do: Map.put(g, :luck, true)

  defp line_text("excellent"), do: "có thêm dòng Excellent"
  defp line_text("luck"), do: "có May mắn"

  defp gear_input(p, %{gear: need}, uid) do
    g = is_binary(uid) && Gear.find(p, uid)
    it = g && Gear.resolve(g)
    up = if g, do: Engine.upgrade_level(p, uid), else: 0

    cond do
      !g -> {:error, "Chọn một món đồ để bỏ vào máy."}
      Gear.equipped?(p, uid) -> {:error, "Tháo #{it.name} ra trước đã."}
      g[:stored] -> {:error, "#{it.name} đang cất trong tủ."}
      g[:locked] -> {:error, "#{it.name} đang khóa. Mở khóa trước khi bỏ vào máy."}
      it.slot not in need.slots -> {:error, "Công thức này không nhận #{it.name}."}
      need[:tier] && it[:tier] != need.tier -> {:error, "Công thức này không nhận #{it.name}."}
      up < need.min_up -> {:error, "#{it.name} cần nâng tới +#{need.min_up} trở lên."}
      true -> {:ok, g, up}
    end
  end

  defp gear_input(_p, _r, _uid), do: {:ok, nil, 0}

  defp enough(p, r) do
    missing =
      r.items
      |> Enum.filter(fn {m, n} -> Map.get(p.inv, m, 0) < n end)
      |> Enum.map_join(", ", fn {m, n} -> "#{Data.item(m).name} #{Map.get(p.inv, m, 0)}/#{n}" end)

    cond do
      missing != "" -> {:error, "Thiếu nguyên liệu: #{missing}."}
      p.gold < r.gold -> {:error, "Cần #{r.gold} vàng."}
      true -> :ok
    end
  end

  defp pay(p, r, g) do
    inv =
      Enum.reduce(r.items, p.inv, fn {m, n}, inv ->
        if inv[m] > n, do: Map.put(inv, m, inv[m] - n), else: Map.delete(inv, m)
      end)

    p = %{p | inv: inv, gold: p.gold - r.gold}

    if g do
      p = Gear.remove(p, g.uid)
      Map.put(p, :upgrades, Map.delete(Map.get(p, :upgrades) || %{}, g.uid))
    else
      p
    end
  end

  defp success(p, _r, out, %{slot: "material"} = it) do
    {%{ok: true, msg: "✨ Ghép thành công: #{it.name}!", chaos: %{result: "success", out: out}},
     Engine.add_item(p, out)}
  end

  defp success(p, _r, out, it) do
    # món đồ vào máy vừa ra khỏi túi nên luôn còn chỗ cho kết quả
    # cánh bậc có dòng phụ (Phase 15e, `RULES.wing_options`) bốc một dòng
    p = Map.put(p, :gear, (Map.get(p, :gear) || []) ++ [Gear.wing_option(Gear.plain(out))])

    {%{
       ok: true,
       msg: "✨ Ghép thành công: #{it.name}!",
       chaos: %{result: "success", out: out},
       announce: "📢 #{p.name} vừa ghép thành công #{it.name} ở Máy Hỗn Nguyên!"
     }, p}
  end
end

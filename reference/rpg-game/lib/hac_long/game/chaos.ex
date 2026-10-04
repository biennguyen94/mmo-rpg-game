defmodule HacLong.Game.Chaos do
  @moduledoc """
  Máy Hỗn Nguyên (Lão Hỗn Nguyên ở Làng): ghép đồ may rủi theo công thức `CHAOS` trong
  `game_data.json`. Hàm thuần như `Engine`, số ngẫu nhiên qua `HacLong.Game.Rng`.

  Công thức: `items` (nguyên liệu trong túi), `gold` (phí), `rate` (tỉ lệ cơ bản), `out` (kết quả;
  `{cls}` thay bằng lớp nhân vật). Công thức có `gear` cần thêm đúng một món đồ trong túi
  (không mặc, không khóa) ở ô `slots`, cấp nâng ≥ `min_up` (và cánh cấp `tier` nếu có); mỗi cấp
  trên `min_up` cộng `per_up` vào tỉ lệ, tối đa `max_rate`.

  Thất bại: **mất hết** nguyên liệu, món đồ và phí. Thành công ra cánh thì báo cả server.
  """

  alias HacLong.Game.{Data, Engine, Gear, Rng}

  @doc "Tỉ lệ thành công của công thức `r` với món đồ đặt vào (cấp nâng `up`)."
  def rate(r, up \\ 0) do
    extra = if r[:gear], do: (r[:per_up] || 0) * max(0, up - r.gear.min_up), else: 0
    min(r[:max_rate] || 1.0, r.rate + extra) |> Float.round(3)
  end

  @doc "Món ra của công thức với lớp nhân vật `cls`."
  def output(r, cls), do: String.replace(r.out, "{cls}", cls)

  @doc """
  Ghép theo công thức `id`, với món đồ `uid` (công thức cần đồ). Trả về `{kết_quả, nhân_vật}`;
  kết quả có `chaos: %{result: "success" | "fail", out}`.
  """
  def combine(p, id, uid) do
    r = is_binary(id) && Data.chaos(id)

    with {:ok, r} <- (r && {:ok, r}) || {:error, "Không có công thức này."},
         :ok <- if(p.battle, do: {:error, "Đang trong trận."}, else: :ok),
         {:ok, g, up} <- gear_input(p, r, uid),
         out = output(r, p.cls),
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

  defp gear_input(p, %{gear: need}, uid) do
    g = is_binary(uid) && Gear.find(p, uid)
    it = g && Gear.resolve(g)
    up = if g, do: Engine.upgrade_level(p, uid), else: 0

    cond do
      !g -> {:error, "Chọn một món đồ để bỏ vào máy."}
      Gear.equipped?(p, uid) -> {:error, "Tháo #{it.name} ra trước đã."}
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
    p = Map.put(p, :gear, (Map.get(p, :gear) || []) ++ [Gear.plain(out)])

    {%{
       ok: true,
       msg: "✨ Ghép thành công: #{it.name}!",
       chaos: %{result: "success", out: out},
       announce: "📢 #{p.name} vừa ghép thành công #{it.name} ở Máy Hỗn Nguyên!"
     }, p}
  end
end

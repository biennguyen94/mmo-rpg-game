defmodule HacLong.Game.AutoHunt do
  @moduledoc """
  Tự đánh quái (Phase 4, `DECISIONS.md` B-31): chỉ chạy khi người chơi đang online (còn tab mở), trên bản đồ đang đứng.

  Cài đặt nằm ở `p.auto` (chỉ trong bộ nhớ, không lưu database; đóng hết tab là tắt):
  `%{map, target, hp, mp, loot, keep, range, origin, skills, kills}`. Bật là lưu cài đặt (trừ bản đồ, chỗ bật, số
  quái) vào `p.auto_cfg` (cột `characters.auto_cfg`) để lần sau, máy khác, mở lại đúng như cũ.

  - `target`: `"all"` (mọi quái trên bản đồ), `"level"` (quái cấp không quá cấp mình + 1; bản đồ không có con nào
    như vậy, vd vùng chuyển sinh, thì mọi quái) hoặc mã một loại quái có trên bản đồ.
  - `hp`, `mp`: % máu / MP dưới mức này thì uống bình (`RULES.auto.hp_pct`, `mp_pct`).
  - `loot`: `"all"` giữ mọi đồ rơi; `"pick"` hủy món đồ vừa nhặt không thuộc loại nào trong `keep`
    (`RULES.auto.keep`: exc, anc, luck, opt, better, cls; cánh / nhẫn / dây chuyền / ngọc / nguyên liệu luôn giữ).
    `"good"` cũ đọc như `"pick"` với `RULES.auto.keep_default`.
  - `range`: 0 săn cả bản đồ; N chỉ đánh quái trong N ô (Manhattan) quanh `origin` (chỗ bật), hết quái thì về `origin`.
  - `skills`: `"all"` dùng bộ kỹ năng (buff trước), `"basic"` chỉ đòn thường, `"boss"` chỉ dùng kỹ năng với trùm /
    tinh anh / quái vàng / quái Bóng Đêm (`Brain.fight/4`).
  - `kills`: số quái đã hạ lúc bật (client hiện số hạ được từ lúc bật).

  `decide/2` là hàm thuần: từ nhân vật và trạng thái bản đồ (`MapServer.snapshot/1`) trả `{:cmd, lệnh}` (lệnh như
  client gửi, chạy qua `Session` nên theo đúng luật và giới hạn tốc độ), `:wait` hoặc `{:stop, lý_do}`. Dùng lại
  `HacLong.Bots.Brain` (đánh, tìm đường), kỹ năng là bộ 4 kỹ năng đang mang (`Engine.skills/1`).

  Dừng khi: hết bình máu, có người tên đỏ (đồ sát) trên bản đồ, bị đồ sát, thua / bỏ chạy, rời bản đồ.
  """
  alias HacLong.Bots.Brain
  alias HacLong.Game.{Data, Engine, Gear}
  alias HacLong.World.Maps

  @r Data.rules().auto

  @doc "Nhịp (ms) tới lần ra lệnh sau, theo lệnh vừa gửi."
  def delay(%{battle: %{}}, _cmd), do: @r.tick_ms.battle
  def delay(_p, %{"act" => "move"}), do: @r.tick_ms.move
  def delay(_p, _cmd), do: @r.tick_ms.idle

  @doc "Bản đồ tự đánh được: có quái hồi sinh, không riêng, không phải Tháp / Hỗn Chiến Thành / Công Thành Chiến."
  def map_ok?(id) do
    m = Maps.get(id)

    m != nil and not m.private and m.spawns != [] and
      id not in ["tower", HacLong.ChaosCastle.map_id(), HacLong.CastleSiege.map_id()]
  end

  @doc "Loại quái (mã, tên, cấp) trên bản đồ `id`, để client cho chọn."
  def kinds(id) do
    case Maps.get(id) do
      nil ->
        []

      m ->
        m.spawns
        |> Enum.map(& &1.monster)
        |> Enum.uniq()
        |> Enum.map(&%{id: &1, level: Brain.monster_level(m, &1), name: name(&1)})
    end
  end

  defp name(kind), do: (Data.side_monster(kind) || Data.monster(kind) || %{name: kind}).name

  @doc """
  Lệnh `"auto"`: `on` false tắt; true bật với `target`, `hp`, `mp`, `loot` (thiếu hoặc sai thì lấy mặc định,
  % kẹp trong giới hạn). Trả `{kết_quả, nhân_vật}` như `Commands.run/2`.
  """
  def configure(p, %{"on" => false}), do: {%{ok: true, msg: "Đã tắt tự đánh."}, stop(p)}

  def configure(p, c) do
    id = p.pos.map
    kinds = Enum.map(kinds(id), & &1.id)
    target = c["target"]

    cond do
      not map_ok?(id) ->
        {%{ok: false, msg: "Bản đồ này không tự đánh được."}, p}

      target not in ["all", "level"] and target not in kinds ->
        {%{ok: false, msg: "Chọn quái có trên bản đồ này."}, p}

      true ->
        {loot, keep} = loot(c["loot"], c["keep"])

        auto = %{
          map: id,
          target: target,
          hp: pct(c["hp"], @r.hp_pct),
          mp: pct(c["mp"], @r.mp_pct),
          loot: loot,
          keep: keep,
          range: if(c["range"] in @r.range_options, do: c["range"], else: @r.range_default),
          origin: [p.pos.x, p.pos.y],
          skills: if(c["skills"] in @r.skills, do: c["skills"], else: "all"),
          kills: p.kills
        }

        cfg =
          auto
          |> Map.take([:target, :hp, :mp, :loot, :keep, :range, :skills])
          |> Map.new(fn {k, v} -> {to_string(k), v} end)

        {%{ok: true, msg: "Bắt đầu tự đánh."},
         p |> Map.put(:auto, auto) |> Map.put(:auto_cfg, cfg)}
    end
  end

  # "good" (bản cũ) = lọc theo mặc định
  defp loot("good", _keep), do: {"pick", @r.keep_default}

  defp loot("pick", keep) when is_list(keep),
    do: {"pick", Enum.filter(@r.keep, &(&1 in keep))}

  defp loot("pick", _keep), do: {"pick", @r.keep_default}
  defp loot(_, _keep), do: {"all", @r.keep_default}

  defp pct(v, r) when is_integer(v), do: v |> max(r.min) |> min(r.max)
  defp pct(_v, r), do: r.default

  @doc "Tắt tự đánh."
  def stop(p), do: Map.delete(p, :auto)

  def on?(p), do: match?(%{auto: %{}}, p)

  @doc "Lệnh tự đánh tiếp theo (xem moduledoc)."
  def decide(%{auto: a} = p, snap) do
    d = Engine.derived(p)
    hp = a.hp / 100

    case p.battle do
      %{over: true} = b ->
        after_battle(p, b, a)

      %{live: true} ->
        {:stop, "Bạn bị đồ sát — tự đánh đã tắt."}

      %{} ->
        if p.hp < d.maxHp * hp and Engine.best_potion(p, d.maxHp - p.hp) == nil,
          do: {:stop, "Hết bình máu — tự đánh đã tắt."},
          else: {:cmd, Brain.fight(p, hp, a.mp / 100, Map.get(a, :skills, "all"))}

      nil ->
        roam(p, snap, a, d, hp)
    end
  end

  defp after_battle(p, b, a) do
    cond do
      b.result != "win" ->
        {:stop,
         if(b.result == "lose",
           do: "Bạn đã gục — tự đánh đã tắt.",
           else: "Đã rời trận — tự đánh đã tắt."
         )}

      id = a.loot == "pick" && junk(p, b, a.keep) ->
        {:cmd, %{"act" => "discard", "id" => id}}

      true ->
        {:cmd, %{"act" => "leave"}}
    end
  end

  # món đồ thường vừa nhặt (còn trong túi, chưa khóa) đầu tiên
  defp junk(p, b, keep) do
    reward = b[:reward] || %{}

    Enum.find(reward[:gear_ids] || [], fn uid ->
      g = Gear.find(p, uid)
      g != nil and !g[:locked] and !g[:stored] and not good?(p, Gear.resolve(g), keep)
    end)
  end

  @doc "Món đáng giữ khi lọc `\"pick\"` theo các loại `keep` (xem moduledoc)."
  def good?(p, it, keep \\ @r.keep_default) do
    it.slot not in Engine.gear_slots() or it.slot in ["ring", "pendant"] or
      Enum.any?(keep, &keep?(&1, p, it))
  end

  defp keep?("exc", _p, it), do: it.exc != []
  defp keep?("anc", _p, it), do: it.anc == true
  defp keep?("luck", _p, it), do: it.luck == true or it.skill == true
  defp keep?("opt", _p, it), do: it.opt >= @r.keep_opt_min
  defp keep?("better", p, it), do: better?(p, it)
  defp keep?("cls", p, it), do: Engine.can_wear?(p, it)
  defp keep?(_, _p, _it), do: false

  defp better?(p, it) do
    Engine.can_wear?(p, it) and
      Brain.power(it) > Brain.power(Gear.item(p, p.equip[Engine.equip_slot(p, it)]))
  end

  defp roam(p, snap, a, d, hp) do
    cond do
      p.pos.map != a.map ->
        {:stop, "Đã rời bản đồ — tự đánh đã tắt."}

      snap != nil and Enum.any?(snap.players, &(&1.red and &1.name != p.name)) ->
        {:stop, "Có người tên đỏ gần đây — tự đánh đã tắt."}

      Engine.best_potion(p, d.maxHp) == nil ->
        {:stop, "Hết bình máu — tự đánh đã tắt."}

      p.hp < d.maxHp * hp ->
        {:cmd, %{"act" => "use", "id" => Engine.best_potion(p, d.maxHp - p.hp)}}

      true ->
        hunt(p, snap, a)
    end
  end

  # cả bản đồ: như bot (không có quái thì đi lang thang)
  defp hunt(p, snap, %{range: r} = a) when r > 0 do
    [ox, oy] = a.origin
    near = keep(p, a)
    keep = fn m, map -> abs(m.x - ox) + abs(m.y - oy) <= r and near.(m, map) end

    cond do
      cmd = Brain.hunt(p, snap, keep, false) -> {:cmd, cmd}
      [p.pos.x, p.pos.y] == a.origin -> :wait
      cmd = Brain.walk(p, Maps.get(p.pos.map), [{ox, oy}], snap) -> {:cmd, cmd}
      true -> :wait
    end
  end

  defp hunt(p, snap, a) do
    case Brain.hunt(p, snap, keep(p, a)) do
      nil -> :wait
      cmd -> {:cmd, cmd}
    end
  end

  defp keep(_p, %{target: "all"}), do: fn _m, _map -> true end

  defp keep(p, %{target: "level"}) do
    map = Maps.get(p.pos.map)
    fit = for k <- kinds(map.id), k.level <= p.level + 1, do: k.id
    fit = if fit == [], do: Enum.map(kinds(map.id), & &1.id), else: fit
    fn m, _map -> m.kind in fit end
  end

  defp keep(_p, %{target: kind}), do: fn m, _map -> m.kind == kind end
end

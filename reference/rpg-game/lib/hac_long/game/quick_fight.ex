defmodule HacLong.Game.QuickFight do
  @moduledoc """
  ⚡ Đánh nhanh theo combo (DECISIONS "Đánh nhanh theo combo", `RULES.quick`). Hàm thuần.

  - Bật / tắt và combo lưu trong `p.auto_cfg` (cột `characters.auto_cfg`, theo nhân vật, đổi máy vẫn còn):
    `"quick"` (bool), `"combo"` = `[%{"id" => mã kỹ năng | "attack", "once" => bool}]` (tối đa `max_steps` bước).
  - Đang bật, đang trong trận với quái hoặc đấu trường (bản sao; đồ sát có nhánh riêng), không bật Tự đánh, chưa bấm ✋ Đánh tay
    (`battle.manual`): `Session` mỗi `tick_ms` hỏi `decide/1` rồi chạy lệnh như client gửi.
  - `decide/1`: trận xong → rời màn trận (`leave`); máu / MP dưới ngưỡng % của Tự đánh → uống bình; không thì bước
    đầu tiên của combo dùng được (kỹ năng đang mang, hết hồi chiêu, đủ MP; `once` thì bỏ qua khi hiệu ứng của kỹ năng
    còn trên người); không bước nào dùng được → đòn thường. Combo trống: theo thứ tự bộ kỹ năng (ô 1 → ô 5), buff đang còn thì bỏ qua.
  """
  alias HacLong.Game.{Data, Engine}

  @r Data.rules().quick
  @auto Data.rules().auto

  def tick_ms, do: @r.tick_ms
  def max_steps, do: @r.max_steps

  defp cfg(p), do: Map.get(p, :auto_cfg) || %{}

  def on?(p), do: cfg(p)["quick"] == true

  @doc "Combo đang lưu (đã bỏ bước không còn dùng được, vd đổi bộ kỹ năng)."
  def combo(p) do
    ids = ["attack" | Enum.map(Engine.skills(p), & &1.id)]

    for %{"id" => id} = s <- cfg(p)["combo"] || [],
        id in ids,
        do: %{"id" => id, "once" => s["once"] == true}
  end

  @doc "Đang đánh nhanh trận hiện tại không."
  # ⚡ Đồ sát nhanh (DECISIONS "Người chơi trên bản đồ, Đồ sát nhanh"): lượt của mình thì server đánh theo combo,
  # trận xong thì rời; lượt người kia thì chờ (`Session.slay_sync` hẹn nhịp khi tới lượt mình)
  def active?(%{battle: %{encounter: %{slay: _} = e} = b} = p) do
    on?(p) and not match?(%{auto: %{}}, p) and b[:manual] != true and
      (b.over == true or e[:mine] == true)
  end

  def active?(%{battle: %{} = b} = p) do
    # E1: đấu trường (bản sao chỉ số, `monster.arena`) cũng tự đánh lượt theo combo
    on?(p) and not match?(%{auto: %{}}, p) and b[:manual] != true and
      (b.monster[:pvp] == nil or b.monster[:arena] == true) and
      b[:live] != true and b[:encounter][:slay] == nil
  end

  def active?(_p), do: false

  @doc "Lệnh `quick`: bật / tắt."
  def toggle(p, on) do
    p = put_cfg(p, "quick", on == true)

    {%{
       ok: true,
       msg:
         if(on == true,
           do: "⚡ Đánh nhanh: bấm quái là tự đánh theo combo.",
           else: "Đã tắt Đánh nhanh."
         )
     }, p}
  end

  @doc "Lệnh `combo_set`: lưu combo (`steps`: danh sách `%{id, once}`)."
  def set_combo(p, steps) when is_list(steps) do
    ids = ["attack" | Enum.map(Engine.skills(p), & &1.id)]

    combo =
      for s <- steps,
          is_map(s),
          id = s["id"],
          id in ids,
          do: %{"id" => id, "once" => s["once"] == true}

    cond do
      length(steps) > @r.max_steps ->
        {%{ok: false, msg: "Combo tối đa #{@r.max_steps} bước."}, p}

      length(combo) != length(steps) ->
        {%{ok: false, msg: "Combo chỉ gồm đòn thường và kỹ năng đang mang."}, p}

      true ->
        {%{ok: true, msg: "Đã lưu combo."}, put_cfg(p, "combo", combo)}
    end
  end

  def set_combo(p, _), do: {%{ok: false, msg: "Combo không hợp lệ."}, p}

  @doc "Lệnh `quick_manual`: trận này cầm lại quyền đánh tay."
  def manual(%{battle: %{} = b} = p), do: {%{ok: true}, %{p | battle: Map.put(b, :manual, true)}}
  def manual(p), do: {%{ok: false, msg: "Không có trận đấu."}, p}

  defp put_cfg(p, k, v), do: Map.put(p, :auto_cfg, Map.put(cfg(p), k, v))

  @doc "Lệnh tiếp theo của trận đánh nhanh (xem moduledoc)."
  def decide(%{battle: %{over: true}}), do: %{"act" => "leave"}

  def decide(p) do
    c = cfg(p)
    hp = (c["hp"] || @auto.hp_pct.default) / 100
    mp = (c["mp"] || @auto.mp_pct.default) / 100
    d = Engine.derived(p)
    cur_mp = Map.get(p, :mp) || 0

    cond do
      p.hp < d.maxHp * hp and Engine.best_potion(p, d.maxHp - p.hp) != nil and
          Engine.potion_ready?(p) ->
        %{"act" => "potion"}

      cur_mp < d.maxMp * mp and Engine.best_mana(p, d.maxMp - cur_mp) != nil and
          Engine.mana_ready?(p) ->
        %{"act" => "mana"}

      # còn kỹ năng trong combo đã hồi chiêu xong mà chỉ thiếu MP: uống mana để dùng tiếp vòng kỹ năng, không đánh thường
      starved?(p, combo(p)) and Engine.best_mana(p, d.maxMp - cur_mp) != nil and
          Engine.mana_ready?(p) ->
        %{"act" => "mana"}

      true ->
        step(p, combo(p))
    end
  end

  # bước kỹ năng của combo (combo trống: bộ kỹ năng) đã hồi chiêu xong nhưng không đủ MP, và không bước nào dùng được ngay
  defp starved?(p, combo) do
    combo =
      if combo == [],
        do: Enum.map(Engine.skills(p), &%{"id" => &1.id, "once" => true}),
        else: combo

    step(p, combo) == %{"act" => "attack"} and
      Enum.any?(combo, fn %{"id" => id} = st ->
        k = Enum.find(Engine.skills(p), &(&1.id == id))

        k != nil and Engine.cooldown(p, id) == 0 and
          (Map.get(p, :mp) || 0) < Engine.skill_mp(p, k) and
          not (st["once"] and Engine.buff_active?(p, k))
      end)
  end

  # combo trống: đúng thứ tự bộ kỹ năng (ô 1 → ô 5; buff đang còn thì bỏ qua), rồi đòn thường
  defp step(p, []),
    do: step(p, Enum.map(Engine.skills(p), &%{"id" => &1.id, "once" => true}))

  defp step(p, combo) do
    mp = Map.get(p, :mp) || 0
    skills = Map.new(Engine.skills(p), &{&1.id, &1})

    Enum.find_value(combo, %{"act" => "attack"}, fn
      %{"id" => "attack"} ->
        %{"act" => "attack"}

      %{"id" => id, "once" => once} ->
        k = skills[id]

        if k && Engine.cooldown(p, id) == 0 && mp >= Engine.skill_mp(p, k) &&
             not (once and Engine.buff_active?(p, k)),
           do: %{"act" => "skill", "skill" => id}
    end)
  end
end

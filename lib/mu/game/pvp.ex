defmodule Mu.Game.Pvp do
  @moduledoc """
  Luật PvP / PK (`KB_GAME_DESIGN §13`, P4-2 / P4-3), **hàm thuần**. Không dùng một boolean
  `isPvP` (§13): mỗi lần đánh người chơi hỏi các hàm này theo **quan hệ** giữa hai người (tự vệ;
  duel / guild war ở P4-M2 / M4) và **trạng thái PK** của từng người.

  Người chơi (entity MapServer) cần các khóa: `character_id`, `level`, `x`, `y`, `pk_points`,
  `rights` (`%{character_id => hạn ms}` — người mình được đánh trả vì tự vệ),
  `aggressor_until` (hạn ms đang là kẻ gây sự, hoặc `nil`).

  - Trạng thái: `pk_points` < `pk.warningAt` → `NORMAL`; < `pk.murdererAt` → `WARNING`; còn lại
    `MURDERER`.
  - Đánh được khi `features.pvp`, không đánh chính mình, cả hai cấp ≥ `pvp.minLevel`, không ai
    đứng trong safe zone.
  - **Quan hệ** (MapServer tính): `:duel` (đang duel với nhau — không tự vệ, không PK, P4-M2),
    `:party` (cùng nhóm — không đánh được, P4M1-2), `:blocked` (một bên đang duel với người khác
    — "vùng riêng" của duel, P4-4), `:none`.
  - Tự vệ: A đánh B (B `NORMAL`, A không phải đang đánh trả B) → B được đánh trả A trong
    `pk.selfDefenseSeconds`, A thành kẻ gây sự cùng thời gian; mỗi đòn của A làm mới.
  - PK: giết người `NORMAL` mà không phải đang tự vệ → +1 điểm. Giết `WARNING` / `MURDERER` không
    tính PK.
  - Giảm: 1 điểm mỗi `pk.decayMinutes` tính từ `last_pk_at` (giờ thực).
  """

  alias Mu.Game.Config

  @type state :: String.t()

  @doc "Trạng thái PK theo số điểm."
  @spec state(non_neg_integer()) :: state()
  def state(points) do
    pk = Config.get(["pk"])

    cond do
      points >= pk["murdererAt"] -> "MURDERER"
      points >= pk["warningAt"] -> "WARNING"
      true -> "NORMAL"
    end
  end

  @doc """
  `attacker` đánh `target` (người chơi) được không: `:ok` hoặc `{:error, code}`. `safe?.(x, y)`
  cho biết ô có trong safe zone không.
  """
  def check_attack(attacker, target, safe?, relation \\ :none) do
    min = Config.get(["pvp", "minLevel"])

    cond do
      Config.get(["features", "pvp"]) != true -> {:error, "FORBIDDEN"}
      attacker.character_id == target.character_id -> {:error, "INVALID_TARGET"}
      relation in [:party, :blocked] -> {:error, "FORBIDDEN"}
      attacker.level < min or target.level < min -> {:error, "REQUIREMENT_NOT_MET"}
      safe?.(attacker.x, attacker.y) or safe?.(target.x, target.y) -> {:error, "FORBIDDEN"}
      true -> :ok
    end
  end

  @doc "`attacker` đang có quyền đánh trả `victim` (tự vệ) lúc `now` (ms)."
  def retaliating?(attacker, victim, now),
    do: Map.get(attacker.rights, victim.character_id, 0) > now

  @doc """
  Sau một đòn `attacker` → `victim` lúc `now`: cập nhật quyền tự vệ của nạn nhân và cờ kẻ gây sự.
  Trả `{attacker, victim}`.
  """
  def on_hit(attacker, victim, now, relation \\ :none)
  def on_hit(attacker, victim, _now, :duel), do: {attacker, victim}

  def on_hit(attacker, victim, now, _relation) do
    if state(victim.pk_points) == "NORMAL" and not retaliating?(attacker, victim, now) do
      until = now + Config.get(["pk", "selfDefenseSeconds"]) * 1000

      {%{attacker | aggressor_until: until},
       %{victim | rights: Map.put(victim.rights, attacker.character_id, until)}}
    else
      {attacker, victim}
    end
  end

  @doc "Điểm PK `killer` nhận khi hạ `victim` lúc `now`: 1 hoặc 0."
  def pk_gain(killer, victim, now, relation \\ :none)
  def pk_gain(_killer, _victim, _now, :duel), do: 0

  def pk_gain(killer, victim, now, _relation) do
    if state(victim.pk_points) == "NORMAL" and not retaliating?(killer, victim, now),
      do: 1,
      else: 0
  end

  @doc "Tỉ lệ rơi 1 món trong túi khi bị người chơi giết, theo trạng thái PK của nạn nhân."
  def drop_chance(points), do: Config.get(["pk", "dropChance", state(points)]) || 0

  @doc "Sát thương người → người: × `pvp.damageMultiplier`, làm tròn xuống, đòn trúng tối thiểu 1."
  def damage(dmg) when dmg <= 0, do: 0
  def damage(dmg), do: max(1, floor(dmg * Config.get(["pvp", "damageMultiplier"])))

  @doc """
  Giảm điểm theo thời gian: mỗi `pk.decayMinutes` kể từ `last_pk_at` bớt 1 điểm. Trả
  `{điểm, last_pk_at}` (mốc dời theo số lần đã giảm để lần sau tính tiếp; hết điểm thì `nil`).
  """
  def decay(0, _last, _now), do: {0, nil}
  def decay(points, nil, now), do: {points, now}

  def decay(points, %DateTime{} = last, %DateTime{} = now) do
    step = Config.get(["pk", "decayMinutes"]) * 60
    n = min(points, div(max(DateTime.diff(now, last, :second), 0), step))

    cond do
      n == 0 -> {points, last}
      points - n == 0 -> {0, nil}
      true -> {points - n, DateTime.add(last, n * step, :second)}
    end
  end
end

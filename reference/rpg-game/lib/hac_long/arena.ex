defmodule HacLong.Arena do
  @moduledoc """
  Đấu trường (PvP bất đồng bộ): đánh với bản sao chỉ số của người chơi khác, người đó không
  cần online.

  - Bản sao dựng từ nhân vật đã lưu của đối thủ (`opponent/1`): máu, tấn công, phòng thủ, chí
    mạng, né như lúc họ mặc đồ; dùng kỹ năng đầu của lớp như đòn đặc biệt mỗi 3 lượt.
  - Thắng/thua đổi điểm Elo của cả hai (`finish/3`, K = 32). Gục ngã tính như chết thường
    (mất vàng, về Nhà); bỏ chạy thì không mất vàng, máu như trước trận. Người thắng (người
    thách đấu) được một ít vàng.
  - Mỗi ngày (giờ Việt Nam) đấu tối đa `@per_day` trận.
  """
  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Game.{Character, Characters, Daily, Data, Engine}

  # số ở `RULES.arena` (`priv/game_data/rules.json`)
  @per_day Data.rules().arena.per_day
  @k Data.rules().arena.elo_k

  def per_day, do: @per_day

  # ---------- Điểm ----------

  @doc "Điểm của người chơi: `%{rating, wins, losses, today}` (chưa đấu trận nào thì 1000)."
  def stats(uid) do
    today = Daily.today()

    case Repo.one(
           from r in "pvp",
             where: r.user_id == ^uid,
             select: map(r, [:rating, :wins, :losses, :day, :today])
         ) do
      nil ->
        %{rating: 1000, wins: 0, losses: 0, today: 0}

      r ->
        %{
          rating: r.rating,
          wins: r.wins,
          losses: r.losses,
          today: if(r.day == today, do: r.today, else: 0)
        }
    end
  end

  defp ensure(uid) do
    Repo.insert_all("pvp", [%{user_id: uid}], on_conflict: :nothing)
  end

  @doc "Điểm Elo thay đổi của người có điểm `a` khi đấu với người có điểm `b`."
  def delta(a, b, won?) do
    expected = 1 / (1 + :math.pow(10, (b - a) / 400))
    round(@k * (if(won?, do: 1, else: 0) - expected))
  end

  # ---------- Thách đấu ----------

  @doc """
  Kiểm tra được thách đấu `target` không, và dựng quái-bản-sao của đối thủ.
  Trả về `{:ok, quái, nhân vật đối thủ}` hoặc `{:error, lý_do}`.
  """
  def challenge(uid, target) do
    s = stats(uid)
    opp = is_integer(target) && target != uid && Characters.load(target)

    cond do
      target == uid -> {:error, "Không tự thách đấu mình được."}
      !opp -> {:error, "Không tìm thấy đối thủ."}
      s.today >= @per_day -> {:error, "Hôm nay đã đấu đủ #{@per_day} trận. Mai quay lại nhé."}
      true -> {:ok, opponent(opp, target), opp}
    end
  end

  @doc "Bản sao chỉ số của nhân vật `p` dùng làm đối thủ trong trận."
  def opponent(p, uid) do
    d = Engine.derived(p)
    skill = hd(Data.class(p.cls).skills)

    %{
      id: "hero",
      name: p.name,
      level: p.level,
      boss: false,
      final: false,
      special: %{name: skill.name, every: 3, mult: 1.8},
      on_hit: nil,
      # cánh: % sát thương gộp vào tấn công. Phase 8: phần giảm sát thương nhận (cánh × Excellent) ở `taken`,
      # bỏ qua phòng thủ (dòng cánh) ở `ignore_def`, máu thật (trước đây gộp hấp thụ của cánh vào máu, bỏ sót Excellent)
      maxHp: d.maxHp,
      hp: d.maxHp,
      atk: round(d.atk * (1 + d.wingDmg)),
      taken: Float.round((1 - d.wingAbsorb) * (1 - d.excAbsorb) * 1.0, 4),
      ignore_def: d.ignoreDef,
      # Excellent "phản sát thương" của người đó: người đánh bản sao (đồ sát) cũng bị phản
      reflect: d.excReflect,
      def: d.def,
      crit: d.crit,
      # Phase 8: hệ số chí mạng thật của người đó (trước đây ×monster_crit_mult như quái)
      crit_mult: d.critMult,
      dodge: d.dodge,
      xp: 0,
      gold: 0,
      pvp: uid,
      look: Engine.look(p),
      # DECISIONS "Cân bằng đánh người": lớp (hệ số nhận sát thương theo lớp) và kỹ năng thật của người đó
      cls: p.cls,
      # số lần chuyển sinh: chọn dòng hệ số lớp (RULES.pvp.class_taken_by_rebirth)
      rebirths: Map.get(p, :rebirths) || 0,
      # Đấu trường: hệ số lớp theo bảng riêng (RULES.pvp.class_taken_arena_by_rebirth); đồ sát ghi đè false
      arena: true,
      skills: Engine.copy_skills(p),
      mp: d.maxMp,
      maxMp: d.maxMp,
      mp_regen: Engine.mp_regen(p)
    }
  end

  @doc """
  Trận với `target` vừa xong (`result`: "win" | "lose" | "fled"). Cập nhật điểm hai bên.
  Trả về `%{won, delta, gold}` (vàng thưởng cho người thách đấu nếu thắng).
  """
  def finish(uid, target, result) do
    won? = result == "win"
    me = stats(uid)
    them = stats(target)
    dm = delta(me.rating, them.rating, won?)
    dt = delta(them.rating, me.rating, not won?)
    today = Daily.today()

    Repo.transaction(fn ->
      ensure(uid)
      ensure(target)

      Repo.update_all(from(r in "pvp", where: r.user_id == ^uid),
        set: [rating: max(0, me.rating + dm), day: today, today: me.today + 1],
        inc: [wins: if(won?, do: 1, else: 0), losses: if(won?, do: 0, else: 1)]
      )

      Repo.update_all(from(r in "pvp", where: r.user_id == ^target),
        set: [rating: max(0, them.rating + dt)],
        inc: [wins: if(won?, do: 0, else: 1), losses: if(won?, do: 1, else: 0)]
      )
    end)

    %{won: won?, delta: dm, their_delta: dt, gold: if(won?, do: 30 + 5 * max(0, dm), else: 0)}
  end

  # ---------- Danh sách ----------

  @doc "Đối thủ gợi ý: những người có điểm gần mình nhất (trừ mình)."
  def suggestions(uid, n \\ 5) do
    me = stats(uid).rating

    from(c in Character,
      left_join: r in "pvp",
      on: r.user_id == c.user_id,
      left_join: gm in "guild_members",
      on: gm.user_id == c.user_id,
      left_join: g in "guilds",
      on: g.id == gm.guild_id,
      where: c.user_id != ^uid,
      order_by: [asc: fragment("abs(coalesce(?, 1000) - ?)", r.rating, ^me), desc: c.level],
      limit: ^n,
      select: %{
        user_id: c.user_id,
        name: c.name,
        cls: c.cls,
        level: c.level,
        rating: coalesce(r.rating, 1000),
        # ký hiệu bang: danh sách tô màu bang địch đang chiến như trên bản đồ
        tag: g.tag
      }
    )
    |> Repo.all()
  end

  @doc """
  Tìm đối thủ theo tên (chứa `q`, không phân biệt hoa thường), trừ mình; tối đa `n` người,
  tên khớp đúng lên đầu. Cùng dạng với `suggestions/2`.
  """
  def search(uid, q, n \\ 10) do
    q = q |> to_string() |> String.replace(~r/[%_\\\\]/, "") |> String.trim()

    if q == "" do
      []
    else
      from(c in Character,
        left_join: r in "pvp",
        on: r.user_id == c.user_id,
        left_join: gm in "guild_members",
        on: gm.user_id == c.user_id,
        left_join: g in "guilds",
        on: g.id == gm.guild_id,
        where: c.user_id != ^uid and ilike(c.name, ^"%#{q}%"),
        order_by: [desc: fragment("lower(?) = lower(?)", c.name, ^q), desc: c.level, asc: c.name],
        limit: ^n,
        select: %{
          user_id: c.user_id,
          name: c.name,
          cls: c.cls,
          level: c.level,
          rating: coalesce(r.rating, 1000),
          tag: g.tag
        }
      )
      |> Repo.all()
    end
  end

  @doc "Bảng xếp hạng đấu trường."
  def top(n \\ 10) do
    from(r in "pvp",
      join: c in Character,
      on: c.user_id == r.user_id,
      where: r.wins + r.losses > 0,
      order_by: [desc: r.rating, desc: r.wins],
      limit: ^n,
      select: %{
        user_id: c.user_id,
        name: c.name,
        cls: c.cls,
        level: c.level,
        rating: r.rating,
        wins: r.wins,
        losses: r.losses
      }
    )
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {row, i} -> Map.put(row, :rank, i) end)
  end
end

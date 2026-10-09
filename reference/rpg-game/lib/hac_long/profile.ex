defmodule HacLong.Profile do
  @moduledoc """
  Hồ sơ người chơi (Phase 13, câu 13-B): mình và người khác xem giống nhau, theo bố cục mẫu
  (tên, bang, cấp · lớp, hình, đang ở đâu, hạng chung / hạng trong lớp, đấu trường, máu / MP,
  chỉ số gốc + đồ cộng, sát thương, phòng thủ, % cộng thêm, vàng, kinh nghiệm, trang bị, thú cưng,
  hàng đang bán ở chợ, số liệu, lần cuối online, ngày đăng ký).

  Chỉ đọc. `p` là nhân vật (đang online thì lấy từ Session, không thì từ database).
  """
  import Ecto.Query

  alias HacLong.{Accounts, Arena, Leaderboard, Repo}
  alias HacLong.Game.{Character, Crafting, Engine, Gear, Pets}
  alias HacLong.World.Maps

  @slots ~w(weapon armor shield wing)a

  def build(uid, p, online?) do
    d = Engine.derived(p)
    bonus = Gear.bonus_stats(p)
    {seen, joined} = dates(uid)
    q = Map.get(p, :quests) || %{}

    %{
      online: online?,
      where: if(online? && p[:pos], do: map_name(p.pos.map)),
      last_seen: seen,
      registered: joined,
      rank: Leaderboard.level_rank(uid),
      class_rank: Leaderboard.level_rank(uid, p.cls),
      hp: p.hp,
      max_hp: d.maxHp,
      mp: Map.get(p, :mp) || 0,
      max_mp: d.maxMp,
      stats:
        Map.new(~w(str agi vit ene)a, fn k ->
          {k, %{base: Map.get(p.stats, k, 0), gear: Map.get(bonus, k, 0)}}
        end),
      atk_min: d.atkMin,
      atk_max: d.atkMax,
      def: d.def,
      crit: d.crit,
      dodge: d.dodge,
      # phần trăm cộng thêm (thú cưng đang dắt + món đang ăn, cánh)
      pct: %{
        hp: pct(p, :hp),
        atk: pct(p, :atk),
        def: pct(p, :def),
        wing_dmg: d.wingDmg,
        wing_absorb: d.wingAbsorb
      },
      gold: p.gold,
      xp: p.xp,
      xp_need: Engine.xp_to_next(p.level),
      equip: Enum.flat_map(@slots, &equip(p, &1)),
      pet: p[:pet] && Pets.name(p),
      pets: length(Map.get(p, :pets) || []),
      market: market(uid),
      counts: %{
        quests: length(Map.get(q, :done) || []),
        kills: p.kills || 0,
        deaths: p.deaths || 0,
        bosses: length(Map.get(p, :bosses) || []),
        pk_wins: pk(uid, :win),
        pk_losses: pk(uid, :loss),
        tower: Map.get(p, :tower_best) || 0
      },
      arena: Arena.stats(uid)
    }
  end

  defp pct(p, key), do: Pets.bonus(p, key) + Crafting.food_bonus(p, key)

  defp equip(p, slot) do
    id = p.equip[slot]

    case id && Gear.item(p, id) do
      nil ->
        []

      it ->
        up = (Map.get(p, :upgrades) || %{})[id] || 0
        [%{slot: slot, id: it[:base] || id, name: it.name, rarity: it[:rarity] || 0, up: up}]
    end
  end

  defp map_name(id), do: (m = Maps.get(id)) && m.name

  defp dates(uid) do
    seen = Repo.one(from c in Character, where: c.user_id == ^uid, select: c.updated_at)
    user = Accounts.get_user(uid)
    {seen, user && user.inserted_at}
  end

  defp market(uid) do
    Repo.aggregate(
      from(l in "market_listings", where: l.seller_id == ^uid and is_nil(l.sold_at)),
      :count
    )
  end

  defp pk(uid, kind) do
    base =
      from m in "pk_matches",
        where: (m.a_id == ^uid or m.b_id == ^uid) and not is_nil(m.winner_id)

    q =
      if kind == :win,
        do: from(m in base, where: m.winner_id == ^uid),
        else: from(m in base, where: m.winner_id != ^uid)

    Repo.aggregate(q, :count)
  end
end

defmodule HacLong.Game.Pets do
  @moduledoc """
  Thú cưng: mua ở Người Nuôi Thú trong Làng, đi theo sau nhân vật trên bản đồ (người khác
  cũng thấy) và **chỉ cộng chỉ số** (`bonus` trong `PETS` trong `priv/game_data/pets.json`), kiểu MU: thú không đánh
  trong trận, không có kỹ năng (DECISIONS "Thú cưng 3 nhóm, chỉ cộng chỉ số"). Hàm thuần, như `Engine`.

  Ba nhóm (`group`): `war` Chiến (tấn công, chí mạng), `guard` Hộ vệ (máu, phòng thủ, giảm sát thương nhận),
  `luck` Tài lộc (kinh nghiệm, vàng rơi); Long Vương (`all`, `rare: true`, DECISIONS "Long Vương") cộng cả ba, không
  bán, chỉ câu được ở Hồ Long Vương (`HacLong.Game.Fishing`).

  Hạ đủ `RULES.pets.tame_kills` con một loài quái thường (vùng chính, bản đồ phụ, vùng chuyển sinh trừ chúa tể)
  thì thuần phục được loài đó ở Người Nuôi Thú: thú thuần (nhóm Chiến) có id `"tame:<id quái>"`; quái vùng chuyển
  sinh k cho thú thuần mạnh hơn (`tame_realm_*`).

  Thú lên cấp (tối đa `max_level`) theo số trận thắng khi được dắt theo (`gain/2`) hoặc cho ăn (`feed/1`, tốn vàng):
  mỗi cấp tăng phần trăm cộng thêm `bonus_per_level`; máu / MP cộng số (`flat`) nhân thẳng với cấp thú (`flat/2`).

  Trạng thái trong nhân vật: `pets: [id]` (đã có), `pet: id | nil` (đang dắt theo),
  `pet_xp: %{id => số trận}`.
  """

  alias HacLong.Game.{Bestiary, Data}

  # số ở `RULES.pets` (`priv/game_data/rules.json`)
  @rules Data.rules().pets
  @tame_kills @rules.tame_kills

  @max_level @rules.max_level

  @groups %{
    "war" => "Chiến",
    "guard" => "Hộ vệ",
    "luck" => "Tài lộc",
    "all" => "Thần thú"
  }

  def tame_kills, do: @tame_kills
  def max_level, do: @max_level

  @doc "Tên nhóm thú (Chiến / Hộ vệ / Tài lộc / Thần thú)."
  def group_name(g), do: Map.get(@groups, g, g)

  @doc "Thú hiếm (không bán, vd Long Vương)."
  def rare?(id), do: match?(%{rare: true}, Data.pet(id))

  # ---------- Cấp của thú ----------

  @doc "Số trận thắng cần để thú lên cấp `level`: xp_coef × cấp × (cấp - 1)."
  def xp_for(level), do: @rules.xp_coef * level * (level - 1)

  def xp(p, id), do: Map.get(Map.get(p, :pet_xp) || %{}, id, 0)

  def level(p, id) do
    n = xp(p, id)
    Enum.find(@max_level..1//-1, &(xp_for(&1) <= n))
  end

  defp active_level(p), do: level(p, p.pet)

  @doc """
  Thú đang dắt theo được tính một trận thắng (trùm: `boss_wins` trận). Trả về
  `{nhân_vật, cấp_mới | nil}`.
  """
  def gain(p, boss?) do
    case Map.get(p, :pet) && data(p.pet) do
      nil -> {p, nil}
      _ -> add_xp(p, p.pet, if(boss?, do: @rules.boss_wins, else: 1))
    end
  end

  defp add_xp(p, id, n) do
    before = level(p, id)
    all = Map.get(p, :pet_xp) || %{}
    p = Map.put(p, :pet_xp, Map.put(all, id, min(xp(p, id) + n, xp_for(@max_level))))
    now = level(p, id)
    {p, if(now > before, do: now)}
  end

  @doc "Giá cho thú đang dắt ăn một lần (`feed_gold` × cấp²), nil nếu không dắt thú hoặc thú đã tối đa."
  def feed_cost(p) do
    with id when is_binary(id) <- Map.get(p, :pet),
         lv when lv < @max_level <- level(p, id),
         do: @rules.feed_gold * lv * lv,
         else: (_ -> nil)
  end

  @doc "Cho thú đang dắt ăn ở Người Nuôi Thú: tốn `feed_cost/1` vàng, thú được `feed_xp` trận."
  def feed(p) do
    cost = feed_cost(p)

    cond do
      !(Map.get(p, :pet) && data(p.pet)) ->
        {%{ok: false, msg: "Chưa dắt theo thú nào."}, p}

      cost == nil ->
        {%{ok: false, msg: "#{name(p)} đã đạt cấp tối đa."}, p}

      p.gold < cost ->
        {%{ok: false, msg: "Cần #{cost} vàng."}, p}

      true ->
        {p, up} = add_xp(%{p | gold: p.gold - cost}, p.pet, @rules.feed_xp)
        lv = level(p, p.pet)

        msg =
          if up,
            do: "🐾 #{name(p)} ăn ngon, lên cấp #{lv}!",
            else: "🐾 #{name(p)} ăn ngon (+#{@rules.feed_xp} trận)."

        {%{ok: true, msg: msg}, p}
    end
  end

  @doc "Thông tin thú `id`: thú bán ở cửa hàng hoặc thú đã thuần (`tame:<quái>`)."
  def data("tame:" <> mid = id) do
    case wild(mid) do
      nil ->
        nil

      m ->
        k = realm(mid)
        atk = Float.round(@rules.tame_bonus + @rules.tame_realm_bonus * k, 3)

        %{
          id: id,
          name: "#{m.name} (thuần)",
          price: tame_price(m),
          group: "war",
          bonus: %{atk: atk, crit: @rules.tame_crit},
          desc: "Tấn công +#{pct(atk)}%, Chí mạng +#{pct(@rules.tame_crit)}%.",
          tame: mid
        }
    end
  end

  def data(id), do: Data.pet(id)

  defp pct(x),
    do:
      x |> Kernel.*(100) |> Float.round(1) |> then(&if(&1 == trunc(&1), do: trunc(&1), else: &1))

  # quái thường (không phải trùm, không phải chúa tể vùng chuyển sinh) mới thuần phục được
  defp wild(mid) do
    Enum.find_value(Data.zones(), fn z -> Enum.find(z.monsters, &(&1.id == mid)) end) ||
      case Data.side_monster(mid) do
        nil -> nil
        m -> if lord?(m), do: nil, else: m
      end
  end

  # vùng chuyển sinh của quái (`r<k>_…`), 0 nếu không phải
  defp realm(mid) do
    case Regex.run(~r/^r(\d+)_/, mid) do
      [_, k] -> String.to_integer(k)
      _ -> 0
    end
  end

  # chúa tể vùng chuyển sinh: `lord: true` (scripts/gen_realms.py)
  defp lord?(m), do: realm(m.id) > 0 and m[:lord] == true

  defp tame_price(m),
    do:
      round(
        (@rules.tame_price + m.level * @rules.tame_price_per_level) *
          (1 + @rules.tame_realm_price * realm(m.id))
      )

  defp wild_all do
    Enum.flat_map(Data.zones(), & &1.monsters) ++ Enum.reject(Data.side_monsters(), &lord?/1)
  end

  @doc "Những loài quái thường có thể thuần phục (đã hạ đủ số con, chưa thuần)."
  def tameable(p) do
    for m <- wild_all(),
        Bestiary.count(p, m.id) >= @tame_kills,
        "tame:#{m.id}" not in owned(p),
        do: tame_entry(p, m)
  end

  @doc "Tối đa `n` loài đang hạ dở (chưa đủ số con để thuần), nhiều con nhất trước."
  def taming(p, n \\ 3) do
    wild_all()
    |> Enum.filter(&(Bestiary.count(p, &1.id) in 1..(@tame_kills - 1)//1))
    |> Enum.sort_by(&(-Bestiary.count(p, &1.id)))
    |> Enum.take(n)
    |> Enum.map(&tame_entry(p, &1))
  end

  defp tame_entry(p, m) do
    pet = data("tame:#{m.id}")

    %{
      id: m.id,
      name: m.name,
      price: pet.price,
      kills: Bestiary.count(p, m.id),
      desc: pet.desc
    }
  end

  @doc "Thuần phục loài `mid` (đã hạ ít nhất #{@tame_kills} con)."
  def tame(p, mid) do
    id = "tame:#{mid}"
    pet = is_binary(mid) && data(id)

    cond do
      !pet ->
        {%{ok: false, msg: "Không thuần phục được loài này."}, p}

      id in owned(p) ->
        {%{ok: false, msg: "Bạn đã thuần phục loài này rồi."}, p}

      Bestiary.count(p, mid) < @tame_kills ->
        {%{ok: false, msg: "Cần hạ ít nhất #{@tame_kills} con (mới #{Bestiary.count(p, mid)})."},
         p}

      p.gold < pet.price ->
        {%{ok: false, msg: "Cần #{pet.price} vàng."}, p}

      true ->
        p = %{p | gold: p.gold - pet.price}
        p = p |> Map.put(:pets, owned(p) ++ [id]) |> Map.put(:pet, id)
        {%{ok: true, msg: "🐾 Đã thuần phục #{pet.name}! (#{pet.desc})"}, p}
    end
  end

  @doc """
  Sức của thú `id` ở cấp `lv` (mặc định cấp hiện tại của `p`) để so các thú (bot, mô phỏng hành trình): công + chí mạng
  cộng thêm + nửa thủ / máu / giảm sát thương nhận. Thú Tài lộc (chỉ kinh nghiệm / vàng) tính một phần nhỏ. nil → 0.
  """
  def power(p, id, lv \\ nil)
  def power(_p, nil, _lv), do: 0

  def power(p, id, lv) do
    lv = lv || level(p, id)
    pt = data(id)
    g = fn k -> pt.bonus[k] || 0 end

    # máu / MP cộng số: đổi ra phần trăm so với máu / MP ước lượng ở cấp nhân vật (`RULES.pets.power_ref`)
    f = fn k -> (pt[:flat] || %{})[k] || 0 end
    r = @rules.power_ref
    hp = f.(:hp) * lv / (r.hp_base + r.hp_per_level * p.level)
    mp = f.(:mp) * lv / (r.mp_base + r.mp_per_level * p.level)

    (g.(:atk) + g.(:crit) + 0.5 * (g.(:def) + 2 * g.(:reduce)) + 0.25 * (g.(:xp) + g.(:gold))) *
      bonus_mult(lv) + 0.5 * hp + 0.25 * mp
  end

  def name(p), do: data(p.pet).name

  @doc """
  Phần trăm cộng thêm của thú đang dắt theo cho chỉ số `key` (hp, atk, def, crit, reduce, gold, xp);
  mỗi cấp trên 1 tăng thêm `bonus_per_level`.
  """
  def bonus(p, key) do
    case Map.get(p, :pet) && data(p.pet) do
      %{bonus: b} -> Map.get(b, key, 0) * bonus_mult(active_level(p))
      _ -> 0
    end
  end

  @doc """
  Máu / MP (`key` :hp, :mp) cộng số cố định của thú đang dắt theo: `flat[key]` × cấp thú
  (DECISIONS "Thú cưng: máu / MP cộng số").
  """
  def flat(p, key) do
    case Map.get(p, :pet) && data(p.pet) do
      %{flat: f} -> Map.get(f, key, 0) * active_level(p)
      _ -> 0
    end
  end

  defp bonus_mult(lv), do: 1 + (lv - 1) * @rules.bonus_per_level

  @doc "Thông tin thú đã có cho client: cấp, nhóm, chỉ số cộng thêm, giá cho ăn (thú đang dắt)."
  def view(p) do
    for id <- owned(p), pt = data(id) do
      lv = level(p, id)

      %{
        id: id,
        level: lv,
        mult: bonus_mult(lv),
        group: pt[:group],
        bonus: pt.bonus,
        flat: pt[:flat] || %{},
        name: pt.name,
        desc: pt.desc,
        feed: if(id == Map.get(p, :pet), do: feed_cost(p))
      }
    end
  end

  defp owned(p), do: Map.get(p, :pets) || []

  def buy(p, id) do
    pet = Data.pet(id)

    cond do
      pet == nil ->
        {%{ok: false, msg: "Không có con thú này."}, p}

      pet[:rare] ->
        {%{ok: false, msg: "#{pet.name} không bán, chỉ câu được ở Hồ Long Vương."}, p}

      id in owned(p) ->
        {%{ok: false, msg: "Bạn đã có #{pet.name} rồi."}, p}

      p.gold < pet.price ->
        {%{ok: false, msg: "Cần #{pet.price} vàng."}, p}

      true ->
        p = %{p | gold: p.gold - pet.price}
        p = p |> Map.put(:pets, owned(p) ++ [id]) |> Map.put(:pet, id)
        {%{ok: true, msg: "#{pet.name} về nhà với bạn! (#{pet.desc})"}, p}
    end
  end

  @doc "Dắt theo thú `id` (đã mua), hoặc `nil` để cho ở nhà."
  def choose(p, nil), do: {%{ok: true, msg: "Thú cưng ở nhà."}, Map.put(p, :pet, nil)}

  def choose(p, id) do
    if id in owned(p),
      do: {%{ok: true, msg: "Dắt theo #{data(id).name}."}, Map.put(p, :pet, id)},
      else: {%{ok: false, msg: "Bạn chưa có con thú này."}, p}
  end
end

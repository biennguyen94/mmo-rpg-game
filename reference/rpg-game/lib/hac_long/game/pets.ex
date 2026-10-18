defmodule HacLong.Game.Pets do
  @moduledoc """
  Thú cưng: mua ở Người Nuôi Thú trong Làng, đi theo sau nhân vật trên bản đồ (người khác
  cũng thấy) và cộng một ít chỉ số (`bonus` trong `PETS` trong `priv/game_data/pets.json`).
  Hàm thuần, như `Engine`.

  Thú đi theo thỉnh thoảng cắn thêm một đòn trong trận (`bite/3`); mỗi thú có sức cắn riêng (`bite` trong
  `PETS`): thú đắt cắn mạnh hơn.

  Hạ đủ `RULES.pets.tame_kills` con một loài quái thường (vùng chính, bản đồ phụ, vùng chuyển sinh trừ chúa tể)
  thì thuần phục được loài đó ở Người Nuôi Thú: thú thuần có id `"tame:<id quái>"`; quái vùng chuyển sinh k
  cho thú thuần mạnh hơn (`tame_realm_*`).

  Thú lên cấp (tối đa `max_level`) theo số trận thắng khi được dắt theo (`gain/2`) hoặc cho ăn (`feed/1`, tốn vàng):
  mỗi cấp tăng chỉ số cộng thêm, tỷ lệ và sức cắn; kỹ năng 1 ở `skill_level`, kỹ năng 2 ở `skill2_level`
  (`skill`, `skill2` trong `PETS`; thú thuần dùng Cắn Xé rồi Húc Ngã), dùng khi cắn.

  Long Vương (`rare: true`, DECISIONS "Long Vương"): không bán, chỉ câu được ở Hồ Long Vương
  (`HacLong.Game.Fishing`); có thêm kỹ năng 3 (`skill3`) ở `skill3_level`.

  Trạng thái trong nhân vật: `pets: [id]` (đã có), `pet: id | nil` (đang dắt theo),
  `pet_xp: %{id => số trận}`.
  """

  alias HacLong.Game.{Bestiary, Data}

  # số ở `RULES.pets` (`priv/game_data/rules.json`)
  @rules Data.rules().pets
  @tame_kills @rules.tame_kills

  @max_level @rules.max_level
  @skill_level @rules.skill_level
  @skill2_level @rules.skill2_level
  @skill3_level @rules.skill3_level
  @unlock [@skill_level, @skill2_level, @skill3_level]
  @tame_skills [
    %{id: "rend", name: "Cắn Xé", desc: "Cú cắn mạnh gấp #{@rules.skills.rend_mult} lần."},
    %{id: "bash", name: "Húc Ngã", desc: "Khi cắn, quái bị suy yếu: tấn công -15% trong 2 lượt."}
  ]

  def tame_kills, do: @tame_kills
  def max_level, do: @max_level
  def skill_level, do: @skill_level
  def skill2_level, do: @skill2_level
  def skill3_level, do: @skill3_level

  @doc "Thú hiếm (không bán, vd Long Vương)."
  def rare?(id), do: match?(%{rare: true}, Data.pet(id))

  @doc "Kỹ năng thú `id` mở ở đúng cấp `lv` (nil nếu cấp đó không mở kỹ năng nào)."
  def skill_at(id, lv) do
    id |> skills() |> Enum.zip(@unlock) |> Enum.find_value(fn {s, at} -> if at == lv, do: s end)
  end

  # ---------- Cấp của thú ----------

  @doc "Số trận thắng cần để thú lên cấp `level`: xp_coef × cấp × (cấp - 1)."
  def xp_for(level), do: @rules.xp_coef * level * (level - 1)

  def xp(p, id), do: Map.get(Map.get(p, :pet_xp) || %{}, id, 0)

  def level(p, id) do
    n = xp(p, id)
    Enum.find(@max_level..1//-1, &(xp_for(&1) <= n))
  end

  defp active_level(p), do: level(p, p.pet)

  @doc "Các kỹ năng riêng của thú `id` (mở ở cấp `skill_level`, `skill2_level`, `skill3_level`)."
  def skills(id) do
    case data(id) do
      %{tame: _} -> @tame_skills
      %{} = pt -> Enum.reject([pt[:skill], pt[:skill2], pt[:skill3]], &is_nil/1)
      _ -> []
    end
  end

  @doc "Kỹ năng thứ nhất của thú `id`."
  def skill(id), do: List.first(skills(id))

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
          bonus: %{atk: atk},
          bite: Float.round(@rules.tame_bite + @rules.tame_realm_bite * k, 3),
          desc: "Tấn công +#{pct(atk)}%.",
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
      desc: pet.desc,
      bite: pet.bite
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

  @doc "Tỷ lệ cắn mỗi lượt của thú `id` ở cấp `lv`."
  def bite_chance(lv), do: @rules.bite_chance + (lv - 1) * @rules.bite_chance_per_level

  @doc "Sức cắn (phần của đòn thường) của thú `id` ở cấp `lv`."
  def bite_power(id, lv),
    do: ((data(id) || %{})[:bite] || @rules.bite_power) + (lv - 1) * @rules.bite_power_per_level

  @doc """
  Thú đang dắt theo cắn thêm: trả về số sát thương (0 nếu không cắn) theo sát thương
  một đòn thường `base` của nhân vật. `roll` là số ngẫu nhiên trong [0, 1).
  """
  def bite(p, base, roll) do
    if Map.get(p, :pet) && data(p.pet) do
      lv = active_level(p)

      if roll < bite_chance(lv),
        do: max(1, round(base * bite_power(p.pet, lv))),
        else: 0
    else
      0
    end
  end

  @doc "Các kỹ năng thú đang dắt đã học (theo cấp)."
  def active_skills(p) do
    if Map.get(p, :pet) && data(p.pet) do
      lv = active_level(p)

      p.pet
      |> skills()
      |> Enum.zip(@unlock)
      |> Enum.filter(&(lv >= elem(&1, 1)))
      |> Enum.map(&elem(&1, 0))
    else
      []
    end
  end

  @doc "Kỹ năng đầu tiên thú đang dắt đã học (nil nếu chưa)."
  def active_skill(p), do: List.first(active_skills(p))

  def name(p), do: data(p.pet).name

  @doc """
  Phần trăm cộng thêm của thú đang dắt theo cho chỉ số `key` (hp, atk, def, gold, xp);
  mỗi cấp trên 1 tăng thêm `bonus_per_level`.
  """
  def bonus(p, key) do
    case Map.get(p, :pet) && data(p.pet) do
      %{bonus: b} -> Map.get(b, key, 0) * bonus_mult(active_level(p))
      _ -> 0
    end
  end

  defp bonus_mult(lv), do: 1 + (lv - 1) * @rules.bonus_per_level

  @doc "Thông tin thú đã có cho client: cấp, chỉ số cộng thêm, cắn, kỹ năng, giá cho ăn (thú đang dắt)."
  def view(p) do
    for id <- owned(p), pt = data(id) do
      lv = level(p, id)

      %{
        id: id,
        level: lv,
        mult: bonus_mult(lv),
        bite_chance: bite_chance(lv),
        bite_power: bite_power(id, lv),
        skills:
          id
          |> skills()
          |> Enum.zip(@unlock)
          |> Enum.map(fn {s, at} -> Map.merge(s, %{at: at, learned: lv >= at}) end),
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

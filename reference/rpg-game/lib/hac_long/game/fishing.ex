defmodule HacLong.Game.Fishing do
  @moduledoc """
  Câu cá ở hồ nước (ô `~`). Hàm thuần, như `Engine`; thời gian truyền vào (mili giây, đồng
  hồ đơn điệu của server) để test được.

  - `cast/2`: đứng cạnh nước thì thả câu. Cá cắn câu sau `@wait` ngẫu nhiên; client nhận số
    mili giây phải chờ để hiện phao chìm.
  - `reel/2`: giật cần. Chỉ được cá nếu giật trong `@window` kể từ lúc cá cắn; giật sớm hay
    muộn thì trượt. Đi chỗ khác thì mất lượt câu.
  - Loại cá tùy vùng (`pool/1`): Làng và Rừng Mê cá thường; Đầm Lầy và Hang Hắc Long có Lươn Điện.
    Rất hiếm mới có Cá Chép Vàng. Hồ Long Vương (`fish: "lake"`) có bảng cá riêng.
  - Long Vương (DECISIONS "Long Vương nổi mỗi giờ"): Ngài nổi ở một ô nước của Hồ Long Vương
    (`HacLong.LakeEvent`). Chỉ lần thả câu trúng đúng ô đó (`spot`) mới có `RULES.fishing.dragon.chance` cơ hội
    × (1 + Long Khí / `long_khi_div`) × `bait_mult` nếu có Mồi Rồng (chỉ tốn mồi khi thả trúng ô Ngài).
    Quyết định lúc thả câu, client nhận `big: true` để hiện phao giật mạnh. Giật đúng lúc thì được thú
    Long Vương (mỗi nhân vật một con; đã có thì được Cá Chép Vàng), kết quả có `rare_pet` để Session ghi
    Bia Long Vương, báo cả server và cho Ngài lặn. Long Khí (`long_khi`) +1 mỗi con cá câu được ở hồ, tối đa
    `long_khi_max`, về 0 khi câu được Ngài.
  - Đàn Cá Vàng (DECISIONS "Đàn Cá Vàng, việc của Ông Lão"): thả trúng ô Đàn Cá Vàng (`school`) thì cá câu được là
    Cá Chép Vàng với tỉ lệ `RULES.fishing.school.gold_chance`, mỗi con +`school.long_khi` Long Khí.
  - Việc của Ông Lão (`claim_elder/1`): câu `RULES.fishing.elder.count` con cá ở hồ trong ngày (đếm ở `daily.lake_n`)
    thì nhận vàng, kinh nghiệm và Long Khí.

  Trạng thái lượt câu (`fishing: %{bite, pos}`) chỉ giữ trong Session, không lưu database.
  Số cá đã câu được lưu ở `fish_caught` (cho thành tựu).
  """

  alias HacLong.Game.{Daily, Data, Engine, Rng}
  alias HacLong.World.Maps

  @wait 3_000..8_000
  @window 1_000

  def window, do: @window

  # {tỉ lệ, món}, ở `RULES.fishing` (`priv/game_data/rules.json`)
  @rules Data.rules().fishing
  @pools Map.new(@rules.pools, fn {k, l} -> {k, Enum.map(l, &List.to_tuple/1)} end)
  @dragon @rules.dragon
  @school @rules.school
  @elder @rules.elder

  def dragon, do: @dragon

  @doc "Bản đồ `map_id` là hồ có Long Vương."
  def dragon_lake?(map_id), do: match?(%{fish: "lake"}, Maps.get(map_id))

  def pool(map_id) do
    case Maps.get(map_id) do
      %{fish: f} when is_binary(f) -> Map.fetch!(@pools, String.to_existing_atom(f))
      %{zone: z} when is_integer(z) and z >= @rules.deep_zone -> @pools.deep
      _ -> @pools.default
    end
  end

  @doc "Đang đứng cạnh (4 hướng) một ô nước."
  def near_water?(%{pos: %{map: id, x: x, y: y}}) do
    case Maps.get(id) do
      nil ->
        false

      m ->
        Enum.any?([{1, 0}, {-1, 0}, {0, 1}, {0, -1}], fn {dx, dy} ->
          Maps.water?(m, x + dx, y + dy)
        end)
    end
  end

  def near_water?(_), do: false

  @doc """
  Thả câu. `at` là ô nước `{x, y}` người chơi chọn (trong tầm `reach`; nil thì ô nước cạnh bên),
  `spot` là ô Long Vương đang nổi, `school` ô Đàn Cá Vàng (`HacLong.LakeEvent.tiles/0`, nil nếu không có).
  """
  def cast(p, now, at \\ nil, spot \\ nil, school \\ nil) do
    cond do
      p.battle ->
        {%{ok: false, msg: "Đang trong trận."}, p}

      not near_water?(p) ->
        {%{ok: false, msg: "Hãy đứng cạnh hồ nước để câu."}, p}

      at != nil and not castable?(p, at) ->
        {%{ok: false, msg: "Ô đó xa quá hoặc không phải nước."}, p}

      true ->
        lo..hi//_ = @wait
        wait = lo + floor(Rng.uniform() * (hi - lo))
        {p, big} = dragon_roll(p, at, spot)
        reply = %{ok: true, wait: wait, window: @window}
        reply = if big, do: Map.put(reply, :big, true), else: reply
        school? = school != nil and at == school and dragon_lake?(p.pos.map)
        reply = if school?, do: Map.put(reply, :school, true), else: reply
        {reply, Map.put(p, :fishing, %{bite: now + wait, pos: p.pos, big: big, school: school?})}
    end
  end

  # ô nước trong tầm `reach` (Chebyshev) của chỗ đứng
  defp castable?(%{pos: %{map: id, x: x, y: y}}, {tx, ty}) do
    m = Maps.get(id)
    max(abs(tx - x), abs(ty - y)) <= @dragon.reach and Maps.water?(m, tx, ty)
  end

  @doc "Cơ hội Long Vương cắn câu khi thả trúng ô Ngài (có / không có Mồi Rồng)."
  def dragon_chance(p, bait?) do
    @dragon.chance * (1 + long_khi(p) / @dragon.long_khi_div) *
      if(bait?, do: @dragon.bait_mult, else: 1)
  end

  def long_khi(p), do: Map.get(p, :long_khi) || 0

  # Hồ Long Vương, thả trúng ô Ngài đang nổi: có Mồi Rồng thì tốn 1 mồi, cơ hội gấp `bait_mult`
  defp dragon_roll(p, at, spot) do
    if spot != nil and at == spot and dragon_lake?(p.pos.map) do
      bait? = Map.get(p.inv, @dragon.bait, 0) > 0
      chance = dragon_chance(p, bait?)
      p = if bait?, do: Engine.take_item(p, @dragon.bait), else: p
      {p, Rng.uniform() < chance}
    else
      {p, false}
    end
  end

  def reel(p, now) do
    f = Map.get(p, :fishing)
    p = Map.put(p, :fishing, nil)

    cond do
      f == nil ->
        {%{ok: false, msg: "Bạn chưa thả câu."}, p}

      f.pos != p.pos ->
        {%{ok: false, msg: "Bạn đã rời chỗ câu."}, p}

      now < f.bite ->
        {%{ok: false, msg: "Giật sớm quá, cá sợ bỏ đi mất."}, p}

      now > f.bite + @window and f[:big] ->
        {%{ok: false, msg: "Dây câu đứt phựt! Bóng vàng khổng lồ lặn mất xuống Vực Rồng..."}, p}

      now > f.bite + @window ->
        {%{ok: false, msg: "Chậm tay rồi, cá ăn mất mồi."}, p}

      f[:big] ->
        land_dragon(p)

      true ->
        catch_fish(p, f[:school])
    end
  end

  @doc "Long Vương cắn câu và được kéo lên (tách riêng để kiểm thử)."
  def land_dragon(p) do
    pet = @dragon.pet
    owned = Map.get(p, :pets) || []

    if pet in owned do
      {r, p} = land(p, @dragon.dupe)

      {%{
         r
         | msg:
             "🐉 Long Vương trồi lên nhìn bạn, nhả lại một #{Data.item(@dragon.dupe).name} rồi lặn mất."
       }, p}
    else
      p =
        p
        |> Map.put(:pets, owned ++ [pet])
        |> Map.put(:fish_caught, Map.get(p, :fish_caught, 0) + 1)
        |> Map.put(:long_khi, 0)

      name = Data.pet(pet).name

      {%{
         ok: true,
         msg: "🐉 Câu được #{name}! Ngài đã nhận bạn làm chủ. Dắt theo ở tab Nhân vật.",
         rare_pet: pet
       }, p}
    end
  end

  defp catch_fish(p, true) do
    id =
      if Rng.uniform() < @school.gold_chance, do: @school.gold_fish, else: roll(pool(p.pos.map))

    land(p, id, @school.long_khi)
  end

  defp catch_fish(p, _), do: land(p, roll(pool(p.pos.map)))

  @doc "Đưa con `id` vừa câu được vào túi (tách riêng để kiểm thử). Ở hồ Long Vương được `lk` Long Khí."
  def land(p, id, lk \\ 1) do
    p = p |> Engine.add_item(id) |> Map.put(:fish_caught, Map.get(p, :fish_caught, 0) + 1)
    p = if id == "old_boot", do: p, else: Daily.on_fish(p)

    p =
      if id != "old_boot" and dragon_lake?(p.pos.map),
        do: p |> add_long_khi(lk) |> Daily.on_lake_fish(@elder.count),
        else: p

    name = Data.item(id).name

    msg =
      case id do
        "old_boot" -> "Câu được... #{name}. Thôi thì cũng là một món."
        "fish_gold" -> "✨ Câu được #{name}! Hiếm lắm đấy!"
        _ -> "Câu được #{name}!"
      end

    {%{ok: true, msg: msg, fish: id}, p}
  end

  defp roll(pool) do
    total = pool |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    r = Rng.uniform() * total

    Enum.reduce_while(pool, 0, fn {w, id}, acc ->
      if r < acc + w, do: {:halt, id}, else: {:cont, acc + w}
    end)
  end

  defp add_long_khi(p, n), do: Map.put(p, :long_khi, min(long_khi(p) + n, @dragon.long_khi_max))

  @doc "Việc của Ông Lão hôm nay: `%{n, count, done, reward: %{gold, xp, long_khi}}` (thưởng theo cấp nhân vật)."
  def elder(p) do
    r = Data.rules().daily.reward.fish
    c = @elder.count

    %{
      n: min(get_in(p, [:daily, :lake_n]) || 0, c),
      count: c,
      done: get_in(p, [:daily, :lake_done]) == true,
      reward: %{
        gold: round(Engine.base_gold(p.level) * c * r.gold),
        xp: round(Engine.base_xp(p.level) * c / r.xp_div),
        long_khi: @elder.long_khi
      }
    }
  end

  @doc "Nhận thưởng việc của Ông Lão (câu đủ cá ở hồ hôm nay, mỗi ngày một lần)."
  def claim_elder(p) do
    e = elder(p)

    cond do
      p[:daily] == nil or e.n < e.count ->
        {%{
           ok: false,
           msg: "Câu đủ #{e.count} con cá ở hồ này rồi quay lại nhé (#{e.n}/#{e.count})."
         }, p}

      e.done ->
        {%{ok: false, msg: "Hôm nay lão trả công rồi, mai lại đến."}, p}

      true ->
        p = %{p | gold: p.gold + e.reward.gold} |> add_long_khi(e.reward.long_khi)
        p = put_in(p, [:daily, :lake_done], true)
        {_levels, p} = Engine.gain_xp(p, e.reward.xp)

        {%{
           ok: true,
           msg:
             "Ông Lão gật gù: +#{e.reward.gold} vàng, +#{e.reward.xp} kinh nghiệm, +#{e.reward.long_khi} Long Khí."
         }, p}
    end
  end
end

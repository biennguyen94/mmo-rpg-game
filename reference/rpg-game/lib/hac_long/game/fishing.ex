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
  - Long Vương (DECISIONS "Long Vương"): mỗi lần thả câu ở Hồ Long Vương có `RULES.fishing.dragon.chance`
    cơ hội Ngài cắn câu (quyết định lúc thả câu, client nhận `big: true` để hiện phao giật mạnh); có Mồi Rồng
    trong túi thì tốn 1 mồi, cơ hội × `bait_mult`. Giật đúng lúc thì được thú Long Vương (mỗi nhân vật một
    con; đã có thì được Cá Chép Vàng), kết quả có `rare_pet` để Session ghi Bia Long Vương và báo cả server.

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

  def cast(p, now) do
    cond do
      p.battle ->
        {%{ok: false, msg: "Đang trong trận."}, p}

      not near_water?(p) ->
        {%{ok: false, msg: "Hãy đứng cạnh hồ nước để câu."}, p}

      true ->
        lo..hi//_ = @wait
        wait = lo + floor(Rng.uniform() * (hi - lo))
        {p, big} = dragon_roll(p)
        reply = %{ok: true, wait: wait, window: @window}
        reply = if big, do: Map.put(reply, :big, true), else: reply
        {reply, Map.put(p, :fishing, %{bite: now + wait, pos: p.pos, big: big})}
    end
  end

  # Hồ Long Vương: có Mồi Rồng thì tốn 1 mồi, cơ hội gấp `bait_mult`
  defp dragon_roll(p) do
    if dragon_lake?(p.pos.map) do
      bait? = Map.get(p.inv, @dragon.bait, 0) > 0
      p = if bait?, do: Engine.take_item(p, @dragon.bait), else: p
      chance = @dragon.chance * if(bait?, do: @dragon.bait_mult, else: 1)
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
        catch_fish(p)
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

      name = Data.pet(pet).name

      {%{
         ok: true,
         msg: "🐉 Câu được #{name}! Ngài đã nhận bạn làm chủ. Dắt theo ở tab Nhân vật.",
         rare_pet: pet
       }, p}
    end
  end

  defp catch_fish(p), do: land(p, roll(pool(p.pos.map)))

  @doc "Đưa con `id` vừa câu được vào túi (tách riêng để kiểm thử)."
  def land(p, id) do
    p = p |> Engine.add_item(id) |> Map.put(:fish_caught, Map.get(p, :fish_caught, 0) + 1)
    p = if id == "old_boot", do: p, else: Daily.on_fish(p)
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
end

defmodule HacLong.Game.DragonEgg do
  @moduledoc """
  Hắc Long, linh vật Con Rồng Cháu Tiên (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long"). Hàm thuần; số ở
  `RULES.sky.hoi` / `RULES.sky.egg`.

  - **Long Phượng Hội** (`HacLong.SkyEvent`): Long Vương nổi ở hồ và Chim Lạc lượn ở đồi cùng lúc thì vòng sáng hiện ở
    Tế Đàn. Đứng trong vòng làm lễ (`ritual/3`):
    - đủ điều kiện (`missing/1` rỗng: có Long Vương và Chim Lạc cấp tối đa, Long Khí và Phong Khí đầy, đã hạ Hắc Long,
      chưa có Hắc Long / chưa có trứng): mất hết Long Khí, Phong Khí, nhận **Bọc Trăm Trứng**;
    - không đủ: hưởng lộc `hoi.lucky_qi` Long Khí và Phong Khí, mỗi hội một lần (`sky.lucky` = mã hội).
  - **Ấp trứng** (`sky.egg = %{at, kills, boss}`): nở (`hatch/2`) khi đủ một trong: hạ `egg.kills` quái kể từ lúc nhận
    trứng, qua `egg.days` ngày, hoặc hạ trùm cuối Hắc Long thêm một lần (`on_final_win/1`). Nở ra `egg.pet`, hoặc
    `egg.rare_pet` (Hắc Long Chân Thân) với tỉ lệ `egg.rare_chance`; kết quả có `rare_pet` để Session ghi bia, báo cả
    server (người đầu tiên của server: báo riêng).
  """

  alias HacLong.Game.{Data, Kite, Pets, Rng}

  @r Data.rules().sky
  @hoi @r.hoi
  @egg @r.egg
  @dragon Data.rules().fishing.dragon

  def hoi_rules, do: @hoi
  def egg_rules, do: @egg
  def pets, do: [@egg.pet, @egg.rare_pet]

  # ---------- Ghép ở Lão Hỗn Nguyên (DECISIONS "Thú thành vật phẩm", thay Long Phượng Hội) ----------

  @doc "Điều kiện ghép Hắc Long còn thiếu: có Long Vương và Chim Lạc, cả hai cấp tối đa (danh sách chữ; rỗng là đủ)."
  def combine_missing(p) do
    pets = Map.get(p, :pets) || []

    for id <- [@dragon.pet, Kite.rules().bird.pet], reduce: [] do
      acc ->
        name = Data.pet(id).name

        cond do
          id not in pets ->
            acc ++ ["chưa có #{name}"]

          Pets.level(p, id) < Pets.max_level(id) ->
            acc ++ ["#{name} chưa cấp #{Pets.max_level(id)}"]

          true ->
            acc
        end
    end
  end

  @doc """
  Ghép Hắc Long ở Lão Hỗn Nguyên, tỉ lệ 100%: mất Long Vương và Chim Lạc (cả hai cấp tối đa), nhận Hắc Long
  (`egg.rare_chance` ra Hắc Long Chân Thân). Đã có con cùng loại thì con mới vào túi dạng Ấn.
  """
  def combine(p) do
    case combine_missing(p) do
      [_ | _] = miss ->
        {%{ok: false, msg: "Chưa ghép được: " <> Enum.join(miss, ", ") <> "."}, p}

      [] ->
        gone = [@dragon.pet, Kite.rules().bird.pet]
        pet = if Rng.uniform() < @egg.rare_chance, do: @egg.rare_pet, else: @egg.pet

        p =
          p
          |> Map.put(:pets, (Map.get(p, :pets) || []) -- gone)
          |> Map.put(:pet_xp, Map.drop(Map.get(p, :pet_xp) || %{}, gone))
          |> then(&if(&1.pet in gone, do: Map.put(&1, :pet, nil), else: &1))

        {p, where} =
          if pet in (Map.get(p, :pets) || []),
            do: {Pets.give_sealed(p, pet), "vào túi dạng Ấn (bạn đã có một con)"},
            else:
              {Map.put(p, :pets, (Map.get(p, :pets) || []) ++ [pet]),
               "đã về, dắt theo ở tab Nhân vật"}

        {%{
           ok: true,
           msg: "🐉🐦 Long Vương và Chim Lạc hòa làm một: #{Data.pet(pet).name} #{where}!",
           rare_pet: pet
         }, p}
    end
  end

  @doc "Đã có Hắc Long (thường hoặc Chân Thân)."
  def owned?(p), do: Enum.any?(Map.get(p, :pets) || [], &(&1 in pets()))

  @doc "Điều kiện làm lễ còn thiếu (danh sách chữ; rỗng là đủ)."
  def missing(p) do
    pets = Map.get(p, :pets) || []
    bird = @r.bird.pet
    dragon = @dragon.pet

    [
      dragon not in pets && "chưa có Long Vương",
      dragon in pets and Pets.level(p, dragon) < Pets.max_level(dragon) &&
        "Long Vương chưa cấp #{Pets.max_level(dragon)}",
      bird not in pets && "chưa có Chim Lạc",
      bird in pets and Pets.level(p, bird) < Pets.max_level(bird) &&
        "Chim Lạc chưa cấp #{Pets.max_level(bird)}",
      (Map.get(p, :long_khi) || 0) < @dragon.long_khi_max &&
        "Long Khí chưa đầy (#{Map.get(p, :long_khi) || 0}/#{@dragon.long_khi_max})",
      Kite.phong_khi(p) < Kite.phong_khi_max() &&
        "Phong Khí chưa đầy (#{Kite.phong_khi(p)}/#{Kite.phong_khi_max()})",
      Map.get(p, :victory) != true && "chưa hạ Hắc Long",
      owned?(p) && "đã có Hắc Long",
      (egg(p) != nil or Map.get(p.inv, @egg.item, 0) > 0) && "đang ấp Bọc Trăm Trứng"
    ]
    |> Enum.filter(&is_binary/1)
  end

  def egg(p), do: (Map.get(p, :sky) || Kite.load(nil)).egg

  @doc "Đứng trong vòng sáng của hội `hoi` (`%{id, at: {x, y}}` hoặc nil)."
  def in_ring?(%{pos: %{map: m, x: x, y: y}}, %{at: {cx, cy}}),
    do: m == @hoi.map and max(abs(x - cx), abs(y - cy)) <= @hoi.radius

  def in_ring?(_, _), do: false

  @doc "Làm lễ ở hội `hoi`; `now_s` giờ unix (giây)."
  def ritual(p, hoi, now_s) do
    sky = Map.get(p, :sky) || Kite.load(nil)

    cond do
      hoi == nil ->
        {%{ok: false, msg: "Long Phượng Hội chưa diễn ra."}, p}

      p.battle ->
        {%{ok: false, msg: "Đang trong trận."}, p}

      not in_ring?(p, hoi) ->
        {%{ok: false, msg: "Hãy bước vào vòng sáng ở Tế Đàn."}, p}

      missing(p) == [] ->
        p =
          p
          |> Map.put(:long_khi, 0)
          |> Kite.put_sky(
            &%{&1 | phong_khi: 0, egg: %{at: now_s, kills: p.kills, boss: false}, lucky: hoi.id}
          )
          |> HacLong.Game.Engine.add_item(@egg.item)

        {%{
           ok: true,
           egg: true,
           msg:
             "🐉🐦 Long Vương và Chim Lạc quấn nhau bay vút lên trời, rồi đặt vào tay bạn một Bọc Trăm Trứng! Ấp trứng bằng cách chiến đấu."
         }, p}

      sky.lucky == hoi.id ->
        {%{
           ok: false,
           msg: "Bạn đã hưởng lộc hội này rồi. (Làm lễ cần: #{Enum.join(missing(p), ", ")}.)"
         }, p}

      true ->
        q = @hoi.lucky_qi

        p =
          p
          |> Map.put(:long_khi, min((Map.get(p, :long_khi) || 0) + q, @dragon.long_khi_max))
          |> Kite.add_phong_khi(q)
          |> Kite.put_sky(&%{&1 | lucky: hoi.id})

        {%{
           ok: true,
           msg:
             "✨ Hưởng lộc Long Phượng Hội: +#{q} Long Khí, +#{q} Phong Khí. Làm lễ nhận Bọc Trăm Trứng cần: #{Enum.join(missing(p), ", ")}."
         }, p}
    end
  end

  @doc "Vừa hạ trùm cuối Hắc Long: trứng đang ấp đủ điều kiện nở."
  def on_final_win(p) do
    if egg(p), do: Kite.put_sky(p, &%{&1 | egg: %{&1.egg | boss: true}}), else: p
  end

  @doc "Tiến độ ấp: `%{kills, need_kills, days, need_days, boss, ready}` hoặc nil nếu không có trứng."
  def progress(p, now_s) do
    case egg(p) do
      nil ->
        nil

      e ->
        k = max(0, p.kills - e.kills)
        d = div(max(0, now_s - e.at), 86_400)

        %{
          kills: min(k, @egg.kills),
          need_kills: @egg.kills,
          days: min(d, @egg.days),
          need_days: @egg.days,
          boss: e.boss,
          ready: k >= @egg.kills or d >= @egg.days or e.boss
        }
    end
  end

  @doc "Cho trứng nở."
  def hatch(p, now_s) do
    pr = progress(p, now_s)

    cond do
      pr == nil or Map.get(p.inv, @egg.item, 0) < 1 ->
        {%{ok: false, msg: "Bạn không có Bọc Trăm Trứng."}, p}

      not pr.ready ->
        {%{
           ok: false,
           msg:
             "Trứng chưa nở được: hạ #{pr.kills}/#{pr.need_kills} quái, hoặc #{pr.days}/#{pr.need_days} ngày, hoặc hạ Hắc Long thêm một lần."
         }, p}

      true ->
        pet = if Rng.uniform() < @egg.rare_chance, do: @egg.rare_pet, else: @egg.pet

        p =
          p
          |> HacLong.Game.Engine.take_item(@egg.item)
          |> Map.put(:pets, (Map.get(p, :pets) || []) ++ [pet])
          |> Kite.put_sky(&%{&1 | egg: nil})

        name = Data.pet(pet).name

        {%{
           ok: true,
           msg:
             "🥚💥 Bọc Trăm Trứng nứt ra… #{name} vươn mình bay lên, quấn quanh bạn! Dắt theo ở tab Nhân vật.",
           rare_pet: pet
         }, p}
    end
  end
end

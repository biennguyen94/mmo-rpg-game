defmodule HacLong.Game.DragonEgg do
  @moduledoc """
  Hắc Long, linh vật Con Rồng Cháu Tiên (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long"). Hàm thuần; số ở
  `RULES.sky.egg`.

  - **Ghép** ở Lão Hỗn Nguyên (`combine/1`): Long Vương + Chim Lạc cấp tối đa ra Hắc Long. Long Phượng Hội (làm lễ nhận
    trứng) đã bỏ hẳn (DECISIONS "Thú thành vật phẩm").
  - **Ấp trứng** (Bọc Trăm Trứng còn lại từ trước) (`sky.egg = %{at, kills, boss}`): nở (`hatch/2`) khi đủ một trong: hạ `egg.kills` quái kể từ lúc nhận
    trứng, qua `egg.days` ngày, hoặc hạ trùm cuối Hắc Long thêm một lần (`on_final_win/1`). Nở ra `egg.pet`, hoặc
    `egg.rare_pet` (Hắc Long Chân Thân) với tỉ lệ `egg.rare_chance`; kết quả có `rare_pet` để Session ghi bia, báo cả
    server (người đầu tiên của server: báo riêng).
  """

  alias HacLong.Game.{Data, Kite, Pets, Rng}

  @r Data.rules().sky
  @egg @r.egg
  @dragon Data.rules().fishing.dragon

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

# Hồ sơ đồ theo mốc chuyển sinh cho cân bằng đồ sát (Max.tier/2), lấy từ nhân vật CHƠI THẬT (HacLong.Game.Journey):
# mỗi lớp × SEEDS seed chạy một hành trình 10 lần chuyển sinh, lấy nhân vật ở mỗi mốc (vừa đạt cấp tối đa, trước khi
# chuyển sinh), rồi tính chung cho cả 4 lớp ở mốc đó: cấp đồ (trung vị) của vũ khí / giáp / trang sức, ép +N, dòng
# cộng thêm, May mắn, Excellent, cánh, tháp, thông thạo kỹ năng, thú cưng. Các số không giảm theo mốc (lấy max dồn).
# Ghi scripts/pvp/tier_profile.json (vào git; sửa tay được). Max.tier/2 dựng 4 lớp cùng một hồ sơ: mỗi lớp mặc món
# tốt nhất CỦA LỚP có cấp đồ ≤ cấp trong hồ sơ.
#
#   mix run --no-start scripts/pvp/profile.exs            dùng hành trình đã lưu ở tmp/journey_tiers (nếu có)
#   FRESH=1 SEEDS=3 mix run --no-start scripts/pvp/profile.exs   chạy lại hành trình (sau khi đổi gameplay, ~5 phút)
alias HacLong.Game.{Engine, Gear, Journey, Mastery}

seeds = 1..String.to_integer(System.get_env("SEEDS") || "3")
classes = ~w(dk dw elf mg)
dir = "tmp/journey_tiers"
File.mkdir_p!(dir)
fresh? = System.get_env("FRESH") == "1"

runs =
  for(c <- classes, s <- seeds, do: {c, s})
  |> Task.async_stream(
    fn {c, s} ->
      f = Path.join(dir, "#{c}-s#{s}.bin")

      tiers =
        case not fresh? && File.read(f) do
          {:ok, bin} ->
            :erlang.binary_to_term(bin)

          _ ->
            # Journey dùng :rand của tiến trình: đặt seed ngay trong tác vụ để chạy lại ra đúng nhân vật
            :rand.seed(:exsss, {s, s, s})
            t = Journey.run(c, rebirths: 10, players: true).tiers
            File.write!(f, :erlang.term_to_binary(t))
            t
        end

      {{c, s}, tiers}
    end,
    timeout: :infinity,
    max_concurrency: System.schedulers_online()
  )
  |> Map.new(fn {:ok, r} -> r end)

median = fn
  [] -> 0
  l -> l |> Enum.sort() |> Enum.at(div(length(l), 2))
end

mean = fn
  [] -> 0
  l -> Enum.sum(l) / length(l)
end

weapon_slots = [:weapon, :shield]
armor_slots = [:helm, :armor, :pants, :gloves, :boots]
jewel_slots = [:ring1, :ring2, :pendant]

raw =
  for k <- 0..10 do
    ps = for c <- classes, s <- seeds, p = runs[{c, s}][k], p != nil, do: p

    pieces =
      for p <- ps,
          {slot, id} <- p.equip,
          id != nil,
          g = Gear.item(p, id),
          g != nil,
          do: {slot, g, Engine.upgrade_level(p, id)}

    gear = Enum.reject(pieces, fn {s, _, _} -> s == :wing end)

    lv = fn slots ->
      median.(for {s, g, _} <- gear, s in slots, g.slot != "shield", do: g.level)
    end

    wings = for p <- ps, do: (w = p.equip[:wing]) && Gear.item(p, w)
    wing_ups = for p <- ps, w = p.equip[:wing], w != nil, do: Engine.upgrade_level(p, w)
    pets = for p <- ps, p[:pet], do: p.pet

    %{
      "chars" => length(ps),
      "weapon_level" => lv.(weapon_slots),
      "armor_level" => lv.(armor_slots),
      "jewel_level" => lv.(jewel_slots),
      "up" => round(mean.(for {_, _, u} <- gear, do: u)),
      "opt" => round(mean.(for {_, g, _} <- gear, do: g.opt || 0)),
      "luck" => mean.(for {_, g, _} <- gear, do: if(g.luck, do: 1, else: 0)) >= 0.5,
      "exc" => round(mean.(for {_, g, _} <- gear, do: length(g.exc || []))),
      "skill" =>
        mean.(for {s, g, _} <- gear, s == :weapon, do: if(g.skill, do: 1, else: 0)) >= 0.5,
      "wing" => median.(for w <- wings, do: (w && w.tier) || 0),
      "wing_up" => round(mean.(wing_ups)),
      "tower" => round(mean.(for p <- ps, do: Map.get(p, :tower_best) || 0)),
      "mastery" => round(mean.(for p <- ps, sk <- Engine.skills(p), do: Mastery.level(p, sk.id))),
      "pet" => if(length(pets) * 2 >= max(length(ps), 1), do: median.(pets), else: nil)
    }
  end

# không giảm theo mốc: người chơi không mất đồ khi chuyển sinh
keys = ~w(weapon_level armor_level jewel_level up opt exc wing wing_up tower mastery)

{rows, _} =
  Enum.map_reduce(Enum.with_index(raw), nil, fn {r, k}, prev ->
    r =
      if prev,
        do:
          Enum.reduce(keys, r, fn key, r -> Map.update!(r, key, &max(&1, prev[key])) end)
          |> Map.update!("luck", &(&1 or prev["luck"])),
        else: r

    {{to_string(k), r}, r}
  end)

out = %{
  "_doc" =>
    "Hồ sơ đồ theo mốc chuyển sinh (scripts/pvp/profile.exs từ HacLong.Game.Journey, #{length(Enum.to_list(seeds))} seed × 4 lớp). " <>
      "Max.tier/2 dựng 4 lớp cùng hồ sơ: món tốt nhất của lớp có cấp đồ ≤ *_level, ép +up, opt dòng cộng thêm, exc dòng Excellent, " <>
      "cánh bậc wing (0 = không) +wing_up, tháp tower, thông thạo mastery, thú pet. Sửa tay được; chạy lại profile.exs để tạo mới.",
  "sourceType" => "SIMULATED",
  "version" => 1,
  "verified" => false,
  "tiers" => Map.new(rows)
}

File.write!(Path.join(__DIR__, "tier_profile.json"), Jason.encode!(out, pretty: true) <> "\n")

IO.puts(
  "mốc | vũ khí / giáp / trang sức (cấp đồ) | +N dòng May Exc | cánh | tháp TT | thú | số nhân vật"
)

for {k, r} <- Enum.sort_by(rows, fn {k, _} -> String.to_integer(k) end) do
  IO.puts(
    "r#{k} | #{r["weapon_level"]} / #{r["armor_level"]} / #{r["jewel_level"]} | +#{r["up"]} #{r["opt"]} #{if r["luck"], do: "có", else: "không"} #{r["exc"]} | " <>
      "#{if r["wing"] > 0, do: "bậc #{r["wing"]} +#{r["wing_up"]}", else: "—"} | #{r["tower"]} #{r["mastery"]} | #{r["pet"] || "—"} | #{r["chars"]}"
  )
end

IO.puts("\nĐã ghi scripts/pvp/tier_profile.json")

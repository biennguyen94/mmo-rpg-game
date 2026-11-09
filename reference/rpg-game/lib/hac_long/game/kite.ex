defmodule HacLong.Game.Kite do
  @moduledoc """
  Thả diều ở Đồi Sáo Diều (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long"), đối xứng câu cá ở Hồ Long Vương
  (`HacLong.Game.Fishing`). Hàm thuần; thời gian truyền vào (mili giây, đồng hồ đơn điệu của server). Số ở `RULES.sky`.

  - `fly/5`: đứng chỗ thoáng trên đồi (không sát cây) thì thả diều vào ô trời (`^`) trong tầm dây diều `reach` (nil: ô trời
    gần nhất phía trên, `sky_near/2`).
    Gió giật sau `wait_ms` ngẫu nhiên.
  - `hold/2`: giữ dây trong `window_ms` kể từ lúc gió giật thì được quà gió (`pool`), +1 Phong Khí; sớm / muộn thì diều
    đứt (không mất gì). Đi chỗ khác thì mất lượt.
  - Chim Lạc (`bird`): lượn ở một ô trời (`HacLong.SkyEvent`). Thả trúng ô đó có `bird.chance` cơ hội ×
    (1 + Phong Khí / `phong_khi_div`) × `bait_mult` nếu có Sáo Đồng (chỉ tốn khi thả trúng); quyết định lúc thả, client
    nhận `big: true`. Giữ dây đúng lúc thì cảm hóa được thú Chim Lạc (mỗi nhân vật một con; đã có thì được `dupe_n`
    `dupe`), kết quả có `rare_pet` để Session ghi Bia Chim Lạc, báo cả server, cho Chim Lạc bay đi. Phong Khí về 0.
  - Đàn Hạc (`flock`): thả trúng ô đó thì quà gió theo `flock.pool`, +`flock.phong_khi` Phong Khí.
  - Ông Lão Làm Diều: thả thành công `elder.count` lần ở đồi trong ngày (`daily.kite_n`) thì nhận thưởng
    (`claim_elder/1`); ghép Sáo Đồng (`craft/1`, `RULES.sky.craft`).

  Trạng thái lượt thả (`kite: %{gust, pos, big, flock}`) chỉ giữ trong Session. Phong Khí ở `sky.phong_khi` (cột `sky`).
  """

  alias HacLong.Game.{Data, Engine, Rng}
  alias HacLong.World.Maps

  @r Data.rules().sky
  @pool Enum.map(@r.pool, &List.to_tuple/1)
  @flock_pool Enum.map(@r.flock.pool, &List.to_tuple/1)
  @bird @r.bird

  def rules, do: @r
  def map_id, do: @r.map

  # ---------- Trạng thái lưu (`p.sky`) ----------

  @doc "Đọc cột `sky` (khóa chuỗi) thành `%{phong_khi, egg, lucky}`."
  def load(%{} = m) do
    egg =
      case m["egg"] do
        %{"at" => at, "kills" => k} = e when is_integer(at) and is_integer(k) ->
          %{at: at, kills: k, boss: e["boss"] == true}

        _ ->
          nil
      end

    %{phong_khi: m["phong_khi"] || 0, egg: egg, lucky: m["lucky"]}
  end

  def load(_), do: %{phong_khi: 0, egg: nil, lucky: nil}

  defp sky(p), do: Map.get(p, :sky) || load(nil)
  def put_sky(p, f), do: Map.put(p, :sky, f.(sky(p)))

  def phong_khi(p), do: sky(p).phong_khi
  def phong_khi_max, do: @bird.phong_khi_max

  def add_phong_khi(p, n),
    do: put_sky(p, &%{&1 | phong_khi: min(&1.phong_khi + n, @bird.phong_khi_max)})

  # ---------- Thả diều ----------

  @doc "Bản đồ `map_id` là Đồi Sáo Diều."
  def hill?(map_id), do: match?(%{kite: true}, Maps.get(map_id))

  # ô cây: đứng sát (8 hướng) thì vướng, không thả diều được
  @trees ~w(T Y K)

  @doc """
  Thả diều được ở chỗ đang đứng không: `:ok` hoặc `{:error, lý_do}`. Đứng chỗ thoáng trên đồi (không sát cây) và có ô trời
  trong tầm dây diều `reach` (anh duyệt 2026-11-09: không cần đứng sát mép trời, như thả diều ngoài đời).
  """
  def check_spot(%{pos: %{map: id, x: x, y: y}}) do
    m = Maps.get(id)

    cond do
      m == nil or not m.kite ->
        {:error, "Thả diều ở Đồi Sáo Diều (cổng mép phải Hồ Long Vương)."}

      Enum.any?(for(dx <- -1..1, dy <- -1..1, do: {dx, dy}), fn {dx, dy} ->
        Maps.tile(m, x + dx, y + dy) in @trees
      end) ->
        {:error, "Vướng cây rồi, ra chỗ thoáng để thả diều."}

      sky_near(m, {x, y}) == nil ->
        {:error, "Xa trời quá: tiến lên gần mép đồi hơn (dây diều dài #{@r.reach} ô)."}

      true ->
        :ok
    end
  end

  def check_spot(_), do: {:error, "Thả diều ở Đồi Sáo Diều."}

  @doc "Mọi ô đứng thả diều được trên bản đồ `m` (đi được, không phải cổng / NPC, không sát cây, có trời trong tầm)."
  def stands(m) do
    for y <- 0..(m.height - 1),
        x <- 0..(m.width - 1),
        Maps.walkable?(m, x, y),
        Maps.tile(m, x, y) not in ~w(D A O),
        check_spot(%{pos: %{map: m.id, x: x, y: y}}) == :ok,
        do: {x, y}
  end

  @doc "Đứng ở đây thả được diều không (`check_spot/1`)."
  def can_fly?(p), do: check_spot(p) == :ok

  @doc "Ô trời diều bay tới khi không chọn ô: ô trời gần nhất phía trên (cùng cột), không thì ô trời gần nhất trong tầm."
  def sky_near(m, {x, y}) do
    up = Enum.find((y - 1)..max(0, y - @r.reach)//-1, &Maps.sky?(m, x, &1))

    if up do
      {x, up}
    else
      for(
        dy <- -@r.reach..@r.reach,
        dx <- -@r.reach..@r.reach,
        Maps.sky?(m, x + dx, y + dy),
        do: {x + dx, y + dy}
      )
      |> Enum.min_by(fn {tx, ty} -> abs(tx - x) + abs(ty - y) end, fn -> nil end)
    end
  end

  @doc "Thả diều vào ô trời `at` (nil: `sky_near/2`). `bird` / `flock`: ô Chim Lạc / Đàn Hạc đang có (nil nếu không)."
  def fly(p, now, at \\ nil, bird \\ nil, flock \\ nil) do
    cond do
      p.battle ->
        {%{ok: false, msg: "Đang trong trận."}, p}

      (err = check_spot(p)) != :ok ->
        {%{ok: false, msg: elem(err, 1)}, p}

      at != nil and not flyable?(p, at) ->
        {%{ok: false, msg: "Ô đó xa quá (dây diều dài #{@r.reach} ô) hoặc không phải trời."}, p}

      true ->
        at = at || sky_near(Maps.get(p.pos.map), {p.pos.x, p.pos.y})
        [lo, hi] = @r.wait_ms
        wait = lo + floor(Rng.uniform() * (hi - lo))
        {p, big} = bird_roll(p, at, bird)
        flock? = flock != nil and at == flock and hill?(p.pos.map)
        reply = %{ok: true, wait: wait, window: @r.window_ms, at: Tuple.to_list(at)}
        reply = if big, do: Map.put(reply, :big, true), else: reply
        reply = if flock?, do: Map.put(reply, :flock, true), else: reply
        {reply, Map.put(p, :kite, %{gust: now + wait, pos: p.pos, big: big, flock: flock?})}
    end
  end

  # ô trời trong tầm `reach` (Chebyshev) của chỗ đứng
  defp flyable?(%{pos: %{map: id, x: x, y: y}}, {tx, ty}) do
    m = Maps.get(id)
    max(abs(tx - x), abs(ty - y)) <= @r.reach and Maps.sky?(m, tx, ty)
  end

  @doc "Cơ hội cảm hóa Chim Lạc khi thả trúng ô của nó (có / không có Sáo Đồng)."
  def bird_chance(p, bait?) do
    @bird.chance * (1 + phong_khi(p) / @bird.phong_khi_div) *
      if(bait?, do: @bird.bait_mult, else: 1)
  end

  defp bird_roll(p, at, bird) do
    if bird != nil and at == bird and hill?(p.pos.map) do
      bait? = Map.get(p.inv, @bird.bait, 0) > 0
      chance = bird_chance(p, bait?)
      p = if bait?, do: Engine.take_item(p, @bird.bait), else: p
      {p, Rng.uniform() < chance}
    else
      {p, false}
    end
  end

  @doc "Giữ dây diều khi gió giật."
  def hold(p, now) do
    k = Map.get(p, :kite)
    p = Map.put(p, :kite, nil)

    cond do
      k == nil ->
        {%{ok: false, msg: "Bạn chưa thả diều."}, p}

      k.pos != p.pos ->
        {%{ok: false, msg: "Bạn đã rời chỗ thả diều."}, p}

      now < k.gust ->
        {%{ok: false, msg: "Giật dây sớm quá, diều chao đảo rồi rơi."}, p}

      now > k.gust + @r.window_ms and k[:big] ->
        {%{ok: false, msg: "Dây diều đứt phựt! Bóng chim đồng lấp lánh vút lên mây..."}, p}

      now > k.gust + @r.window_ms ->
        {%{ok: false, msg: "Chậm tay rồi, gió cuốn diều đi mất."}, p}

      k[:big] ->
        land_bird(p)

      true ->
        catch_gift(p, k[:flock])
    end
  end

  @doc "Chim Lạc sà xuống đậu vào diều (tách riêng để kiểm thử)."
  def land_bird(p) do
    pet = @bird.pet
    owned = Map.get(p, :pets) || []

    if pet in owned do
      {r, p} = land(p, @bird.dupe, 1, @bird.dupe_n)

      {%{
         r
         | msg:
             "🐦 Chim Lạc lượn quanh diều, để lại #{@bird.dupe_n} #{Data.item(@bird.dupe).name} rồi bay đi."
       }, p}
    else
      p = p |> Map.put(:pets, owned ++ [pet]) |> put_sky(&%{&1 | phong_khi: 0})
      name = Data.pet(pet).name

      {%{
         ok: true,
         msg:
           "🐦 #{name} sà xuống đậu trên diều của bạn! Thần điểu đã nhận bạn làm chủ. Dắt theo ở tab Nhân vật.",
         rare_pet: pet
       }, p}
    end
  end

  defp catch_gift(p, true), do: land(p, roll(@flock_pool), @r.flock.phong_khi)
  defp catch_gift(p, _), do: land(p, roll(@pool))

  @doc "Đưa quà gió `id` (× `n`) vào túi, +`pk` Phong Khí, tính việc Ông Lão (tách riêng để kiểm thử)."
  def land(p, id, pk \\ 1, n \\ 1) do
    p = Engine.add_item(p, id, n)

    p =
      if id == "day_dieu_dut" or not hill?(p.pos.map),
        do: p,
        else: p |> add_phong_khi(pk) |> on_kite(@r.elder.count)

    name = Data.item(id).name

    msg =
      case id do
        "day_dieu_dut" -> "Diều kéo về... #{name}. Thôi thì cũng là một món."
        "manh_sao" -> "✨ Diều vướng #{if n > 1, do: "#{n} ", else: ""}#{name}! Hiếm lắm đấy!"
        "jewel_" <> _ -> "💎 Gió cuốn #{name} vào diều!"
        _ -> "Diều mang về #{name}!"
      end

    {%{ok: true, msg: msg, gift: id}, p}
  end

  defp on_kite(%{daily: %{} = d} = p, max),
    do: %{p | daily: Map.put(d, :kite_n, min((d[:kite_n] || 0) + 1, max))}

  defp on_kite(p, _max), do: p

  defp roll(pool) do
    total = pool |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    r = Rng.uniform() * total

    Enum.reduce_while(pool, 0, fn {w, id}, acc ->
      if r < acc + w, do: {:halt, id}, else: {:cont, acc + w}
    end)
  end

  # ---------- Ông Lão Làm Diều ----------

  @doc "Việc của Ông Lão hôm nay: `%{n, count, done, reward: %{gold, xp, phong_khi}}` (thưởng theo cấp nhân vật)."
  def elder(p) do
    r = Data.rules().daily.reward.fish
    c = @r.elder.count

    %{
      n: min(get_in(p, [:daily, :kite_n]) || 0, c),
      count: c,
      done: get_in(p, [:daily, :kite_done]) == true,
      reward: %{
        gold: round(Engine.base_gold(p.level) * c * r.gold),
        xp: round(Engine.base_xp(p.level) * c / r.xp_div),
        phong_khi: @r.elder.phong_khi
      }
    }
  end

  @doc "Nhận thưởng việc của Ông Lão Làm Diều (thả đủ diều ở đồi hôm nay, mỗi ngày một lần)."
  def claim_elder(p) do
    e = elder(p)

    cond do
      p[:daily] == nil or e.n < e.count ->
        {%{
           ok: false,
           msg:
             "Thả diều thành công đủ #{e.count} lần ở đồi này rồi quay lại nhé (#{e.n}/#{e.count})."
         }, p}

      e.done ->
        {%{ok: false, msg: "Hôm nay lão trả công rồi, mai lại đến."}, p}

      true ->
        p = %{p | gold: p.gold + e.reward.gold} |> add_phong_khi(e.reward.phong_khi)
        p = put_in(p, [:daily, :kite_done], true)
        {_levels, p} = Engine.gain_xp(p, e.reward.xp)

        {%{
           ok: true,
           msg:
             "Ông Lão cười khà: +#{e.reward.gold} vàng, +#{e.reward.xp} kinh nghiệm, +#{e.reward.phong_khi} Phong Khí."
         }, p}
    end
  end

  @doc "Ghép một Sáo Đồng từ nguyên liệu `RULES.sky.craft.sao_dong`."
  def craft(p) do
    need = @r.craft.sao_dong

    lack =
      for {id, n} <- need,
          Map.get(p.inv, to_string(id), 0) < n,
          do: "#{Data.item(to_string(id)).name} #{Map.get(p.inv, to_string(id), 0)}/#{n}"

    if lack != [] do
      {%{ok: false, msg: "Chưa đủ nguyên liệu: #{Enum.join(lack, ", ")}."}, p}
    else
      p = Enum.reduce(need, p, fn {id, n}, p -> Engine.take_item(p, to_string(id), n) end)
      p = Engine.add_item(p, @bird.bait)
      {%{ok: true, msg: "Ông Lão gắn xong một #{Data.item(@bird.bait).name}, gió thổi vi vu."}, p}
    end
  end
end

defmodule HacLong.Bots.Brain do
  @moduledoc """
  Bộ não người chơi AI (Phase 16): hàm thuần, từ nhân vật `p` và trạng thái bản đồ đang đứng `snap`
  (`MapServer.snapshot/1`, nil ở bản đồ riêng) trả về **một lệnh** như client gửi (`%{"act" => ...}`)
  hoặc nil (đứng chờ). Bot gửi lệnh qua `Session` nên theo đúng luật, giới hạn tốc độ như người thật.

  Thứ tự ưu tiên:
  1. Chưa có nhân vật → tạo (`name`, `cls` do tiến trình bot chọn).
  2. Trong trận: xong → rời; máu < 35 % và có bình → uống; MP thiếu và có bình mana → uống mana;
     kỹ năng mạnh nhất đang sẵn → dùng; còn lại đánh thường.
  3. Còn điểm tiềm năng → cộng hết vào chỉ số chính của lớp.
  4. Trong túi có vũ khí / giáp / khiên tốt hơn đồ đang mặc → mặc.
  5. Máu < 45 % và có bình → uống.
  6. Sắp hết bình (Phase 5, `RULES.bots.potion_min` / `mana_min`) mà đủ vàng → về Làng mua ở Bà Lang (`restock/1`).
  7. Máu < 45 %, hết bình: đủ vàng thì nghỉ ở Quán Trọ Làng, không thì uống nước giếng giữa Làng (miễn phí).
  8. Chưa ở bản đồ hợp cấp → dịch chuyển (nếu được và đủ vàng) hoặc đi bộ qua cổng theo đường ngắn nhất.
  9. Ở bản đồ hợp cấp → đi tới con quái gần nhất không ai đánh, cấp không quá cấp mình + 1.
  10. Đủ cấp (cấp trùm + 1) mà trùm vùng kế tiếp chưa hạ → vào phòng trùm đánh để mở vùng mới.
  11. Cấp tối đa, đủ điều kiện → về Làng chuyển sinh (Trưởng Làng); cần hạ chúa tể vùng chuyển sinh trước thì đi vùng đó.
  12. Rảnh mà dư vàng, có ngọc → về Làng ép đồ / thêm dòng / ghép, nâng cánh (`forge_job/2`, DECISIONS "Bot ép đồ,
      chuyển sinh"). Đang chờ ghép cánh (cánh đã tháo ra túi) thì làm trước cả bước mặc đồ.
  13. Túi trang bị gần đầy → về Làng bán đồ thừa ở Thợ Rèn (`sell_job/1`); cho thú ăn mỗi vài phút (`opts.feed_due`).
  14. Gục nhiều lần ở một chỗ (phòng trùm đánh không lại, bản đồ quá mạnh) → tạm tránh chỗ đó (`opts.avoid`, tiến trình
      bot ghi bằng `note_death/3`); chuyển sinh tối đa + cấp tối đa → luyện ở vùng chuyển sinh, khó dần
      (`realm_target/2`; DECISIONS "Bot cuối game").

  16. Sự kiện (DECISIONS "Bot đi sự kiện", `RULES.bots.events`): Cổ Long còn sống (`opts.world_boss`) → về Tế Đàn đánh;
      Mảnh Sao trên Đồi Sáo Diều (`opts.stars`) → nhặt; Golden Invasion (`opts.invasion`, bản đồ còn quái vàng) → sang
      bản đồ hợp cấp, đánh quái vàng trước.

  15. Câu cá (DECISIONS "Bot câu cá, bot try hard"): Long Vương nổi thì bot săn rồng (`chaser?/1`, chưa có Ngài) bỏ việc
      rảnh, kể cả đang leo Tháp Vô Tận, ra Biển Long Vương thả trúng ô Ngài; tới lượt ra hồ (`opts.fishing`) thì câu ở ô
      Đàn Cá Vàng hoặc ô nước cạnh bên, câu đủ cá thì nhận việc Ông Lão. Bot try hard (`tryhard?/1`) chơi dồn dập hơn.

  Vừa gục (số lần chết tăng) thì nghỉ ngẫu nhiên `RULES.bots.rest_after_death_s` giây ([ít nhất, nhiều nhất]) trước
  khi đi luyện tiếp (`rest_until/4`, `resting?/3`); không thì bot dịch chuyển về chỗ cũ ngay sau vài giây, trông như
  chưa chết.
  """
  alias HacLong.Game.{
    BloodCastle,
    Data,
    DevilSquare,
    Engine,
    Fishing,
    Gear,
    Kalima,
    Pets,
    Rng,
    Tower
  }

  alias HacLong.World
  alias HacLong.World.Maps

  @main %{"dk" => "str", "dw" => "ene", "elf" => "agi", "mg" => "str"}
  @dirs %{"up" => {0, -1}, "down" => {0, 1}, "left" => {-1, 0}, "right" => {1, 0}}

  @rest Data.rules().bots.rest_after_death_s
  @shop Data.rules().bots
  @hp_ids ~w(potion_s potion_m potion_l)
  @mp_ids ~w(mana_s mana_m mana_l)

  @doc """
  Mốc (ms) bot được đi luyện tiếp: số lần chết của `p` tăng so với `prev_deaths` (lần trước bot nhìn) thì nghỉ
  ngẫu nhiên trong `RULES.bots.rest_after_death_s` giây tính từ `now`; không thì giữ `until`.
  """
  def rest_until(until, prev_deaths, p, now, mult \\ 1) do
    if is_integer(prev_deaths) and p != nil and (p[:deaths] || 0) > prev_deaths do
      [lo, hi] = @rest
      now + round((lo + Rng.uniform() * (hi - lo)) * 1000 * mult)
    else
      until
    end
  end

  @doc "Đang nghỉ sau khi gục: chưa tới mốc và không ở trong trận (trận đã xong thì vẫn rời trận như thường)."
  def resting?(p, until, now), do: p != nil and p.battle == nil and now < until

  def decide(p, snap, opts \\ %{})

  def decide(nil, _snap, opts),
    do: %{"act" => "create", "name" => opts[:name] || "Lữ Khách", "cls" => opts[:cls] || "dk"}

  def decide(%{battle: %{over: true}}, _snap, _opts), do: %{"act" => "leave"}
  # đồ sát: chưa tới lượt thì chờ (không gửi lệnh)
  def decide(%{battle: %{live: true, encounter: %{mine: false}}}, _snap, _opts), do: nil
  def decide(%{battle: %{}} = p, _snap, _opts), do: fight(p)

  def decide(p, snap, opts) do
    d = Engine.derived(p)

    cond do
      p.points > 0 ->
        alloc(p)

      # đã thả câu, tiến trình bot hẹn giờ giật cần (`opts.reeling`): đứng yên chờ
      opts[:reeling] == true and (p[:fishing] != nil or p[:kite] != nil) ->
        nil

      # cánh đã tháo ra túi để ghép lên cấp: ghép trước (không thì bước mặc đồ lại mặc vào)
      job = wing_combine(p, spare_gold(p)) ->
        do_job(p, job, snap)

      g = better_gear(p) ->
        g

      p.hp < d.maxHp * 0.45 and Engine.best_potion(p, d.maxHp - p.hp) ->
        %{"act" => "use", "id" => Engine.best_potion(p, d.maxHp - p.hp)}

      # trong Tháp / Quảng Trường / Lâu Đài / Kalima: đánh hết quái, lên tầng / đợt hoặc ra cổng
      # ở bản đồ tháp quá lâu (`opts.tower_stuck`, tiến trình bot đo): ra cổng
      p.pos.map == "tower" and opts[:tower_stuck] == true and p[:tower] != nil ->
        tower_walk(p, [List.to_tuple(p.tower.exit)]) || idle_step(p)

      # Long Vương nổi: bot săn rồng bỏ dở Tháp Vô Tận (không bỏ Quảng Trường / Lâu Đài / Kalima) ra hồ
      p.pos.map == "tower" and plain_tower?(p) and chasing?(p, opts) ->
        tower_walk(p, [List.to_tuple(p.tower.exit)]) || idle_step(p)

      p.pos.map == "tower" ->
        tower_play(p, d, opts)

      (need = restock(p)) != [] ->
        shop(p, need, snap)

      p.hp < d.maxHp * 0.45 ->
        heal(p, d, snap)

      rebirth_ready?(p) ->
        at_village_npc(p, "quests", snap, fn -> %{"act" => "rebirth"} end)

      cmd = fish_job(p, snap, opts, :chase) ->
        cmd

      cmd = world_boss_job(p, d, opts) ->
        cmd

      cmd = star_job(p, snap, opts) ->
        cmd

      job = event_job(p, d) ->
        if job == :heal, do: heal(p, d, snap), else: do_job(p, job, snap)

      job = sell_job(p) ->
        do_job(p, job, snap)

      job = pet_job(p, opts) ->
        do_job(p, job, snap)

      job = forge_job(p, opts) ->
        do_job(p, job, snap)

      cmd = fish_job(p, snap, opts, :idle) ->
        cmd

      job = tower_job(p, d, opts) ->
        if job == :heal, do: heal(p, d, snap), else: do_job(p, job, snap)

      true ->
        roam(p, snap, opts)
    end
  end

  @doc """
  Huyết Nguyệt (DECISIONS "Pháp Trường Huyết Nguyệt"), bot `me` được gọi vào Pháp Trường, ngoài trận:

  - trận vừa xong thì rời trận; đang đánh quái / leo Tháp (`Session.teleport/2` kết thúc trận như bỏ chạy, rời tháp) thì
    bỏ ngang đi luôn;
  - chưa ở Pháp Trường: còn bị khóa (`locked_s` > 0, vừa gục) thì chờ; máu thấp thì uống bình; rồi `{:teleport, ô}`
    (một ô đất ngẫu nhiên trên sân);
  - ở Pháp Trường: máu thấp thì uống bình; người gần nhất (không phải mình, không đang được bảo vệ, đủ cấp đồ sát) trong
    tầm đánh thì `{:slay, uid}`, xa thì đi tới; không có ai thì đi lang thang.
  """
  def blood_job(p, snap, me, locked_s, altar \\ nil) do
    d = Engine.derived(p)
    pot = p.hp < d.maxHp * 0.45 && Engine.best_potion(p, d.maxHp - p.hp)
    map_id = HacLong.BloodMoon.map_id()

    cond do
      match?(%{battle: %{over: true}}, p) ->
        %{"act" => "leave"}

      p.battle != nil and p.pos.map == map_id ->
        fight(p)

      pot && p.battle == nil ->
        %{"act" => "use", "id" => pot}

      p.pos.map != map_id and locked_s > 0 ->
        nil

      p.pos.map != map_id ->
        {:teleport, Enum.random(HacLong.BloodMoon.map_spawns())}

      true ->
        blood_target(p, snap, me, altar)
    end
  end

  # Bàn thờ đang sáng (`altar`: các ô): người trong tầm thì đánh, không thì ra bàn thờ đứng giữ (đã đứng trên đó thì chờ)
  defp blood_target(p, snap, me, altar) do
    min = Data.rules().slay.min_level
    at = fn o -> max(abs(o.x - p.pos.x), abs(o.y - p.pos.y)) end

    foes =
      ((snap && snap.players) || [])
      |> Enum.reject(&(&1.id == me or &1.safe or &1.level < min))
      |> Enum.sort_by(at)

    on_altar = altar != nil and {p.pos.x, p.pos.y} in altar

    case foes do
      [o | _] when is_map(o) ->
        cond do
          at.(o) <= Gear.reach(p) -> {:slay, o.id}
          on_altar -> nil
          altar != nil -> walk(p, Maps.get(p.pos.map), altar, snap) || wander(p)
          true -> walk(p, Maps.get(p.pos.map), [{o.x, o.y}], snap) || wander(p)
        end

      [] ->
        cond do
          on_altar -> nil
          altar != nil -> walk(p, Maps.get(p.pos.map), altar, snap) || wander(p)
          true -> wander(p)
        end
    end
  end

  @doc """
  Cộng điểm (DECISIONS "Máu theo chuyển sinh"): khoảng `RULES.bots.vit_share` số điểm đã cộng vào Thể lực, còn lại vào
  chỉ số chính của lớp.
  """
  def alloc(p) do
    base = Data.class(p.cls).base
    spent = Enum.sum(Map.values(p.stats)) - Enum.sum(Map.values(base))

    need =
      Map.get(base, :vit, 0) + round(@shop.vit_share * (spent + p.points)) -
        Map.get(p.stats, :vit, 0)

    if need > 0,
      do: %{"act" => "alloc", "stat" => "vit", "n" => min(p.points, need)},
      else: %{"act" => "alloc", "stat" => @main[p.cls] || "str", "n" => min(p.points, 99)}
  end

  # ---------- Sự kiện (DECISIONS "Bot đi sự kiện") ----------
  @ev Data.rules().bots.events

  @doc "Cổ Long còn sống (`opts.world_boss`): bot đủ cấp, đủ máu về Tế Đàn, bước vào ô trùm (vào trận luôn)."
  def world_boss_job(p, d, opts) do
    wb = @ev.world_boss
    altar = opts[:world_boss] == true && Maps.get(wb.map)

    cond do
      !altar or altar.world_boss == nil -> nil
      p.level < wb.min_level or p.hp < d.maxHp * wb.hp_pct -> nil
      p.pos.map != altar.id -> go_to(p, altar.id)
      true -> walk(p, altar, [altar.world_boss], nil)
    end
  end

  @doc "Mảnh Sao (`opts.stars`, `[[x, y]]`) trên Đồi Sáo Diều, bot đang ở đồi: đứng cạnh thì nhặt, xa thì đi tới."
  def star_job(p, snap, opts) do
    stars = for [x, y] <- opts[:stars] || [], do: {x, y}
    hill = HacLong.Game.Kite.map_id()

    if @ev.star and stars != [] and p.pos.map == hill do
      me = {p.pos.x, p.pos.y}
      {x, y} = Enum.min_by(stars, &dist(me, &1))

      if dist(me, {x, y}) <= 1,
        do: %{"act" => "star_pick", "x" => x, "y" => y},
        else: walk(p, Maps.get(hill), [{x, y}], snap)
    end
  end

  @doc """
  Golden Invasion đang chạy (`opts.invasion`: `%{id bản đồ => "run" | "boss" | "done"}`): bản đồ còn quái vàng, hợp cấp
  (như `target_map/2`: quái không quá cấp mình + 1), chọn bản đồ quái cao nhất; nil nếu không có.
  """
  def invasion_map(p, inv) when is_map(inv) and map_size(inv) > 0 do
    if @ev.invasion do
      for {id, st} <- inv,
          st in ["run", "boss"],
          m = Maps.get(id),
          m != nil and reachable?(p, m),
          lo = World.min_level(m),
          lo != nil and lo <= p.level,
          hi = max_level(m),
          hi <= p.level + 1 do
        {hi, id}
      end
      |> Enum.max(fn -> nil end)
      |> then(&(&1 && elem(&1, 1)))
    end
  end

  def invasion_map(_p, _inv), do: nil

  # ---------- Câu cá, săn Long Vương (DECISIONS "Bot câu cá, bot try hard") ----------
  @fish Data.rules().bots.fish
  @tryhard Data.rules().bots.tryhard
  @reach Data.rules().fishing.dragon.reach
  @dragon_pet Data.rules().fishing.dragon.pet

  @doc "Bot try hard (`RULES.bots.tryhard.every`): chơi dồn dập hơn, luôn săn Long Vương, luôn ép liều."
  def tryhard?(seed) when is_integer(seed), do: rem(seed, @tryhard.every) == 0
  def tryhard?(_), do: false

  @doc "Bot đi săn Long Vương khi Ngài nổi: bot try hard hoặc seed chia hết cho `RULES.bots.fish.chase_every`."
  def chaser?(seed) when is_integer(seed), do: tryhard?(seed) or rem(seed, @fish.chase_every) == 0
  def chaser?(_), do: false

  @doc """
  Câu cá ở Biển Long Vương. `mode` `:chase`: Long Vương đang nổi (`opts.dragon`, ô `{x, y}`), bot săn rồng chưa có Ngài →
  ra hồ, đứng trong tầm câu, thả trúng ô Ngài. `:idle`: đang trong lượt ra hồ (`opts.fishing`, tiến trình bot hẹn) →
  câu ở ô Đàn Cá Vàng nếu có (`opts.school`), không thì ô nước cạnh bên; câu đủ cá thì nhận việc Ông Lão. Chưa đủ cấp
  vào hồ thì nil.
  """
  def fish_job(p, snap, opts, mode) do
    if mode == :idle and opts[:fishing] == true and kiter?(opts[:seed]),
      do: kite_job(p, snap, opts),
      else: lake_job(p, snap, opts, mode)
  end

  @doc """
  Bot thả diều (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long"): một nửa số bot (seed lẻ) dùng lượt "ra hồ" để ra Đồi Sáo Diều.
  Đứng chỗ thoáng trên đồi (`Kite.stands/1`, mỗi bot một chỗ, `spread/5`), thả vào ô Chim Lạc nếu đang lượn và chưa có, không thì ô Đàn Hạc, không thì
  lên giữa trời (`Kite.aim/3`); thả đủ thì nhận việc Ông Lão Làm Diều.
  """
  def kiter?(seed) when is_integer(seed), do: rem(seed, 2) == 1
  def kiter?(_), do: false

  def kite_job(p, snap, opts) do
    hill = Maps.get(HacLong.Game.Kite.map_id())
    e = HacLong.Game.Kite.elder(p)
    bird = opts[:bird]

    target =
      cond do
        bird && HacLong.Game.Kite.rules().bird.pet not in (Map.get(p, :pets) || []) -> bird
        opts[:flock] -> opts[:flock]
        true -> :any
      end

    cond do
      hill == nil or p.level < (hill[:min_level] || 1) ->
        nil

      p.pos.map != hill.id ->
        go_to(p, hill.id)

      p[:daily] != nil and e.n >= e.count and not e.done ->
        at_npc_cmd(p, hill, "kite_maker", %{"act" => "kite_elder"}, snap)

      true ->
        kite_at(p, hill, target, snap, opts[:seed])
    end
  end

  defp at_npc_cmd(p, map, id, cmd, snap) do
    n = Enum.find(map.npcs, &(&1.id == id))
    {nx, ny} = n.at

    if max(abs(p.pos.x - nx), abs(p.pos.y - ny)) <= 1,
      do: cmd,
      else: walk(p, map, for({dx, dy} <- Map.values(@dirs), do: {nx + dx, ny + dy}), snap) || cmd
  end

  defp kite_at(p, map, target, snap, seed) do
    me = {p.pos.x, p.pos.y}

    # dây diều không giới hạn: đứng chỗ thoáng nào cũng thả tới ô Chim Lạc / Đàn Hạc (gần ô đó hơn cho tự nhiên)
    all =
      case target do
        :any ->
          sky_stands(map)

        {tx, _} ->
          for {x, y} <- sky_stands(map), abs(x - tx) <= 4, do: {x, y}
      end

    stands =
      if target == :any,
        do: spread(all, Map.put(p, :fishing, p[:kite]), me, seed, snap),
        else: all

    cond do
      all == [] and target != :any ->
        kite_at(p, map, :any, snap, seed)

      me in stands ->
        case target do
          {x, y} -> %{"act" => "kite_fly", "x" => x, "y" => y}
          :any -> %{"act" => "kite_fly"}
        end

      true ->
        walk(p, map, stands, snap)
    end
  end

  @doc "Ô đứng thả diều được trên bản đồ `map` (`HacLong.Game.Kite.stands/1`: chỗ thoáng, có trời trong tầm dây diều)."
  def sky_stands(map), do: HacLong.Game.Kite.stands(map)

  defp lake_job(p, snap, opts, mode) do
    lake = Maps.get(HacLong.LakeEvent.map_id())

    target =
      case mode do
        :chase ->
          if chasing?(p, opts), do: opts[:dragon]

        :idle ->
          if opts[:fishing] == true, do: opts[:school] || :any
      end

    cond do
      target == nil or lake == nil or p.level < (lake[:min_level] || 1) ->
        nil

      p.pos.map != lake.id ->
        go_to(p, lake.id)

      mode == :idle and elder_ready?(p) ->
        %{"act" => "elder_claim"}

      true ->
        fish_at(p, lake, target, snap, opts[:seed])
    end
  end

  defp plain_tower?(%{tower: %{} = t}), do: t[:ds] == nil and t[:bc] == nil and t[:kal] == nil
  defp plain_tower?(_), do: false

  @doc "Long Vương đang nổi (`opts.dragon`), bot này săn rồng và chưa có Ngài, đủ cấp vào Biển Long Vương."
  def chasing?(p, opts) do
    lake = Maps.get(HacLong.LakeEvent.map_id())

    opts[:dragon] != nil and chaser?(opts[:seed]) and lake != nil and
      p.level >= (lake[:min_level] || 1) and @dragon_pet not in (Map.get(p, :pets) || [])
  end

  defp elder_ready?(p) do
    e = Fishing.elder(p)
    p[:daily] != nil and e.n >= e.count and not e.done
  end

  defp fish_at(p, map, target, snap, seed) do
    me = {p.pos.x, p.pos.y}

    all =
      case target do
        :any ->
          stand_tiles(map)

        {tx, ty} ->
          for {x, y} <- stand_tiles(map), max(abs(x - tx), abs(y - ty)) <= @reach, do: {x, y}
      end

    # Long Vương / Đàn Cá Vàng: cần nhanh, ô nào trong tầm cũng được; câu thường thì mỗi bot một chỗ
    stands = if target == :any, do: spread(all, p, me, seed, snap), else: all

    cond do
      all == [] and target != :any ->
        fish_at(p, map, :any, snap, seed)

      me in stands ->
        case target do
          {x, y} -> %{"act" => "fish_cast", "x" => x, "y" => y}
          :any -> %{"act" => "fish_cast"}
        end

      true ->
        walk(p, map, stands, snap) || if(Fishing.near_water?(p), do: %{"act" => "fish_cast"})
    end
  end

  # Mỗi bot một chỗ câu (anh báo "bot dồn một ô"): trước đây đi tới ô câu gần nhất nên con nào cũng về cùng một ô.
  # Đang câu ở ô hợp lệ không ai đứng thì ở lại; không thì chọn trong các ô còn trống một ô theo seed của bot (đổi mỗi giờ
  # cho khác lượt trước), ô đã có người khác đứng thì bỏ qua (hết ô trống thì chọn trong tất cả).
  @doc false
  def spread([], _p, _me, _seed, _snap), do: []

  def spread(stands, p, me, seed, snap) do
    others =
      for o <- (snap && snap[:players]) || [], o.id != seed, into: MapSet.new(), do: {o.x, o.y}

    if p[:fishing] != nil and me in stands and me not in others do
      [me]
    else
      free = Enum.reject(stands, &(&1 in others))
      pool = if free == [], do: stands, else: free
      hour = div(System.os_time(:second), 3600)
      [Enum.min_by(pool, fn {x, y} -> :erlang.phash2({seed, x, y, hour}) end)]
    end
  end

  @doc "Ô đứng câu được trên bản đồ `map`: đi được, không phải cổng, cạnh (4 hướng) một ô nước."
  def stand_tiles(map) do
    for y <- 0..(map.height - 1),
        x <- 0..(map.width - 1),
        plain?(map, {x, y}),
        Enum.any?(Map.values(@dirs), fn {dx, dy} -> Maps.water?(map, x + dx, y + dy) end),
        do: {x, y}
  end

  # ---------- Ép đồ, cánh, chuyển sinh ----------
  @forge Data.rules().bots.forge
  @life Data.rules().upgrade.life
  @max_level Data.rules().character.max_level
  @max_rebirths Data.rules().character.max_rebirths
  # bot chuyển sinh tới trần riêng (DECISIONS "Bot chuyển sinh quá 10, chọn vùng theo thang")
  @bot_rebirths Data.rules().bots.max_rebirths
  @ladder_margin Data.rules().bots.ladder_margin
  @per_day Data.rules().character.rebirth_per_day

  # bot dừng ở mốc chuyển sinh tối đa (không chuyển sinh vô hạn, DECISIONS "Chuyển sinh vô hạn"): quá mốc thì không
  # còn chúa tể phải hạ
  # chúa tể cần hạ trước lần chuyển sinh tới (cả khi quá mốc 10: hạ lại chúa tể vùng cuối); đã tới trần của bot thì không
  defp need(p),
    do: if((Map.get(p, :rebirths) || 0) >= @bot_rebirths, do: nil, else: Engine.rebirth_need(p))

  # vàng được tiêu cho rèn (giữ lại `gold_keep_per_level` × cấp để mua bình)
  defp spare_gold(p), do: p.gold - @forge.gold_keep_per_level * p.level

  # `{vai NPC ở Làng hoặc nil, lệnh}`: đi tới NPC rồi gửi lệnh (nil: gửi ngay)
  defp do_job(_p, {nil, cmd}, _snap), do: cmd
  defp do_job(p, {role, cmd}, snap), do: at_village_npc(p, role, snap, fn -> cmd end)

  @doc "Cấp tối đa, đủ điều kiện chuyển sinh (đã hạ chúa tể nếu cần, chưa chuyển sinh tối đa)."
  def rebirth_ready?(p) do
    p.level >= @max_level and (Map.get(p, :rebirths) || 0) < @bot_rebirths and
      need(p) == nil and Engine.rebirths_today(p) < @per_day
  end

  @doc """
  Vùng chuyển sinh hợp sức với bot theo thang vùng co giãn (`HacLong.RealmLadder`): vùng cao nhất đã mở (chuyển sinh ≥ số
  vùng) có mức hiện tại ≤ CS + `bots.ladder_margin`; không có thì vùng 1.
  """
  def ladder_realm(p, ks \\ HacLong.RealmLadder.ks()) do
    cs = Map.get(p, :rebirths) || 0

    ks
    |> Enum.with_index(1)
    |> Enum.filter(fn {k, r} -> r <= cs and k <= cs + @ladder_margin end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.max(fn -> 1 end)
  end

  @doc """
  Việc rèn bot làm được bây giờ: `{vai NPC, lệnh}` hoặc nil. Thứ tự: ép món đang mặc cấp thấp nhất (bước có thể hỏng chỉ
  khi dư ngọc; +10 / +11 chỉ bot liều), thêm dòng Ngọc Sinh Mệnh, ghép / nâng cánh.
  """
  def forge_job(p, opts \\ %{}) do
    spare = spare_gold(p)

    # chưa có cánh: làm cánh trước (không thì Ngọc Ước Nguyện cứ bị dùng ép lại đồ mới mặc, không bao giờ đủ cho
    # món làm cánh); có cánh rồi thì ép đồ, cánh như thường rồi mới nâng cánh
    cond do
      spare <= 0 -> nil
      p.equip[:wing] == nil -> wing_job(p, spare) || upgrade_job(p, spare, opts) || life_job(p)
      true -> upgrade_job(p, spare, opts) || life_job(p) || wing_job(p, spare)
    end
  end

  defp has?(p, items, extra \\ 0),
    do: Enum.all?(items, fn {m, n} -> Map.get(p.inv, to_string(m), 0) >= n + extra end)

  defp upgrade_job(p, spare, opts) do
    daring = rem(opts[:seed] || 1, @forge.daring_every) == 0 or tryhard?(opts[:seed] || 1)

    p.equip
    |> Enum.flat_map(fn {slot, id} ->
      it = id && Gear.item(p, id)
      lv = if id, do: Engine.upgrade_level(p, id), else: 0
      cost = it && Engine.upgrade_cost(it, lv)

      ok =
        cost && cost.gold <= spare &&
          has?(p, cost.items, if(cost.fail, do: @forge.spare, else: 0)) &&
          (cost.at == "smith" or daring)

      if ok, do: [{lv + focus_lead(slot), slot, cost.at}], else: []
    end)
    |> Enum.sort()
    |> case do
      [] ->
        nil

      [{_, slot, "smith"} | _] ->
        {"shop", %{"act" => "upgrade", "slot" => to_string(slot), "confirm" => true}}

      [{_, slot, _} | _] ->
        {"chaos", %{"act" => "chaos_upgrade", "slot" => to_string(slot), "confirm" => true}}
    end
  end

  # dồn ngọc vào món đáng giá (vũ khí, giáp, cánh, khiên: `forge.focus_slots`) trước: các ô khác chỉ ép khi kém món
  # đáng giá thấp nhất `forge.focus_lead` cấp (DECISIONS "Bot dùng ngọc khôn hơn")
  defp focus_lead(slot),
    do: if(to_string(slot) in @forge.focus_slots, do: 0, else: @forge.focus_lead)

  defp life_job(p) do
    if Map.get(p.inv, @life.jewel, 0) >= 1 do
      Enum.find_value(@forge.life_slots, fn slot ->
        id = p.equip[String.to_existing_atom(slot)]
        g = id && Gear.instance?(id) && Gear.find(p, id)
        lines = (g && g[:opt]) || 0

        if id && lines < @life.max_lines,
          do: {"shop", %{"act" => "life", "slot" => slot}}
      end)
    end
  end

  defp wing_recipe(tier), do: Data.chaos("wing#{tier}")

  defp wing_tier(p, id), do: (id && (Gear.item(p, id) || %{})[:tier]) || 0

  # cánh trong túi (vừa tháo ra) đủ điều kiện công thức kế tiếp: ghép ngay ở Máy Hỗn Nguyên
  defp wing_combine(p, spare) do
    Enum.find_value(Gear.bag(p), fn g ->
      it = Gear.resolve(g)
      r = it.slot == "wing" && wing_recipe((it[:tier] || 0) + 1)

      if r && r.gold <= spare && has?(p, r.items) && it[:tier] == r.gear[:tier] &&
           Engine.upgrade_level(p, g.uid) >= r.gear.min_up && !g[:locked] do
        {"chaos", %{"act" => "chaos", "id" => r.id, "gear" => g.uid}}
      end
    end)
  end

  defp wing_job(p, spare) do
    worn = p.equip[:wing]
    r = wing_recipe(wing_tier(p, worn) + 1)
    ready = r != nil and r.gold <= spare and has?(p, r.items)

    cond do
      r == nil ->
        nil

      # chưa có cánh: ép sẵn món làm cánh lên +min_up (kể cả khi chưa đủ Ngọc Hỗn Nguyên / vàng để ghép)
      worn == nil ->
        first_wing(p, r, spare, ready)

      not ready ->
        nil

      # đang mặc cánh đủ cấp ép: tháo ra để ghép lên cấp (bước kế tiếp: `wing_combine/2`)
      worn && Engine.upgrade_level(p, worn) >= r.gear.min_up ->
        {nil, %{"act" => "unequip", "slot" => "wing"}}

      true ->
        nil
    end
  end

  # một món trong túi (vũ khí / giáp / khiên) ép tới +min_up rồi bỏ vào máy
  defp first_wing(p, r, spare, ready) do
    bag =
      for g <- Gear.bag(p),
          !g[:locked],
          Gear.resolve(g).slot in r.gear.slots,
          do: {Engine.upgrade_level(p, g.uid), g.uid}

    case Enum.sort(bag, :desc) do
      [{up, uid} | _] when up >= r.gear.min_up ->
        if ready, do: {"chaos", %{"act" => "chaos", "id" => r.id, "gear" => uid}}

      [{up, uid} | _] ->
        cost = Engine.upgrade_cost(Gear.item(p, uid), up)

        if cost && cost.at == "smith" && cost.gold <= spare && has?(p, cost.items),
          do: {"shop", %{"act" => "upgrade", "id" => uid, "confirm" => true}}

      [] ->
        nil
    end
  end

  # ---------- Sự kiện, thú cưng, tháp (DECISIONS "Bot chơi như người thật") ----------
  @play Data.rules().bots.play

  @doc """
  Sự kiện bot tham gia lúc rảnh: Quảng Trường Quỷ / Lâu Đài Máu đang mở, đủ cấp, chưa vào đợt này → có vé thì vào, không
  thì ghép vé từ mảnh ở Máy Hỗn Nguyên hoặc mua; Kalima: có Bản Đồ Thất Lạc thì vào, đủ 5 Dấu Ấn Kundun thì ghép bản đồ.
  Trả `{vai NPC, lệnh}`, `:heal` (sắp vào mà máu < `play.event_hp`: hồi máu trước, như người chơi) hoặc nil.
  """
  def event_job(p, d \\ nil) do
    d = d || Engine.derived(p)
    spare = spare_gold(p)

    job =
      sched_event(p, DevilSquare.view(p), "ds", "ds_ticket", spare) ||
        sched_event(p, BloodCastle.view(p), "bc", "bc_ticket", spare) ||
        kalima_job(p, spare)

    case job do
      {_, %{"act" => act}} = job ->
        if String.ends_with?(act, "_enter") and p.hp < d.maxHp * @play.event_hp,
          do: :heal,
          else: job

      nil ->
        nil
    end
  end

  defp sched_event(p, v, kind, recipe, spare) do
    r = Data.chaos(recipe)

    cond do
      not v.open or v.used or p.level < v.min_level -> nil
      v.tickets > 0 -> {"tower", %{"act" => kind <> "_enter"}}
      r.gold <= spare and has?(p, r.items) -> {"chaos", %{"act" => "chaos", "id" => recipe}}
      v.price <= spare -> {"tower", %{"act" => kind <> "_buy"}}
      true -> nil
    end
  end

  defp kalima_job(p, spare) do
    v = Kalima.view(p)
    r = Data.chaos("lost_map")

    cond do
      p.level < v.min_level -> nil
      v.maps > 0 -> {"tower", %{"act" => "kal_enter"}}
      r.gold <= spare and has?(p, r.items) -> {"chaos", %{"act" => "chaos", "id" => "lost_map"}}
      true -> nil
    end
  end

  @doc """
  Thú cưng như `HacLong.Game.Journey`: thú mạnh hơn hẳn (`Pets.power/3` > `play.pet_better` × thú mạnh nhất đang có)
  mà giá ≤ `play.pet_budget` vàng dư → mua ở cửa hàng / thuần phục; dắt con mạnh nhất; vàng dư > `play.feed_mult` × giá
  cho ăn và tới lượt (`opts.feed_due`: mỗi `play.feed_every_min` phút, tiến trình bot hẹn) → cho ăn. Trả `{vai NPC | nil, lệnh}` hoặc nil.
  """
  def pet_job(p, opts \\ %{}) do
    spare = spare_gold(p)
    owned = Map.get(p, :pets) || []
    best = Enum.max_by(owned, &Pets.power(p, &1), fn -> nil end)
    cur = Pets.power(p, best)
    budget = spare * @play.pet_budget

    shop =
      for pt <- Data.pets(),
          !pt[:rare],
          pt.id not in owned,
          pt.price <= budget,
          do: {"pet_buy", pt.id, pt.id}

    tame =
      for t <- Pets.tameable(p), t.price <= budget, do: {"pet_tame", t.id, "tame:" <> t.id}

    cand =
      (shop ++ tame)
      |> Enum.map(fn {act, id, pet} -> {act, id, Pets.power(p, pet, 1)} end)
      |> Enum.max_by(&elem(&1, 2), fn -> nil end)

    feed = Pets.feed_cost(p)

    cond do
      match?({_, _, pw} when pw > cur * @play.pet_better, cand) ->
        {act, id, _} = cand
        {"pets", %{"act" => act, "id" => id}}

      best && best != p[:pet] ->
        {nil, %{"act" => "pet_choose", "id" => best}}

      # cho ăn từ từ như người thật: tiến trình bot hẹn giờ (`feed_due`, `play.feed_every_min`)
      feed && spare > feed * @play.feed_mult && Map.get(opts, :feed_due, true) ->
        {"pets", %{"act" => "pet_feed"}}

      true ->
        nil
    end
  end

  @doc """
  Leo Tháp Vô Tận lúc rảnh: từ cấp `play.tower_level`, tới lượt (`opts.tower_due`: tiến trình bot đặt mỗi
  `play.tower_every_min` phút) thì vào từ tầng bắt đầu cao nhất đã mở; máu chưa đầy thì hồi trước (`:heal`).
  """
  def tower_job(p, d, opts \\ %{}) do
    cond do
      not (opts[:tower_due] == true and p.level >= @play.tower_level) ->
        nil

      p.hp < d.maxHp * @play.tower_enter_hp ->
        :heal

      true ->
        floor = p |> Map.get(:tower_best, 0) |> Tower.starts() |> List.last()
        {"tower", %{"act" => "tower_enter", "floor" => floor}}
    end
  end

  @doc """
  Đang ở bản đồ riêng `tower` (Tháp, Quảng Trường, Lâu Đài, Kalima): còn quái thì tới con gần nhất đánh; hết quái thì
  lên cầu thang (Tháp, Quảng Trường); Lâu Đài / Kalima xong thì bước một bước để về Làng. Ra cổng `<` khi máu
  < `play.leave_hp` và hết bình, hoặc (Tháp) vừa xong một chặng 10 tầng / máu < `play.tower_hp` sau một tầng.
  """
  def tower_play(p, d, opts \\ %{})
  def tower_play(%{tower: nil} = p, _d, _opts), do: any_step(p)

  def tower_play(%{tower: t} = p, d, opts) do
    me = {p.pos.x, p.pos.y}
    low = p.hp < d.maxHp * @play.leave_hp and Engine.best_potion(p, d.maxHp - p.hp) == nil
    done = (t[:bc] && t.bc.done) || (t[:kal] && t.kal.done)
    plain? = t[:ds] == nil and t[:bc] == nil and t[:kal] == nil

    # mọi con là đích: quái chắn đường thì con chắn đó cũng là đích, luôn có đường
    targets = t.monsters |> Enum.sort_by(&dist(me, {&1.x, &1.y})) |> Enum.map(&{&1.x, &1.y})

    cond do
      done ->
        any_step(p)

      low ->
        tower_walk(p, [List.to_tuple(t.exit)])

      # vừa lên qua hết một chặng 10 tầng (đang ở tầng 11, 21… mà không phải tầng vào lượt này): ra cổng. Tầng 10 xong
      # thì lên cầu thang trước: kỷ lục `tower_best` chỉ ghi khi lên cầu thang (trước đây ra cổng ngay ở tầng 10 nên kỷ
      # lục mãi là 9, lần sau lại vào từ tầng 1 — bot "kẹt tầng 9")
      plain? and rem(t.floor, 10) == 1 and t.floor > (opts[:tower_from] || t.floor) ->
        tower_walk(p, [List.to_tuple(t.exit)])

      targets != [] ->
        tower_walk(p, targets)

      plain? and p.hp < d.maxHp * @play.tower_hp ->
        tower_walk(p, [List.to_tuple(t.exit)])

      t[:ds] != nil or plain? ->
        tower_walk(p, [List.to_tuple(t.stairs)])

      # Lâu Đài / Kalima chưa xong mà hết quái (trùm sắp hiện): đi qua lại chậm chờ (trước đây đứng im không gửi lệnh
      # gì, mà server chỉ xét hết giờ / phòng đã đóng khi bước đi, nên bot kẹt mãi trong tháp, vd. sau khi khởi động lại)
      true ->
        idle_step(p)
    end
  end

  @doc false
  # bước sang ô trống "." kế bên (không bước vào cổng / cầu thang), đánh dấu `wait` để tiến trình bot hỏi lại chậm
  def idle_step(%{tower: t} = p) when is_map(t) do
    Enum.find_value(["up", "down", "left", "right"], fn dir ->
      {dx, dy} = @dirs[dir]

      if tower_tile(t, {p.pos.x + dx, p.pos.y + dy}) == ".",
        do: %{"act" => "move", "dir" => dir, "wait" => true}
    end) || Map.put(any_step(p), "wait", true)
  end

  def idle_step(p), do: Map.put(any_step(p), "wait", true)

  # bước một ô bất kỳ (Lâu Đài / Kalima xong, lượt đã hết: bước nào cũng về Làng)
  defp any_step(p) do
    Enum.find_value(["up", "down", "left", "right"], fn dir ->
      {dx, dy} = @dirs[dir]
      t = p[:tower]

      if t == nil or tower_tile(t, {p.pos.x + dx, p.pos.y + dy}) in [".", ">", "<"],
        do: %{"act" => "move", "dir" => dir}
    end) || %{"act" => "move", "dir" => "up"}
  end

  defp tower_tile(t, {x, y}), do: t.tiles |> Enum.at(y, "") |> String.at(x)

  # đường đi trên tầng (ô "." đi được; cầu thang, quái chỉ là đích)
  defp tower_walk(%{tower: t} = p, goals) do
    goals = MapSet.new(goals)
    blocked = t.monsters |> MapSet.new(&{&1.x, &1.y}) |> MapSet.difference(goals)
    free? = fn pos -> tower_tile(t, pos) == "." end

    case first_step(free?, {p.pos.x, p.pos.y}, goals, blocked) do
      # không có đường (quái chắn hết lối…): đi qua lại chờ, không đứng im
      nil -> idle_step(p)
      dir -> %{"act" => "move", "dir" => dir}
    end
  end

  # Vùng chuyển sinh (DECISIONS "Bot cuối game"): cấp tối đa mà cần hạ chúa tể thì đi các bản đồ của vùng đó; đã chuyển sinh
  # tối đa thì luyện ở vùng chuyển sinh (mọi vùng đã mở, khó dần) thay vì bản đồ thường. Đi lần lượt: hạ đủ `realm_kills`
  # quái ở bản đồ trước mới sang bản đồ sau; bản đồ đang tránh (`avoid`, vừa chết nhiều) thì dừng ở bản đồ trước nó
  # (bản đồ đầu tiên đã tránh: nil, luyện bản đồ thường).
  @doc false
  def realm_target(p, avoid \\ []) do
    cs = Map.get(p, :rebirths) || 0

    cond do
      p.level < @max_level ->
        nil

      # cần hạ chúa tể trước lần chuyển sinh tới: đi các bản đồ của vùng đó; vùng đó đang tránh (gục nhiều, quá mạnh so
      # với thang hiện tại) thì luyện ở vùng hợp sức
      need = need(p) ->
        realm_walk(p, realm_maps(p, &(&1 == need.realm)), avoid) || ladder_walk(p, avoid)

      # không chuyển sinh được lúc này (tới trần bot, hết lượt hôm nay) hoặc đã quá mốc 10: vùng hợp sức theo thang
      cs >= @bot_rebirths or cs >= @max_rebirths or Engine.rebirths_today(p) >= @per_day ->
        ladder_walk(p, avoid)

      true ->
        nil
    end
  end

  # vùng chuyển sinh hợp sức theo thang vùng co giãn (`ladder_realm/2`); vùng đó đang tránh thì lùi vùng thấp hơn
  defp ladder_walk(p, avoid) do
    top = ladder_realm(p)

    Enum.find_value(top..1//-1, fn r ->
      realm_walk(p, realm_maps(p, &(&1 == r)), avoid)
    end)
  end

  defp realm_maps(p, realm?) do
    Maps.ids()
    |> Enum.map(&Maps.get/1)
    |> Enum.filter(&(realm?.(&1.realm) and World.realm_open?(p, &1)))
    |> Enum.sort_by(&{&1.realm, &1.id})
  end

  defp realm_walk(p, maps, avoid) do
    Enum.reduce_while(maps, nil, fn m, prev ->
      kills = m.spawns |> Enum.map(&HacLong.Game.Bestiary.count(p, &1.monster)) |> Enum.sum()

      cond do
        m.id in avoid -> {:halt, prev}
        kills < @forge.realm_kills -> {:halt, m.id}
        true -> {:cont, m.id}
      end
    end)
  end

  # ---------- Chết nhiều ở một chỗ: tạm tránh ----------
  @avoid Data.rules().bots.play.avoid

  @doc """
  Ghi một lần gục ở bản đồ `map` (lúc `now`, ms) vào `%{fails: %{bản_đồ => [mốc]}, avoid: %{bản_đồ => tới_mốc}}`:
  gục `play.avoid.deaths` lần trong `window_min` phút ở cùng một chỗ (phòng trùm đánh không lại, bản đồ quá mạnh) thì
  tránh chỗ đó `hours` giờ (DECISIONS "Bot cuối game").
  """
  def note_death(st, map, now) do
    win = @avoid.window_min * 60_000
    recent = [now | Enum.filter(Map.get(st.fails, map, []), &(now - &1 < win))]

    if length(recent) >= @avoid.deaths,
      do: %{
        st
        | fails: Map.delete(st.fails, map),
          avoid: Map.put(st.avoid, map, now + round(@avoid.hours * 3_600_000))
      },
      else: %{st | fails: Map.put(st.fails, map, recent)}
  end

  @doc "Các bản đồ đang tránh lúc `now`."
  def avoiding(st, now), do: for({m, t} <- st.avoid, now < t, do: m)

  # ---------- Dọn túi ----------
  @sell Data.rules().bots.sell
  @gear_bag Data.rules().loot.gear_bag

  @doc """
  Túi trang bị gần đầy (≥ `bots.sell.full_at` món) thì về Làng bán đồ thừa ở Thợ Rèn; đang ở Làng thì bán tiếp tới khi
  còn `down_to` món. Đồ thừa: chưa khóa, chưa ép, không Excellent / May mắn / đồ Thần, không phải cánh, và mặc không được
  (lớp khác) hoặc không hơn món đang mặc ở ô đó. Chưa có cánh thì giữ một món làm cánh (`first_wing/4`).
  """
  def sell_job(p) do
    bag = Gear.bag(p)
    n = length(bag)
    village? = p.pos.map == "village"

    if n >= min(@sell.full_at, @gear_bag) or (village? and n > @sell.down_to) do
      keep = wing_material(p, bag)

      Enum.find_value(bag, fn g ->
        it = Gear.resolve(g)
        if g.uid != keep and junk?(p, it), do: {"shop", %{"act" => "sell", "id" => g.uid}}
      end)
    end
  end

  defp junk?(p, it) do
    plain =
      not it.locked and not it.stored and it.slot != "wing" and not it.excellent and not it.luck and
        not it.anc and Engine.upgrade_level(p, it.uid) == 0

    plain and
      (not Engine.can_wear?(p, it) or
         (it.slot in Engine.gear_slots() and
            power(it) <= power(Gear.item(p, p.equip[Engine.equip_slot(p, it)]))))
  end

  # món giữ lại để ghép cánh đầu tiên (như `first_wing/4`: món ép cao nhất trong các ô của công thức)
  defp wing_material(p, bag) do
    r = p.equip[:wing] == nil && wing_recipe(1)

    if r do
      bag
      |> Enum.filter(&(!&1[:locked] and Gear.resolve(&1).slot in r.gear.slots))
      |> Enum.max_by(&{Engine.upgrade_level(p, &1.uid), &1.uid}, fn -> nil end)
      |> then(&(&1 && &1.uid))
    end
  end

  # ---------- Trận đánh ----------

  @doc """
  Lệnh trong trận: máu < `hp` (tỉ lệ máu tối đa) và có bình → uống; chưa có kỹ năng dùng được và MP < `mp` → uống
  mana; kỹ năng mạnh nhất (cuối bộ kỹ năng) đang sẵn → dùng; còn lại đánh thường. Tự đánh (Phase 4) dùng chung.
  """
  def fight(p, hp \\ 0.35, mp_pct \\ 0.3, mode \\ nil) do
    d = Engine.derived(p)
    mp = Map.get(p, :mp) || 0

    ready = p |> fight_skills(mode) |> Enum.filter(&(Engine.cooldown(p, &1.id) == 0))
    skill = Enum.find(ready, &(mp >= Engine.skill_mp(p, &1)))

    # hết MP cho kỹ năng đã hồi chiêu (lớp ít MP với kỹ năng tháp tốn nhiều) thì cũng uống bình mana
    starved? = ready != [] and d.maxMp >= Enum.min(Enum.map(ready, &Engine.skill_mp(p, &1)))

    cond do
      # đánh người: bình còn được uống (giới hạn số bình / lượt chờ), không thì đánh tiếp thay vì đứng im
      p.hp < d.maxHp * hp and Engine.best_potion(p, d.maxHp - p.hp) != nil and
          Engine.potion_ready?(p) ->
        %{"act" => "potion"}

      skill == nil and (mp < d.maxMp * mp_pct or starved?) and Engine.best_mana(p, d.maxMp - mp) &&
          Engine.mana_ready?(p) ->
        %{"act" => "mana"}

      skill ->
        %{"act" => "skill", "skill" => skill.id}

      true ->
        %{"act" => "attack"}
    end
  end

  # bot (mode nil): kỹ năng mạnh nhất trước. Tự đánh: "all" kỹ năng buff trước rồi mạnh nhất, "basic" không dùng,
  # "boss" chỉ khi quái là trùm / tinh anh / quái vàng / quái Bóng Đêm
  defp fight_skills(p, nil), do: p |> Engine.skills() |> Enum.reverse()
  defp fight_skills(_p, "basic"), do: []

  defp fight_skills(p, "boss") do
    m = (p.battle || %{})[:monster] || %{}

    if m[:boss] || m[:elite] || m[:golden] || m[:rare] || m[:world],
      do: fight_skills(p, "all"),
      else: []
  end

  defp fight_skills(p, _all) do
    {buffs, rest} = p |> Engine.skills() |> Enum.reverse() |> Enum.split_with(&buff?/1)
    buffs ++ rest
  end

  @buff_effects ~w(war_cry guard shadow_step)
  defp buff?(k), do: k[:buff] != nil or k[:effect] in @buff_effects

  @doc """
  Bộ kỹ năng bot mang vào trận (tối đa `loadout`, chỉ kỹ năng tốn không quá MP tối đa): luôn giữ một kỹ năng hồi máu /
  hút máu mạnh nhất nếu có, còn lại là các kỹ năng hệ số cao nhất (kỹ năng lớp không có hệ số tính 1).
  Trả danh sách id xếp yếu → mạnh (`fight/1` dùng từ cuối lên).
  """
  def loadout(p, n) do
    # bỏ kỹ năng tốn hơn MP tối đa (không bao giờ dùng được)
    max_mp = Engine.derived(p).maxMp
    avail = Enum.filter(Engine.available_skills(p), &(Engine.skill_mp(p, &1) <= max_mp))
    sustain = avail |> Enum.filter(&sustain?/1) |> Enum.max_by(&skill_power/1, fn -> nil end)
    rest = avail |> Enum.reject(&(&1 == sustain)) |> Enum.sort_by(&skill_power/1, :desc)
    picked = if sustain, do: [sustain | Enum.take(rest, n - 1)], else: Enum.take(rest, n)
    picked |> Enum.sort_by(&skill_power/1) |> Enum.map(& &1.id)
  end

  defp sustain?(k), do: k[:effect] == "holy" or (k[:heal] || 0) > 0 or (k[:drain] || 0) > 0
  defp skill_power(k), do: k[:mult] || 1

  # ---------- Đồ đạc, hồi máu ----------

  # món trong túi đồ hiếm mạnh hơn món đang mặc cùng loại (vũ khí theo tấn công, giáp / khiên theo phòng thủ;
  # vũ khí 2 tay so với vũ khí + khiên đang cầm; lớp cầm 2 vũ khí: vũ khí 1 tay ở tay trái so với khiên / vũ khí
  # tay trái đang cầm). Trả lệnh `equip` hoặc nil.
  defp better_gear(p), do: better_wing(p) || better_armor(p)

  # cánh trong túi (ghép xong ở Máy Hỗn Nguyên, nhặt được) hơn cánh đang mặc: bậc cao hơn, cùng bậc thì ép cao hơn.
  # Trước đây chỉ xét `Engine.gear_slots/0` (không có cánh) nên bot ghép cánh xong để trong túi, rồi lại ghép tiếp.
  defp better_wing(p) do
    rank = fn uid -> {wing_tier(p, uid), Engine.upgrade_level(p, uid)} end
    worn = p.equip[:wing]

    p
    |> Gear.bag()
    |> Enum.filter(fn g ->
      it = Gear.resolve(g)
      it.slot == "wing" and Engine.can_wear?(p, it)
    end)
    |> Enum.max_by(&rank.(&1.uid), fn -> nil end)
    |> then(fn g -> if g && (worn == nil or rank.(g.uid) > rank.(worn)), do: equip(g) end)
  end

  defp better_armor(p) do
    weapon = Gear.item(p, p.equip.weapon)
    left = Gear.item(p, p.equip.shield)
    k = Engine.dual_rules().mult

    p
    |> Gear.bag()
    |> Enum.map(&Gear.resolve/1)
    |> Enum.filter(&(&1.slot in Engine.gear_slots() and Engine.can_wear?(p, &1)))
    |> Enum.find_value(fn it ->
      slot = Engine.equip_slot(p, it)
      cur = Gear.item(p, p.equip[slot])

      left_power =
        if left && left.slot == "weapon", do: worth(p, left) * k, else: worth(p, left)

      cond do
        # vũ khí 2 tay không cầm khiên (B-41)
        slot == :shield and Engine.two_handed?(weapon) ->
          nil

        # vũ khí 2 tay thay 1 tay: phải hơn cả vũ khí lẫn tay trái đang cầm
        slot == :weapon and Engine.two_handed?(it) ->
          if worth(p, it) > worth(p, cur) + left_power, do: equip(it)

        slot == :weapon and worth(p, it) > worth(p, cur) ->
          equip(it)

        # cầm 2 vũ khí (B-42): vũ khí 1 tay vào tay trái nếu hơn khiên / vũ khí tay trái
        slot == :weapon and Engine.dual_class?(p.cls) and weapon && not Engine.two_handed?(weapon) and
          Engine.dual_pair?(weapon, it) and worth(p, it) * k > left_power ->
          equip(it, "left")

        slot != :weapon and worth(p, it) > worth(p, cur) and
            not (slot == :shield and left != nil and left.slot == "weapon") ->
          equip(it)

        true ->
          nil
      end
    end)
  end

  defp equip(it, hand \\ nil),
    do:
      %{"act" => "equip", "id" => it.uid}
      |> then(&if(hand, do: Map.put(&1, "hand", hand), else: &1))

  @doc "Sức mạnh thô một món đồ (tấn công + phòng thủ + dòng cộng thêm), để so với món đang mặc."
  def power(nil), do: 0

  def power(it),
    do: (it[:atk] || 0) + (it[:def] || 0) + (it[:opt] || 0) * Engine.line_value(it)

  # sức mạnh kể cả cấp ép (DECISIONS "Bot dùng ngọc khôn hơn"): món +5 không bị thay bằng món +0 nhỉnh hơn chút,
  # trước đây mất trắng 5 Ngọc Ước Nguyện mỗi lần thay đồ
  defp worth(_p, nil), do: 0
  defp worth(p, it), do: power(it) + Engine.upgrade_bonus(p, it.uid)

  # hết bình: đủ vàng thì nghỉ trọ ở Làng, không thì uống giếng giữa Làng (miễn phí)
  defp heal(p, _d, snap) do
    if p.gold >= Engine.rest_cost(p) * @shop.inn_gold_mult and village_npc("inn"),
      do: at_village_npc(p, "inn", snap, fn -> %{"act" => "rest"} end),
      else: go_fountain(p, snap)
  end

  # ---------- Mua bình (Phase 5, B-32) ----------

  @doc """
  Bình cần mua: `[{id, số}]`. Còn ít hơn `RULES.bots.potion_min` bình máu thì mua tới `potion_buy` (bình mana tương
  tự, chỉ lớp có MP); chỉ tính khi mua được ít nhất mức tối thiểu với số vàng đang có.
  """
  def restock(p) do
    d = Engine.derived(p)

    kinds =
      [{@hp_ids, d.maxHp, @shop.potion_min, @shop.potion_buy}] ++
        if d.maxMp > 0, do: [{@mp_ids, d.maxMp, @shop.mana_min, @shop.mana_buy}], else: []

    {need, _gold} =
      Enum.reduce(kinds, {[], p.gold}, fn {ids, max, min, buy}, {acc, gold} ->
        have = Enum.sum(Enum.map(useful(p, ids, max), &Map.get(p.inv, &1, 0)))

        with true <- have < min,
             id when id != nil <- pick_potion(p, ids, max, gold, min),
             n = min(buy - have, div(gold, Engine.price(p, id))),
             true <- n >= min - have do
          {acc ++ [{id, n}], gold - n * Engine.price(p, id)}
        else
          _ -> {acc, gold}
        end
      end)

    need
  end

  # Bình hồi số cố định (DECISIONS "Bình máu / mana hồi số"): chỉ đếm loại còn hồi được ≥ `potion_heal_min` máu (MP)
  # tối đa (trong các loại mua được ở cấp này); bình nhỏ nhặt từ đầu game không đủ dùng cuối game. Không loại nào đủ
  # (đầu game): đếm hết.
  defp useful(p, ids, max) do
    ok? = fn id ->
      Engine.buy_level_ok?(p, Data.item(id)) and
        elem(Engine.potion_amount(p, id), 1) >= max * @shop.potion_heal_min
    end

    case Enum.filter(ids, ok?) do
      [] -> ids
      ok -> ok
    end
  end

  # rẻ nhất mà hồi được ≥ `potion_heal_min` máu (MP) tối đa; không có thì loại mạnh nhất mua được `min` bình
  defp pick_potion(p, ids, max, gold, min) do
    ok =
      Enum.filter(ids, fn id ->
        it = Data.item(id)

        (it[:level] || 0) <= p.level and Engine.buy_level_ok?(p, it) and
          gold >= Engine.price(p, id) * min
      end)

    Enum.find(ok, &(elem(Engine.potion_amount(p, &1), 1) >= max * @shop.potion_heal_min)) ||
      List.last(ok)
  end

  defp shop(p, [{id, n} | _], snap),
    do: at_village_npc(p, "herbalist", snap, fn -> %{"act" => "buy", "id" => id, "n" => n} end)

  defp village_npc(role), do: Enum.find(Maps.get("village").npcs, &(&1.role == role))

  # tới NPC `role` ở Làng; đứng cạnh rồi thì ra lệnh `then`
  defp at_village_npc(%{pos: %{map: "village", x: x, y: y}} = p, role, snap, then) do
    %{at: {nx, ny}} = village_npc(role)

    if abs(nx - x) + abs(ny - y) == 1,
      do: then.(),
      else: walk(p, Maps.get("village"), [{nx, ny}], snap)
  end

  defp at_village_npc(p, _role, _snap, _then), do: go_to(p, "village")

  # giếng ở Làng (ô "F"; Nhà đã bỏ, DECISIONS "Bỏ Nhà: Thủ Kho ở Làng")
  defp go_fountain(%{pos: %{map: "village"}} = p, snap) do
    map = Maps.get("village")

    fountain =
      for {row, y} <- Enum.with_index(rows(map)), {"F", x} <- Enum.with_index(row), do: {x, y}

    walk(p, map, fountain, snap)
  end

  defp go_fountain(p, _snap), do: go_to(p, "village")

  # ---------- Chọn nơi luyện, di chuyển ----------

  @doc """
  Bản đồ luyện cho `p`: có quái, cấp quái thấp nhất ≤ cấp mình, cao nhất ≤ cấp mình + 1; trong 3 bản đồ
  cấp cao nhất thì mỗi bot (`seed`) chọn một cái để các bot không dồn về một chỗ.
  """
  def target_map(p, seed \\ 0) do
    candidates =
      for id <- Maps.ids(),
          m = Maps.get(id),
          not m.private and id != "tower" and m.spawns != [] and m.secret == nil,
          reachable?(p, m),
          lo = World.min_level(m),
          lo != nil and lo <= p.level,
          hi = max_level(m),
          hi <= p.level + 1,
          do: {hi, lo, id}

    case Enum.sort(candidates, :desc) do
      [] -> "forest_1"
      best -> best |> Enum.at(rem(seed, min(3, length(best)))) |> elem(2)
    end
  end

  defp max_level(%{side: true} = m),
    do: m.spawns |> Enum.map(&Data.side_monster(&1.monster).level) |> Enum.max()

  defp max_level(m) do
    z = Data.zone(m.zone)
    kinds = Enum.map(m.spawns, & &1.monster)
    z.monsters |> Enum.filter(&(&1.id in kinds)) |> Enum.map(& &1.level) |> Enum.max(fn -> 99 end)
  end

  # tới được: bản đồ vùng đã mở, bản đồ phụ đã tới hoặc có đường cổng từ Làng qua các vùng đã mở
  defp reachable?(p, %{side: true, id: id}) do
    id in (Map.get(p, :visited) || []) or next_portal(p, "village", id) != nil
  end

  defp reachable?(p, %{zone: zi}) when is_integer(zi), do: Engine.zone_unlocked?(p, zi)
  defp reachable?(_p, _m), do: true

  defp roam(p, snap, opts) do
    {seed, avoid} = {opts[:seed] || 0, opts[:avoid] || []}
    here = p.pos.map
    realm = realm_target(p, avoid)
    inv = !realm && invasion_map(p, opts[:invasion])
    target = boss_room(p, avoid) || realm || inv || target_map(p, seed)

    cond do
      here != target ->
        go_to(p, target)

      # vùng chuyển sinh: quái cấp cao hơn cấp tối đa, đánh mọi con (chúa tể trước)
      realm ->
        lord = (need(p) || %{})[:id]
        hunt_first(p, snap, lord) || hunt(p, snap, fn _m, _map -> true end)

      # Golden Invasion: quái vàng trước
      inv == here ->
        hunt(p, snap, fn m, _map -> m[:gold] == true end, false) || hunt(p, snap)

      true ->
        hunt(p, snap)
    end
  end

  defp hunt_first(_p, nil, _kind), do: nil

  defp hunt_first(p, snap, kind) do
    t = Enum.filter(snap.monsters, &(&1.kind == kind and not &1.busy))
    if t != [], do: walk(p, Maps.get(p.pos.map), Enum.map(t, &{&1.x, &1.y}), snap)
  end

  # tới bản đồ `target`: dịch chuyển nếu được và đủ vàng (giữ lại ít nhất gấp đôi giá), không thì đi bộ qua cổng
  defp go_to(p, target) do
    map = Maps.get(target)
    cost = World.travel_cost(map)

    if World.can_travel?(p, map) and p.gold >= cost * 2,
      do: %{"act" => "travel", "to" => target},
      else: walk_route(p, target)
  end

  defp walk_route(p, target) do
    here = Maps.get(p.pos.map)

    case next_portal(p, here.id, target) do
      nil -> if(here.id != "village", do: %{"act" => "travel", "to" => "village"})
      portal -> walk(p, here, [portal.at], nil)
    end
  end

  @doc "Cổng đầu tiên trên đường ngắn nhất (theo số lần qua cổng) từ bản đồ `from` tới `to`, hoặc nil."
  def next_portal(p, from, to) do
    bfs_maps(p, [{from, nil}], MapSet.new([from]), to)
  end

  defp bfs_maps(_p, [], _seen, _to), do: nil

  defp bfs_maps(p, [{id, first} | rest], seen, to) do
    if id == to do
      first
    else
      next =
        for pt <- Maps.get(id).portals,
            not MapSet.member?(seen, pt.to),
            m = Maps.get(pt.to),
            not m.private and m.secret == nil,
            open?(p, m),
            do: {pt.to, first || pt}

      seen = Enum.reduce(next, seen, fn {mid, _}, s -> MapSet.put(s, mid) end)
      bfs_maps(p, rest ++ next, seen, to)
    end
  end

  defp open?(p, %{zone: zi}) when is_integer(zi), do: Engine.zone_unlocked?(p, zi)
  defp open?(_p, _m), do: true

  @doc "Phòng trùm nên vào: trùm của vùng cuối đã mở chưa hạ và cấp mình ≥ cấp trùm + 1 (nil nếu không)."
  def boss_room(p, avoid \\ []) do
    zones = Data.zones()

    zones
    |> Enum.with_index()
    |> Enum.find(fn {z, i} -> Engine.zone_unlocked?(p, i) and z.boss.id not in p.bosses end)
    |> case do
      {z, _} when p.level >= z.boss.level + 1 ->
        room = z.id <> "_boss"
        if Maps.get(room) && room not in avoid, do: room

      _ ->
        nil
    end
  end

  @doc """
  Đi tới con quái gần nhất không ai đánh (trùm thường của bản đồ có quái hồi sinh thì bỏ qua) thỏa `keep`
  (`fn quái, bản_đồ -> bool`, mặc định cấp không quá cấp mình + 1); không có con nào thì đi lang thang.
  """
  def hunt(p, snap, keep \\ nil, wander? \\ true)
  def hunt(p, nil, _keep, wander?), do: if(wander?, do: wander(p))

  def hunt(p, snap, keep, wander?) do
    me = {p.pos.x, p.pos.y}
    map = Maps.get(p.pos.map)
    keep = keep || fn m, map -> monster_level(map, m.kind) <= p.level + 1 end

    targets =
      snap.monsters
      |> Enum.reject(&(&1.busy or (&1.boss and map.spawns != [])))
      |> Enum.filter(&keep.(&1, map))
      |> Enum.sort_by(&dist(me, {&1.x, &1.y}))
      |> Enum.map(&{&1.x, &1.y})

    case targets do
      [] -> if(wander?, do: wander(p))
      _ -> walk(p, map, Enum.take(targets, 3), snap) || if(wander?, do: wander(p))
    end
  end

  @doc "Cấp loại quái `kind` trên bản đồ `map` (99 nếu không biết)."
  def monster_level(%{side: true}, kind), do: (Data.side_monster(kind) || %{level: 99}).level

  def monster_level(%{zone: zi}, kind) when is_integer(zi) do
    z = Data.zone(zi)
    Enum.find_value(z.monsters ++ [z.boss], 99, &(&1.id == kind && &1.level))
  end

  def monster_level(_, _), do: 99

  defp wander(p) do
    map = Maps.get(p.pos.map)
    {x, y} = {p.pos.x, p.pos.y}

    @dirs
    |> Enum.shuffle()
    |> Enum.find_value(fn {dir, {dx, dy}} ->
      if Maps.walkable?(map, x + dx, y + dy) and Maps.portal_at(map, x + dx, y + dy) == nil,
        do: %{"act" => "move", "dir" => dir}
    end)
  end

  # ---------- Tìm đường trên ô ----------

  @doc """
  Bước đi đầu tiên (`%{"act" => "move", "dir" => ...}`) tới ô gần nhất trong `goals`, hoặc nil. Ô đi được theo
  `Maps.walkable?/3`; cổng, giếng, quái chỉ được bước vào nếu là đích.
  """
  def walk(p, map, goals, snap) do
    goals = MapSet.new(goals)
    start = {p.pos.x, p.pos.y}
    blocked = monsters_at(snap) |> MapSet.difference(goals)

    case first_step(&plain?(map, &1), start, goals, blocked) do
      nil -> nil
      # gặp trùm vào trận luôn (như client, Phase 11)
      dir -> %{"act" => "move", "dir" => dir, "confirm" => true}
    end
  end

  defp monsters_at(nil), do: MapSet.new()
  defp monsters_at(snap), do: MapSet.new(snap.monsters, &{&1.x, &1.y})

  # `free?`: ô đi qua được (đích luôn bước vào được)
  defp first_step(free?, start, goals, blocked) do
    queue = :queue.from_list([{start, nil}])
    search(free?, queue, MapSet.new([start]), goals, blocked)
  end

  defp search(free?, queue, seen, goals, blocked) do
    case :queue.out(queue) do
      {:empty, _} ->
        nil

      {{:value, {pos, first}}, queue} ->
        if MapSet.member?(goals, pos) and first != nil do
          first
        else
          {queue, seen} =
            Enum.reduce(@dirs, {queue, seen}, fn {dir, {dx, dy}}, {q, s} ->
              {x, y} = pos
              nxt = {x + dx, y + dy}
              goal? = MapSet.member?(goals, nxt)

              if MapSet.member?(s, nxt) or MapSet.member?(blocked, nxt) or
                   not (goal? or free?.(nxt)) do
                {q, s}
              else
                {:queue.in({nxt, first || dir}, q), MapSet.put(s, nxt)}
              end
            end)

          search(free?, queue, seen, goals, blocked)
        end
    end
  end

  defp plain?(map, {x, y}),
    do: Maps.walkable?(map, x, y) and Maps.portal_at(map, x, y) == nil

  defp rows(map),
    do:
      Enum.map(0..(map.height - 1), fn y ->
        Enum.map(0..(map.width - 1), &Maps.tile(map, &1, y))
      end)

  defp dist({a, b}, {c, d}), do: abs(a - c) + abs(b - d)
end

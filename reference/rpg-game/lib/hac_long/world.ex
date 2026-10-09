defmodule HacLong.World do
  @moduledoc """
  Di chuyển trên bản đồ, gọi từ `HacLong.Game.Session` (tiến trình của người chơi).

  Vị trí nằm trong trạng thái nhân vật: `player.pos = %{map: id, x: x, y: y}`.
  Nhà là bản đồ riêng nên chỉ cần kiểm tra địa hình; các bản đồ khác dùng chung,
  đi qua `HacLong.World.MapServer` để biết ô nào có quái và ai đang ở đâu.

  Session luôn gọi MapServer, không bao giờ ngược lại, nên không thể bị treo chờ nhau.
  """

  alias HacLong.Game.{Daily, Data, Engine, Home, Tower}
  alias HacLong.{Party, WorldBoss}
  alias HacLong.World.{Maps, MapServer}

  @dirs %{"up" => {0, -1}, "down" => {0, 1}, "left" => {-1, 0}, "right" => {1, 0}}

  def dirs, do: Map.keys(@dirs)

  @doc """
  Vị trí hợp lệ khi vào game: bản đồ còn tồn tại, ô đi được và không bị bít kín bốn phía. Nếu
  không (bản đồ đã sửa) thì về điểm vào của chính bản đồ đó (`Maps.entry/1`), không có thì về Nhà.
  """
  def valid_pos(%{map: id, x: x, y: y} = pos) do
    case Maps.get(id) do
      nil ->
        Maps.home_spawn()

      map ->
        free? = fn {dx, dy} -> Maps.walkable?(map, x + dx, y + dy) end

        if Maps.walkable?(map, x, y) and Enum.any?(Map.values(@dirs), free?),
          do: pos,
          else: Maps.entry(id) || Maps.home_spawn()
    end
  end

  def valid_pos(_), do: Maps.home_spawn()

  defp shared?(%{map: id}), do: not Maps.get(id).private

  @doc "Những gì người khác thấy về mình trên bản đồ: tên, lớp, cấp, ngoại hình, ký hiệu bang."
  def info(p) do
    %{
      name: p.name,
      cls: p.cls,
      level: p.level,
      look: Engine.look(p),
      tag: Map.get(p, :guild) && p.guild.tag
    }
  end

  @doc "Cập nhật thông tin người khác thấy (vd. vừa đổi đồ, lên cấp, dắt thú khác)."
  def refresh(%{pos: pos} = p, uid) do
    if shared?(pos), do: MapServer.update(pos.map, uid, info(p))
    :ok
  end

  def refresh(_p, _uid), do: :ok

  @doc "Có mặt trên bản đồ hiện tại (khi người chơi mở game)."
  def enter(%{pos: pos} = p, uid) do
    if shared?(pos), do: MapServer.enter(pos.map, uid, info(p), {pos.x, pos.y})
    :ok
  end

  def enter(_p, _uid), do: :ok

  @doc "Rời bản đồ hiện tại (đóng game, xóa nhân vật)."
  def leave(%{pos: pos}, uid) do
    if shared?(pos), do: MapServer.leave(pos.map, uid)
    :ok
  end

  def leave(_p, _uid), do: :ok

  @doc "NPC đứng ngay cạnh nhân vật có một trong các `roles` (hoặc nil)."
  def near_npc(%{pos: %{map: id, x: x, y: y}}, roles) do
    Enum.find(Maps.get(id).npcs, fn %{at: {nx, ny}} = n ->
      n.role in roles and abs(nx - x) + abs(ny - y) == 1
    end)
  end

  def near_npc(_p, _roles), do: nil

  @doc """
  Đi một bước theo hướng `dir`. Trả về `{kết_quả, nhân_vật}` như các lệnh khác.

  Bước vào trùm thì lần đầu chỉ nhận `%{confirm: "boss", boss: ...}`; gửi lại với
  `confirm: true` mới vào trận. Bước vào đá dịch chuyển thì ghi nhớ đá đó và nhận
  `%{waystone: true}` để client mở bảng chọn nơi đến. Bước vào NPC thì nhận `%{npc: id}`
  để mở hội thoại. Bước vào điểm thu thập thì nhận nguyên liệu.
  """
  def move(p, uid, dir, confirm? \\ false) do
    with {:ok, {dx, dy}} <- Map.fetch(@dirs, dir),
         nil <- p.battle,
         false <- p.pos.map == Tower.map_id() && tower_move(p, uid, {dx, dy}) do
      %{map: map_id, x: x, y: y} = p.pos
      map = Maps.get(map_id)
      {tx, ty} = {x + dx, y + dy}

      cond do
        portal = Maps.portal_at(map, tx, ty) -> use_portal(p, uid, portal)
        npc = Maps.npc_at(map, tx, ty) -> {%{ok: true, npc: npc.id}, p}
        Maps.tile(map, tx, ty) == "F" -> drink_fountain(p)
        Maps.tile(map, tx, ty) == "W" -> touch_waystone(p, map)
        map.world_boss == {tx, ty} and WorldBoss.hp() != nil -> world_boss(p, uid, confirm?)
        not Maps.walkable?(map, tx, ty) -> {%{ok: false}, p}
        map.private and Home.at(p, tx, ty) != nil -> {%{ok: false}, p}
        map.private -> {%{ok: true}, put_pos(p, map_id, tx, ty)}
        true -> step_shared(p, uid, map, {tx, ty}, confirm?)
      end
    else
      :error -> {%{ok: false, msg: "Hướng đi không hợp lệ."}, p}
      {%{}, %{}} = tower_result -> tower_result
      _battle -> {%{ok: false, msg: "Đang trong trận đấu."}, p}
    end
  end

  # ---------- Tháp Vô Tận ----------
  # Tầng tháp là bản đồ riêng của từng người, nằm ngay trong trạng thái nhân vật (`p.tower`).

  # chỗ đứng trong Làng khi ra khỏi tháp (cạnh Người Gác Tháp)
  @tower_door %{map: "village", x: 21, y: 9}

  defp tower_move(%{tower: nil} = p, uid, _d),
    do: leave_tower(p, uid, "Lượt leo tháp đã kết thúc.")

  defp tower_move(%{tower: t, pos: %{x: x, y: y}} = p, uid, {dx, dy}) do
    {tx, ty} = {x + dx, y + dy}
    tile = t.tiles |> Enum.at(ty, "") |> String.at(tx)

    cond do
      m = Enum.find(t.monsters, &(&1.x == tx and &1.y == ty)) ->
        case Engine.start_with_monster(
               p,
               min(div(t.floor - 1, 10), Data.zone_count() - 1),
               Tower.battle_monster(m)
             ) do
          {%{ok: true} = r, p} -> {r, put_in(p.battle[:encounter], %{tower: m.id})}
          other -> other
        end

      tile == ">" ->
        Tower.climb(p)

      tile == "<" ->
        leave_tower(p, uid, "Rời Tháp Vô Tận. Kỷ lục: tầng #{Map.get(p, :tower_best, 0)}.")

      tile == "." ->
        {%{ok: true}, %{p | pos: %{p.pos | x: tx, y: ty}}}

      true ->
        {%{ok: false}, p}
    end
  end

  defp leave_tower(p, uid, msg) do
    p = %{p | pos: @tower_door} |> Map.put(:tower, nil)
    enter(p, uid)
    {%{ok: true, msg: msg}, p}
  end

  # Chạm trùm thế giới: hỏi xác nhận như trùm thường, rồi vào trận với thanh máu chung.
  defp world_boss(p, _uid, confirm?) when confirm? != true do
    {%{
       ok: false,
       confirm: "boss",
       boss: %{id: "ancient_dragon", name: WorldBoss.name(), level: 34, world: true}
     }, p}
  end

  defp world_boss(p, uid, _confirm) do
    case WorldBoss.engage(uid) do
      {:ok, m} ->
        {r, p} = Engine.start_with_monster(p, 5, m)
        if r.ok, do: {r, put_in(p.battle[:encounter], %{world_boss: true})}, else: {r, p}

      {:error, msg} ->
        {%{ok: false, msg: msg}, p}
    end
  end

  def world_battle?(%{battle: %{encounter: %{world_boss: true}}}), do: true
  def world_battle?(_), do: false

  defp put_pos(p, map, x, y), do: %{p | pos: %{map: map, x: x, y: y}}

  # giếng ở Nhà hồi đầy máu và MP
  defp drink_fountain(p) do
    d = Engine.derived(p)

    if p.hp >= d.maxHp and (p[:mp] || 0) >= d.maxMp,
      do: {%{ok: false, msg: "Nước giếng mát lạnh. Máu và MP đang đầy."}, p},
      else:
        {%{ok: true, msg: "Uống nước giếng, máu và MP đã đầy."},
         Map.merge(p, %{hp: d.maxHp, mp: d.maxMp})}
  end

  defp use_portal(p, uid, portal) do
    target = Maps.get(portal.to)

    if target.zone && not Engine.zone_unlocked?(p, target.zone) do
      prev = Data.zone(target.zone - 1)
      {%{ok: false, msg: "Hạ #{prev.boss.name} để mở #{Data.zone(target.zone).name}."}, p}
    else
      leave(p, uid)
      {x, y} = portal.spawn
      p = p |> put_pos(target.id, x, y) |> visit(target)
      enter(p, uid)
      {%{ok: true, msg: "Đến #{target.name}."}, p}
    end
  end

  # bản đồ phụ đã tới thì dịch chuyển tới được bằng bảng chọn bản đồ
  defp visit(p, %{side: true, id: id}) do
    known = Map.get(p, :visited) || []
    if id in known, do: p, else: Map.put(p, :visited, known ++ [id])
  end

  defp visit(p, _), do: p

  # ---------- Chọn bản đồ (Phase 15a, U2) ----------

  @travel Data.rules().travel

  @doc "Cấp quái thấp nhất của bản đồ (nil nếu không có quái): dùng để xếp và tính giá."
  def min_level(%{side: true} = map),
    do: map.spawns |> Enum.map(&Data.side_monster(&1.monster).level) |> Enum.min(fn -> nil end)

  def min_level(%{zone: zi} = map) when is_integer(zi) do
    z = Data.zone(zi)
    kinds = Enum.map(map.spawns, & &1.monster)

    lv =
      for(mo <- z.monsters, mo.id in kinds, do: mo.level) ++
        if(map.boss, do: [z.boss.level], else: [])

    Enum.min(lv, fn -> nil end)
  end

  def min_level(_), do: nil

  @doc "Giá dịch chuyển tới bản đồ: `base + per_level × cấp quái thấp nhất`; Làng, Nhà miễn phí."
  def travel_cost(map) do
    case map.id in @travel.free or min_level(map) do
      true -> 0
      nil -> @travel.base
      lv -> @travel.base + @travel.per_level * lv
    end
  end

  @doc "Bản đồ tới được bằng bảng chọn: vùng đã mở (bản đồ thường), đã đi tới (bản đồ phụ), Làng, Nhà."
  def can_travel?(p, map) do
    cond do
      map.id in @travel.free -> true
      map.side -> map.id in (Map.get(p, :visited) || [])
      map.private or map.id == "tower" -> false
      is_integer(map.zone) -> Engine.zone_unlocked?(p, map.zone)
      true -> true
    end
  end

  @doc "Dịch chuyển bằng bảng chọn bản đồ (tốn vàng)."
  def travel(p, uid, to) do
    target = is_binary(to) && Maps.get(to)

    cond do
      p.battle ->
        {%{ok: false, msg: "Đang trong trận đấu."}, p}

      !target or target.id == "tower" ->
        {%{ok: false, msg: "Không có bản đồ đó."}, p}

      to == p.pos.map ->
        {%{ok: false, msg: "Bạn đang ở đây rồi."}, p}

      not can_travel?(p, target) ->
        {%{ok: false, msg: "Chưa mở bản đồ này (đi qua cổng một lần trước)."}, p}

      p.gold < travel_cost(target) ->
        {%{ok: false, msg: "Cần #{travel_cost(target)} vàng."}, p}

      true ->
        cost = travel_cost(target)
        leave(p, uid)
        %{x: x, y: y} = if target.id == "home", do: Maps.home_spawn(), else: Maps.entry(target.id)
        p = %{put_pos(p, target.id, x, y) | gold: p.gold - cost}
        enter(p, uid)

        {%{ok: true, msg: "Đến #{target.name}#{if cost > 0, do: " (−#{cost} vàng)", else: ""}."},
         p}
    end
  end

  defp step_shared(p, uid, map, {tx, ty} = to, confirm?) do
    case MapServer.step(map.id, uid, to, confirm? == true) do
      :ok ->
        {%{ok: true}, put_pos(p, map.id, tx, ty)}

      {:gather, node} ->
        item = Data.item(node.item)
        verb = if String.starts_with?(node.item, "ore"), do: "Đào", else: "Hái"
        p = p |> Engine.add_item(node.item) |> Daily.on_gather(node.item)
        {%{ok: true, msg: "#{verb} được #{item.name}.", gather: node.item}, p}

      {:confirm_boss, m} ->
        boss = Data.zone(map.zone).boss

        {%{ok: false, confirm: "boss", boss: %{id: m.kind, name: boss.name, level: boss.level}},
         p}

      {:busy, m} ->
        join_shared(p, uid, map, m)

      {:engage, m} ->
        case encounter(p, map, m) do
          {%{ok: true} = r, p} ->
            # trong tổ đội: ghi trận để đồng đội vào đánh cùng
            key = fight_key(map.id, m.id)
            Party.open_fight(key, uid, p.battle.monster)
            {r, put_in(p.battle[:encounter], %{map: map.id, mid: m.id, shared: key})}

          {r, p} ->
            MapServer.release(map.id, uid, m.id)
            {r, p}
        end
    end
  end

  # bản đồ phụ (Phase 15a) không thuộc vùng: không cần mở vùng, nền theo `theme`
  defp encounter(p, %{side: true} = map, m),
    do: Engine.start_side_encounter(p, spec_of(map, m), map.name, map.theme)

  defp encounter(p, map, m), do: Engine.start_encounter(p, map.zone, spec_of(map, m), m.boss)

  defp spec_of(map, m) do
    spec =
      cond do
        map.side -> Data.side_monster(m.kind)
        m.boss -> Data.zone(map.zone).boss
        true -> Enum.find(Data.zone(map.zone).monsters, &(&1.id == m.kind))
      end

    cond do
      m[:gold] -> golden_variant(spec, m.boss)
      m[:rare] -> night_variant(spec)
      true -> spec
    end
  end

  # Quái vàng Golden Invasion (`RULES.invasion`, Phase 7): mạnh hơn (`strength_mult`, trùm vàng giữ sức
  # như trùm vùng), thưởng × `reward_mult`, rơi ngọc theo `jewel_chance` / `boss_jewel_chance`.
  @inv Data.rules().invasion
  defp golden_variant(spec, boss?) do
    Map.merge(spec, %{
      name: "#{spec.name} Vàng",
      mult: Map.get(spec, :mult, 1) * if(boss?, do: 1, else: @inv.strength_mult),
      reward_mult: @inv.reward_mult,
      golden: true,
      jewel_chance: if(boss?, do: @inv.boss_jewel_chance, else: @inv.jewel_chance)
    })
  end

  def fight_key(map_id, mid), do: "#{map_id}:#{mid}"

  # Con quái đang đánh với đồng đội cùng tổ: vào đánh chung (máu chung ở HacLong.Party).
  defp join_shared(p, uid, map, m) do
    key = fight_key(map.id, m.id)

    with {:ok, f} <- Party.join_fight(key, uid),
         {%{ok: true} = r, p} <- encounter(p, map, m) do
      p = put_in(p.battle.monster.hp, f.hp)
      p = put_in(p.battle[:encounter], %{map: map.id, mid: m.id, shared: key, joined: true})
      {Map.put(r, :msg, "Vào đánh cùng đồng đội (#{f.n} người)."), p}
    else
      {:error, msg} -> {%{ok: false, msg: msg}, p}
      {r, p} -> {r, p}
    end
  end

  # Quái Bóng Đêm (chỉ xuất hiện ban đêm): mạnh gấp rưỡi nên kinh nghiệm, vàng cũng gấp rưỡi;
  # dễ rơi đồ ngẫu nhiên hơn (`Gear.drop_chance/1`).
  defp night_variant(spec) do
    Map.merge(spec, %{
      name: "#{spec.name} Bóng Đêm",
      mult: Map.get(spec, :mult, 1) * 1.5,
      night: true
    })
  end

  # ---------- Đá dịch chuyển ----------

  defp touch_waystone(p, map) do
    known = Map.get(p, :waystones, [])

    if map.id in known or map.id == "village" do
      {%{ok: true, waystone: true}, p}
    else
      {%{ok: true, waystone: true, msg: "Đã ghi nhớ đá dịch chuyển ở #{map.name}."},
       Map.put(p, :waystones, known ++ [map.id])}
    end
  end

  @doc "Những nơi có thể dịch chuyển tới: Làng và các đá đã ghi nhớ."
  def waystones(p), do: ["village" | Map.get(p, :waystones, [])]

  defp next_to_waystone?(%{pos: %{map: id, x: x, y: y}}) do
    case Maps.get(id).waystone do
      %{at: {wx, wy}} -> abs(wx - x) + abs(wy - y) == 1
      nil -> false
    end
  end

  @doc "Dịch chuyển từ đá đang đứng cạnh tới đá ở bản đồ `to`."
  def teleport(p, uid, to) do
    target = is_binary(to) && Maps.get(to)

    cond do
      p.battle ->
        {%{ok: false, msg: "Đang trong trận đấu."}, p}

      not next_to_waystone?(p) ->
        {%{ok: false, msg: "Hãy đứng cạnh đá dịch chuyển."}, p}

      !target or target.waystone == nil ->
        {%{ok: false, msg: "Không có đá dịch chuyển ở đó."}, p}

      to not in waystones(p) ->
        {%{ok: false, msg: "Bạn chưa tới đá dịch chuyển đó."}, p}

      to == p.pos.map ->
        {%{ok: false, msg: "Bạn đang ở đây rồi."}, p}

      target.zone && not Engine.zone_unlocked?(p, target.zone) ->
        {%{ok: false, msg: "Vùng chưa mở."}, p}

      true ->
        leave(p, uid)
        {x, y} = target.waystone.spawn
        p = put_pos(p, target.id, x, y)
        enter(p, uid)
        {%{ok: true, msg: "Dịch chuyển tới #{target.name}."}, p}
    end
  end

  @doc """
  Gọi khi trận vừa kết thúc: thắng thì quái biến mất khỏi bản đồ, thua hoặc chạy thì
  nhả quái ra. Gục ngã thì được đưa về Nhà.
  """
  def finish_encounter(%{battle: %{over: true} = b} = p, uid) do
    case b[:encounter] do
      # vào đánh cùng đồng đội: con quái do người khác giữ
      %{joined: true, shared: key} ->
        if b.result != "win", do: Party.leave_fight(key, uid)

      %{map: map_id, mid: mid} = enc ->
        cond do
          b.result == "win" ->
            MapServer.defeat(map_id, uid, mid)

          # mình thua hoặc bỏ chạy nhưng đồng đội còn đánh: chuyển quái cho người khác
          enc[:shared] ->
            case Party.leave_fight(enc.shared, uid) do
              {:owner, next} -> MapServer.reassign(map_id, uid, mid, next)
              :ok -> MapServer.release(map_id, uid, mid)
            end

          true ->
            MapServer.release(map_id, uid, mid)
        end

      _ ->
        :ok
    end

    if b.result == "lose" do
      leave(p, uid)
      %{p | pos: Maps.home_spawn()}
    else
      p
    end
  end

  def finish_encounter(p, _uid), do: p
end

defmodule HacLong.World do
  @moduledoc """
  Di chuyển trên bản đồ, gọi từ `HacLong.Game.Session` (tiến trình của người chơi).

  Vị trí nằm trong trạng thái nhân vật: `player.pos = %{map: id, x: x, y: y}`.
  Nhà là bản đồ riêng nên chỉ cần kiểm tra địa hình; các bản đồ khác dùng chung,
  đi qua `HacLong.World.MapServer` để biết ô nào có quái và ai đang ở đâu.

  Session luôn gọi MapServer, không bao giờ ngược lại, nên không thể bị treo chờ nhau.
  """

  alias HacLong.Game.{BloodCastle, Daily, Data, DevilSquare, Engine, Kalima, Tower}
  alias HacLong.EventRoom
  alias HacLong.{Party, WorldBoss}
  alias HacLong.World.{Maps, MapServer}

  @dirs %{"up" => {0, -1}, "down" => {0, 1}, "left" => {-1, 0}, "right" => {1, 0}}

  def dirs, do: Map.keys(@dirs)

  @doc """
  Vị trí hợp lệ khi vào game: bản đồ còn tồn tại, ô đi được và không bị bít kín bốn phía. Nếu
  không (bản đồ đã sửa) thì về điểm vào của chính bản đồ đó (`Maps.entry/1`), không có thì về Làng.
  """
  def valid_pos(%{map: id, x: x, y: y} = pos) do
    case Maps.get(id) do
      nil ->
        Maps.home_spawn()

      # bản đồ sự kiện (B-19): sự kiện đã xong hoặc mất kết nối giữa chừng thì về Làng
      %{event: e} when is_binary(e) ->
        village_spawn()

      map ->
        free? = fn {dx, dy} -> Maps.walkable?(map, x + dx, y + dy) end

        if Maps.walkable?(map, x, y) and Enum.any?(Map.values(@dirs), free?),
          do: pos,
          else: Maps.entry(id) || Maps.home_spawn()
    end
  end

  def valid_pos(_), do: Maps.home_spawn()

  @doc "Chỗ đứng ở Làng khi bị đưa về (bị loại khỏi sự kiện, sự kiện kết thúc)."
  def village_spawn do
    {x, y} = Maps.get("village").waystone.spawn
    %{map: "village", x: x, y: y}
  end

  @doc """
  Đưa nhân vật tới `pos` (bản đồ sự kiện, về Làng…): rời bản đồ cũ, có mặt ở bản đồ mới. Không kiểm tra điều kiện.
  """
  def warp(p, uid, %{map: _, x: _, y: _} = pos) do
    leave(p, uid)

    # ra khỏi bản đồ riêng `tower` (Tháp / sự kiện) thì bỏ luôn trạng thái tháp, không kẹt lại
    p = %{p | pos: pos} |> drop_stale_tower()
    enter(p, uid)
    p
  end

  @doc "Bản đồ chung (nhiều người cùng thấy nhau), không phải bản đồ riêng như tháp."
  def shared?(%{map: id}), do: not Maps.get(id).private

  @doc "Những gì người khác thấy về mình trên bản đồ: tên, lớp, cấp, số lần chuyển sinh, ngoại hình, ký hiệu bang."
  def info(p) do
    %{
      name: p.name,
      cls: p.cls,
      level: p.level,
      rebirths: Map.get(p, :rebirths) || 0,
      look: Engine.look(p),
      tag: Map.get(p, :guild) && p.guild.tag,
      # đang đồ sát (người cùng bản đồ thấy ⚔ và máu trên đầu): đối thủ, % máu của mình
      duel: duel(p)
    }
  end

  @doc """
  Trạng thái đồ sát vừa đổi (vào / xong trận) thì cập nhật thông tin người khác thấy, không thì ⚔ "đang đồ sát" kẹt lại
  sau khi trận đã xong (người khác không bấm Đồ sát được).
  """
  def sync_duel(old, new, uid) do
    if is_map(new) and Map.has_key?(new, :pos) and
         (is_map(old) and duel(old) != nil) != (duel(new) != nil),
       do: refresh(new, uid),
       else: :ok
  end

  defp duel(%{battle: %{over: false, encounter: %{slay: _, foe: foe}}} = p),
    do: %{with: foe, hp: round(max(p.hp, 0) * 100 / max(Engine.derived(p).maxHp, 1))}

  defp duel(_p), do: nil

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
    # rời Hỗn Chiến Thành (gục, đổi bản đồ, thoát game) là bị loại
    if Maps.get(pos.map)[:event] == "chaos_castle", do: HacLong.ChaosCastle.out(uid)
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
  `confirm: true` mới vào trận. Bước vào Đài Phúc Lành (ô `W`) thì nhận phúc lành của bản đồ và
  ghi điểm hồi sinh (`%{blessing: true}`). Bước vào NPC thì nhận `%{npc: id}`
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

  # Phòng sự kiện đánh chung (Quảng Trường / Lâu Đài / Kalima, HacLong.EventRoom): bản đồ, quái, máu quái là của phòng
  defp tower_move(%{tower: %{room: id} = t, pos: %{x: x, y: y}} = p, uid, {dx, dy}) do
    {tx, ty} = {x + dx, y + dy}
    tile = t.tiles |> Enum.at(ty, "") |> String.at(tx)
    kind = EventRoom.kind(t)
    done? = kind != :ds and t[kind].done

    cond do
      done? ->
        EventRoom.leave(id, uid)
        p |> room_out(kind) |> ds_back(uid)

      # hết giờ, hoặc phòng không còn (server khởi động lại, đã kết thúc lúc mình offline): kết thúc lượt
      room_expired?(p, kind) or not EventRoom.alive?(id) ->
        EventRoom.leave(id, uid)
        p |> room_out(kind, "hết giờ") |> ds_back(uid)

      m = Enum.find(t.monsters, &(&1.x == tx and &1.y == ty)) ->
        room_engage(p, uid, id, kind, m)

      tile == ">" and kind == :ds ->
        case EventRoom.climb(id, uid) do
          {:error, msg} ->
            {%{ok: false, msg: msg}, p}

          {:ok, t2} ->
            [ex, ey] = t2.exit

            {%{ok: true, msg: "Đợt #{t2.floor}/#{t2.ds.waves}!"},
             %{p | tower: EventRoom.merge(t, t2), pos: %{p.pos | x: ex, y: ey - 1}}}

          {:cleared, info} ->
            p |> EventRoom.settle(info) |> ds_back(uid)
        end

      tile == "<" ->
        EventRoom.leave(id, uid)
        p |> room_out(kind, "tự rời") |> ds_back(uid)

      tile in [".", ">"] ->
        EventRoom.moved(id, uid, tx, ty)
        {%{ok: true}, %{p | pos: %{p.pos | x: tx, y: ty}}}

      true ->
        {%{ok: false}, p}
    end
  end

  # Quảng Trường Quỷ (Phase 18 M1): cùng bản đồ riêng `tower`, trạng thái `p.tower.ds`
  defp tower_move(%{tower: %{ds: %{}} = t, pos: %{x: x, y: y}} = p, uid, {dx, dy}) do
    {tx, ty} = {x + dx, y + dy}
    tile = t.tiles |> Enum.at(ty, "") |> String.at(tx)

    cond do
      DevilSquare.expired?(p) ->
        p |> DevilSquare.finish("hết giờ") |> ds_back(uid)

      m = Enum.find(t.monsters, &(&1.x == tx and &1.y == ty)) ->
        case Engine.start_with_monster(p, Data.zone_count() - 1, DevilSquare.battle_monster(m)) do
          {%{ok: true} = r, p} ->
            {r,
             p
             |> Engine.scale_event(event_k(p))
             |> Tower.resume_hp(m)
             |> put_in([:battle, :encounter], %{tower: m.id})}

          other ->
            other
        end

      tile == ">" ->
        p |> DevilSquare.climb() |> ds_back(uid)

      tile == "<" ->
        p |> DevilSquare.finish("tự rời") |> ds_back(uid)

      tile == "." ->
        {%{ok: true}, %{p | pos: %{p.pos | x: tx, y: ty}}}

      true ->
        {%{ok: false}, p}
    end
  end

  # Lâu Đài Máu (Phase 18 M2): cùng bản đồ riêng `tower`, trạng thái `p.tower.bc`
  # (phải đứng trước mệnh đề Tháp Vô Tận chung bên dưới, vốn khớp mọi `p.tower`)
  defp tower_move(%{tower: %{bc: bc} = t, pos: %{x: x, y: y}} = p, uid, {dx, dy}) do
    {tx, ty} = {x + dx, y + dy}
    tile = t.tiles |> Enum.at(ty, "") |> String.at(tx)

    cond do
      bc.done or BloodCastle.expired?(p) ->
        p |> BloodCastle.leave() |> ds_back(uid)

      m = Enum.find(t.monsters, &(&1.x == tx and &1.y == ty)) ->
        case Engine.start_with_monster(p, Data.zone_count() - 1, BloodCastle.battle_monster(m)) do
          {%{ok: true} = r, p} ->
            {r,
             p
             |> Engine.scale_event(event_k(p))
             |> Tower.resume_hp(m)
             |> put_in([:battle, :encounter], %{tower: m.id})}

          other ->
            other
        end

      tile == "<" ->
        p |> BloodCastle.leave() |> ds_back(uid)

      tile in [".", ">"] ->
        {%{ok: true}, %{p | pos: %{p.pos | x: tx, y: ty}}}

      true ->
        {%{ok: false}, p}
    end
  end

  # Kalima (B-21): cùng bản đồ riêng `tower`, trạng thái `p.tower.kal`
  defp tower_move(%{tower: %{kal: kal} = t, pos: %{x: x, y: y}} = p, uid, {dx, dy}) do
    {tx, ty} = {x + dx, y + dy}
    tile = t.tiles |> Enum.at(ty, "") |> String.at(tx)

    cond do
      kal.done or Kalima.expired?(p) ->
        p |> Kalima.leave() |> ds_back(uid)

      m = Enum.find(t.monsters, &(&1.x == tx and &1.y == ty)) ->
        case Engine.start_with_monster(p, Data.zone_count() - 1, Kalima.battle_monster(m)) do
          {%{ok: true} = r, p} ->
            {r,
             p
             |> Engine.scale_event(event_k(p))
             |> Tower.resume_hp(m)
             |> put_in([:battle, :encounter], %{tower: m.id})}

          other ->
            other
        end

      tile == "<" ->
        p |> Kalima.leave() |> ds_back(uid)

      tile in [".", ">"] ->
        {%{ok: true}, %{p | pos: %{p.pos | x: tx, y: ty}}}

      true ->
        {%{ok: false}, p}
    end
  end

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
          {%{ok: true} = r, p} ->
            {r, p |> Tower.resume_hp(m) |> put_in([:battle, :encounter], %{tower: m.id})}

          other ->
            other
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

  defp room_expired?(p, :ds), do: DevilSquare.expired?(p)
  defp room_expired?(p, :bc), do: BloodCastle.expired?(p)
  defp room_expired?(p, :kal), do: Kalima.expired?(p)

  # rời phòng: kết thúc lượt của mình như lượt riêng (thưởng theo điểm / số quái mình hạ)
  defp room_out(p, kind, why \\ nil)
  defp room_out(p, :ds, why), do: DevilSquare.finish(p, why || "tự rời")
  defp room_out(p, :bc, _why), do: BloodCastle.leave(p)
  defp room_out(p, :kal, _why), do: Kalima.leave(p)

  defp room_engage(p, uid, id, kind, m) do
    q =
      case kind do
        :ds -> DevilSquare.battle_monster(m)
        :bc -> BloodCastle.battle_monster(m)
        :kal -> Kalima.battle_monster(m)
      end

    case Engine.start_with_monster(p, Data.zone_count() - 1, q) do
      {%{ok: true} = r, p2} ->
        # trùm phòng: nhân vật quá mạnh gặp bản Thức Tỉnh; máu chung cộng phần của người đó (EventRoom)
        p2 = p2 |> Engine.scale_event(p.tower.k) |> room_awaken(kind, m)
        mon = p2.battle.monster
        base = mon[:base_max] || mon.maxHp

        case EventRoom.engage(id, uid, m.id, base, mon[:awaken_extra] || 0) do
          {:ok, hp, n, max} ->
            # room_key / room_n: màn trận nhận máu chung, số người đang đánh (sự kiện "shared" như tổ đội)
            enc = %{
              tower: m.id,
              room: id,
              room_key: EventRoom.key(id, m.id),
              room_n: n,
              base_xp: mon.xp,
              base_gold: mon.gold
            }

            {r,
             p2
             |> put_in([:battle, :monster, :hp], hp)
             |> put_in([:battle, :monster, :maxHp], max)
             |> put_in([:battle, :encounter], enc)}

          {:error, msg} ->
            {%{ok: false, msg: msg}, p}
        end

      other ->
        other
    end
  end

  # lượt Quảng Trường vừa kết thúc (đã về Làng): vào lại bản đồ Làng chung
  defp ds_back({r, %{tower: nil} = p}, uid) do
    enter(p, uid)
    {r, p}
  end

  defp ds_back(res, _uid), do: res

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

  defp put_pos(p, map, x, y), do: drop_stale_tower(%{p | pos: %{map: map, x: x, y: y}})

  @doc """
  Trạng thái tháp (`p.tower`) chỉ có nghĩa khi đang đứng ở bản đồ riêng `tower`; ở bản đồ khác (dữ liệu kẹt từ trước,
  bị đưa ra bằng đường khác) thì bỏ, để vào lại Tháp / Kalima / Lâu Đài Máu / Quảng Trường Quỷ được.
  """
  def drop_stale_tower(%{pos: %{map: map}} = p) do
    if Map.get(p, :tower) && map != Tower.map_id(), do: Map.put(p, :tower, nil), else: p
  end

  def drop_stale_tower(p), do: p

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

    cond do
      target.zone && not Engine.zone_unlocked?(p, target.zone) ->
        {%{
           ok: false,
           msg:
             "Cần đạt cấp #{Engine.zone_level(target.zone)} để vào #{Data.zone(target.zone).name}."
         }, p}

      target.realm && not realm_open?(p, target) ->
        {%{ok: false, msg: realm_msg(target)}, p}

      (wait = blood_lock(uid, target)) > 0 ->
        {%{ok: false, msg: blood_msg(wait)}, p}

      # bản đồ bí mật (Động Bí Ẩn, DECISIONS "Động Bí Ẩn"): cửa chỉ mở những đêm động mở; đóng thì chỉ là vách đá
      target.secret == "night" and not HacLong.World.Secret.open?() ->
        {%{ok: false, msg: "Chỉ là vách đá lạnh ngắt."}, p}

      # bản đồ không có quái nhưng cần cấp (Biển Long Vương); Động Bí Ẩn cần cấp 38
      !target.realm and is_integer(target.min_level) and p.level < target.min_level ->
        {%{
           ok: false,
           msg:
             if(target.secret,
               do: "Khe đá tỏa hơi lạnh buốt. Cần đạt cấp #{target.min_level} mới dám bước vào.",
               else: "Cần đạt cấp #{target.min_level} để vào #{target.name}."
             )
         }, p}

      true ->
        leave(p, uid)
        {x, y} = portal.spawn
        p = p |> put_pos(target.id, x, y) |> visit(target)
        p = if target.secret, do: HacLong.World.Secret.visit(p), else: p
        enter(p, uid)
        if target.secret, do: HacLong.World.Secret.found(target, p, uid)
        {%{ok: true, msg: "Đến #{target.name}."}, p}
    end
  end

  # Pháp Trường (DECISIONS "Pháp Trường Huyết Nguyệt"): vừa gục trong Huyết Nguyệt thì chờ `relock_s` giây mới vào lại
  defp blood_lock(uid, %{id: id}),
    do: if(id == HacLong.BloodMoon.map_id(), do: HacLong.BloodMoon.locked_s(uid), else: 0)

  defp blood_msg(wait), do: "Bạn vừa gục ở Pháp Trường, nghỉ #{wait} giây nữa mới vào lại được."

  @doc "Phase 6 (B-30): vào được vùng đất chuyển sinh `map` không (đủ số lần chuyển sinh và cấp)."
  def realm_open?(p, map),
    do: (Map.get(p, :rebirths) || 0) >= map.min_rebirths and p.level >= map.min_level

  defp realm_msg(map),
    do: "#{map.name} cần chuyển sinh #{map.min_rebirths} lần và cấp #{map.min_level} trở lên."

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

  # bản đồ không có quái nhưng ghi `min_level` (Biển Long Vương)
  def min_level(%{realm: nil, min_level: lv}) when is_integer(lv), do: lv
  def min_level(_), do: nil

  @doc "Giá dịch chuyển tới bản đồ: `base + per_level × cấp quái thấp nhất`; Làng, Nhà miễn phí."
  def travel_cost(map) do
    case map.id in @travel.free or min_level(map) do
      true -> 0
      nil -> @travel.base
      lv -> @travel.base + @travel.per_level * lv
    end
  end

  @doc """
  Bản đồ tới được bằng bảng chọn: Làng, Nhà, và mọi bản đồ chung khi **cấp nhân vật ≥ cấp quái thấp
  nhất** của bản đồ (`min_level/1`; không có quái thì tới được). Không cần mở vùng hay đi qua cổng trước
  (theo yêu cầu 2026-10-10). Vàng kiểm ở `travel/3`.
  """
  def can_travel?(p, map) do
    cond do
      map.id in @travel.free -> true
      map.private or map.id == "tower" or map.secret != nil -> false
      map.realm -> realm_open?(p, map)
      true -> p.level >= (min_level(map) || 0)
    end
  end

  @doc "Dịch chuyển bằng bảng chọn bản đồ (tốn vàng)."
  def travel(p, uid, to) do
    target = is_binary(to) && Maps.get(to)

    cond do
      p.battle ->
        {%{ok: false, msg: "Đang trong trận đấu."}, p}

      !target or target.id == "tower" or target.event != nil ->
        {%{ok: false, msg: "Không có bản đồ đó."}, p}

      # đang trong Tháp / Quảng Trường Quỷ / Lâu Đài Máu / Kalima: phải ra bằng cổng (để kết thúc lượt, nhận thưởng)
      p.pos.map == Tower.map_id() ->
        {%{ok: false, msg: "Đang ở trong Tháp / sự kiện: ra bằng cổng trước."}, p}

      to == p.pos.map ->
        {%{ok: false, msg: "Bạn đang ở đây rồi."}, p}

      not can_travel?(p, target) ->
        msg =
          if target.realm,
            do: realm_msg(target),
            else: "Cần đạt cấp #{min_level(target)} mới tới được bản đồ này."

        {%{ok: false, msg: msg}, p}

      (wait = blood_lock(uid, target)) > 0 ->
        {%{ok: false, msg: blood_msg(wait)}, p}

      p.gold < travel_cost(target) ->
        {%{ok: false, msg: "Cần #{travel_cost(target)} vàng."}, p}

      true ->
        cost = travel_cost(target)
        leave(p, uid)
        %{x: x, y: y} = Maps.entry(target.id)
        p = %{put_pos(p, target.id, x, y) | gold: p.gold - cost}
        enter(p, uid)

        {%{
           ok: true,
           msg:
             if(cost > 0,
               do: "Đến #{target.name} (−#{cost} vàng).",
               else: "Đến #{target.name}."
             )
         }, p}
    end
  end

  @doc """
  Đánh quái ở ô `(x, y)` từ xa, không di chuyển (DECISIONS "Tầm đánh theo cánh"): chỉ bản đồ chung, trong tầm `Gear.reach/1`
  (không cánh: sát bên; cánh cấp 1 / 2 / 3 = 3 / 5 / 8 ô).
  """
  def engage(p, uid, x, y, confirm? \\ false) do
    map = Maps.get(p.pos.map)
    reach = HacLong.Game.Gear.reach(p)

    cond do
      p.battle != nil ->
        {%{ok: false, msg: "Đang trong trận đấu."}, p}

      not (is_integer(x) and is_integer(y)) ->
        {%{ok: false}, p}

      max(abs(p.pos.x - x), abs(p.pos.y - y)) > reach ->
        {%{ok: false, msg: "Xa quá, lại gần trong #{reach} ô để đánh.", reach: reach}, p}

      # Tháp / phòng sự kiện (Quảng Trường Quỷ, Lâu Đài Máu, Kalima): quái ở `p.tower.monsters`; đánh từ xa bằng
      # đường bước-vào-ô-quái của tầng (đứng tạm cạnh quái), rồi trả người về chỗ cũ
      p.pos.map == Tower.map_id() ->
        t = p[:tower]

        if t && Enum.any?(t.monsters || [], &(&1.x == x and &1.y == y)) do
          {r, p2} = tower_move(%{p | pos: %{p.pos | x: x - 1, y: y}}, uid, {1, 0})
          {r, if(p2.pos.map == Tower.map_id(), do: %{p2 | pos: p.pos}, else: p2)}
        else
          {%{ok: false, msg: "Không còn quái ở đó."}, p}
        end

      map == nil or map.private ->
        {%{ok: false}, p}

      true ->
        step_shared(p, uid, map, {x, y}, confirm?, &MapServer.engage/4)
    end
  end

  defp step_shared(p, uid, map, {tx, ty} = to, confirm?, call \\ &MapServer.step/4) do
    case call.(map.id, uid, to, confirm? == true) do
      :none ->
        {%{ok: false, msg: "Không còn quái ở đó."}, p}

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
            # quái đang dở máu (người trước bỏ chạy): đánh tiếp từ máu đó
            p =
              if is_number(m[:hp]) and m.hp < 100,
                do:
                  update_in(p.battle.monster, &%{&1 | hp: max(1, round(&1.maxHp * m.hp / 100))}),
                else: p

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

  # Quảng Trường Quỷ / Lâu Đài Máu / Kalima: quái mạnh theo mốc của phòng / tổ (`p.tower.k`, đặt lúc vào)
  defp event_k(%{tower: %{k: k}}), do: k

  defp event_k(p),
    do: HacLong.Game.EventRooms.k(HacLong.Game.EventRooms.band(Map.get(p, :rebirths)))

  # quái trên bản đồ sự kiện mạnh theo mốc chuyển sinh của PHÒNG (Hỗn Chiến Thành) hoặc cố định (Vương Miện Công Thành
  # Chiến), không theo người đánh (DECISIONS "Sự kiện đánh chung theo phòng"); quái vàng mạnh theo vùng như quái thường
  @crown_k Data.rules().event_scale.crown_rebirths
  defp encounter(p, map, m) do
    boss? = (m.boss == true or m[:night_boss] == true) and !map.realm

    p
    |> do_encounter(map, m)
    |> scale_encounter(map, boss?)
    |> awaken(m)
    |> starter_guard(map, m)
  end

  # trùm đêm Động Bí Ẩn: nhân vật quá mạnh gặp bản Thức Tỉnh (DECISIONS "Trùm Thức Tỉnh theo sức người đánh")
  defp awaken({%{ok: true} = r, p}, %{night_boss: true}),
    do: {r, HacLong.Game.Awaken.maybe(p, "secret")}

  defp awaken(res, _m), do: res

  defp scale_encounter(res, map, boss?) do
    case res do
      {%{ok: true} = r, p} ->
        case map[:event] do
          "castle_siege" ->
            {r, Engine.scale_event(p, @crown_k)}

          "chaos_castle" ->
            {r, Engine.scale_event(p, HacLong.ChaosCastle.room_k(map.id))}

          # DECISIONS "Trùm mạnh theo chuyển sinh": trùm vùng, trùm đêm Động Bí Ẩn (Thạch Long Ẩn) mạnh lên theo số lần
          # chuyển sinh của người đánh như quái sự kiện (máu / thủ / công / thưởng); vùng chuyển sinh đã có chúa tể riêng
          _ when boss? ->
            {r, Engine.scale_event(p, Map.get(p, :rebirths) || 0)}

          _ ->
            {r, p}
        end

      other ->
        other
    end
  end

  # DECISIONS "Review sự kiện theo chuyển sinh": ở bản đồ không phải vùng chuyển sinh, trùm vàng Golden Invasion và đầu
  # đàn xâm lăng chỉ rơi ngọc / đồ thêm cho người chuyển sinh dưới `RULES.starter_events.jewel_max_rebirths` lần
  @starter Data.rules().starter_events
  defp starter_guard({%{ok: true} = r, p}, map, m) do
    if map.realm == nil and m.boss == true and (m[:gold] == true or is_binary(m[:raid])) and
         (Map.get(p, :rebirths) || 0) >= @starter.jewel_max_rebirths do
      p = update_in(p.battle.monster, &Map.merge(&1, %{jewel_chance: 0, no_drops: true}))

      line =
        "💎 #{p.battle.monster.name} giữ ngọc cho người mới (dưới chuyển sinh #{@starter.jewel_max_rebirths}): bạn hạ được vẫn nhận vàng, kinh nghiệm."

      {r, put_in(p.battle.log, p.battle.log ++ [%{text: line, kind: "info"}])}
    else
      {r, p}
    end
  end

  defp starter_guard(other, _map, _m), do: other

  # bản đồ phụ (Phase 15a) không thuộc vùng: không cần mở vùng, nền theo `theme`
  defp do_encounter(p, %{side: true} = map, m),
    do:
      Engine.start_side_encounter(
        p,
        spec_of(map, m, Map.get(p, :rebirths) || 0),
        map.name,
        map.theme,
        m[:night_boss] == true
      )

  # bản đồ sự kiện (B-19, Hỗn Chiến Thành): quái bất kỳ (vùng / bản đồ phụ) thả vào, đánh như bản đồ phụ;
  # B-22: bang đang giữ Vương Miện không đánh được nó
  defp do_encounter(p, %{event: e} = map, m) when is_binary(e) do
    case e == "castle_siege" && HacLong.CastleSiege.crown_blocked(p, m) do
      msg when is_binary(msg) -> {%{ok: false, msg: msg}, p}
      _ -> Engine.start_side_encounter(p, spec_of(map, m), map.name, map.theme)
    end
  end

  defp do_encounter(p, map, m), do: Engine.start_encounter(p, map.zone, spec_of(map, m), m.boss)

  defp spec_of(map, m, cs \\ nil) do
    spec =
      cond do
        m[:raid] != nil and map.realm != nil ->
          HacLong.RealmLadder.adjust(HacLong.Raids.spec(m.raid, m.kind, map), map.realm, cs)

        m[:raid] ->
          HacLong.Raids.spec(m.raid, m.kind, map)

        map.event == "castle_siege" ->
          HacLong.CastleSiege.crown_spec()

        # vùng chuyển sinh: dời mức theo thang co giãn của server (DECISIONS "Thang vùng co giãn theo server")
        map.side and map.realm != nil ->
          HacLong.RealmLadder.adjust(Data.side_monster(m.kind), map.realm, cs)

        map.side ->
          Data.side_monster(m.kind)

        map.event ->
          Data.side_monster(m.kind) || Data.monster(m.kind)

        m.boss ->
          Data.zone(map.zone).boss

        true ->
          Enum.find(Data.zone(map.zone).monsters, &(&1.id == m.kind))
      end

    cond do
      m[:gold] -> golden_variant(spec, m.boss)
      m[:elite] -> elite_variant(spec)
      m[:rare] -> night_variant(spec)
      true -> spec
    end
  end

  # Quái Tinh Anh ở Động Bí Ẩn (`RULES.secret`): mạnh hơn, thưởng nhiều hơn, dễ rơi ngọc hơn
  defp elite_variant(spec) do
    r = HacLong.World.Secret.rules()
    j = Data.jewels()

    Map.merge(spec, %{
      name: "#{spec.name} Tinh Anh",
      mult: Map.get(spec, :mult, 1) * r.elite_mult,
      reward_mult: Map.get(spec, :reward_mult, 1) * r.elite_reward,
      jewel_chance:
        (spec[:jewel_chance] || if(spec.level >= j.monster_level, do: j.monster_chance, else: 0)) *
          r.elite_jewel_mult,
      elite: true
    })
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

  # trùm của phòng (Quảng Trường Quỷ: quái `elite`; Lâu Đài Máu / Kalima: vai `boss`), quái thường không thức tỉnh
  defp room_awaken(p, :ds, %{elite: true}), do: HacLong.Game.Awaken.maybe(p, "ds")

  defp room_awaken(p, kind, %{role: "boss"}) when kind in [:bc, :kal],
    do: HacLong.Game.Awaken.maybe(p, Atom.to_string(kind))

  defp room_awaken(p, _kind, _m), do: p

  def fight_key(map_id, mid), do: "#{map_id}:#{mid}"

  # Con quái đang đánh với đồng đội cùng tổ: vào đánh chung (máu chung ở HacLong.Party).
  defp join_shared(p, uid, map, m) do
    key = fight_key(map.id, m.id)

    # dựng trận trước (biết mình có gặp bản Thức Tỉnh không) rồi mới vào trận chung: máu chung cộng phần của người mạnh
    with {%{ok: true} = r, p2} <- encounter(p, map, m),
         {:ok, f} <- Party.join_fight(key, uid, p2.battle.monster[:awaken_extra] || 0) do
      p2 =
        p2 |> put_in([:battle, :monster, :hp], f.hp) |> put_in([:battle, :monster, :maxHp], f.max)

      p2 = put_in(p2.battle[:encounter], %{map: map.id, mid: m.id, shared: key, joined: true})
      {Map.put(r, :msg, "Vào đánh cùng đồng đội (#{f.n} người)."), p2}
    else
      {:error, msg} -> {%{ok: false, msg: msg}, p}
      {r, _p2} -> {r, p}
    end
  end

  # Quái Bóng Đêm (chỉ xuất hiện ban đêm): mạnh gấp rưỡi nên kinh nghiệm, vàng cũng gấp rưỡi;
  # dễ rơi đồ ngẫu nhiên hơn (`Gear.drop_chance/1`).
  defp night_variant(spec) do
    Map.merge(spec, %{
      name: "#{spec.name} Bóng Đêm",
      mult: Map.get(spec, :mult, 1) * Data.rules().world.night_rare_mult,
      night: true
    })
  end

  # ---------- Đài Phúc Lành (thay đá dịch chuyển, Phase 2 B-26) ----------

  # chạm đài: phúc lành của bản đồ + điểm hồi sinh; vẫn ghi đài đã ghé (thành tựu ghé đủ đài)
  defp touch_waystone(p, map) do
    known = Map.get(p, :waystones, [])

    p =
      if map.id in known or map.id == "village",
        do: p,
        else: Map.put(p, :waystones, known ++ [map.id])

    # Đài Phúc Lành đã bỏ (DECISIONS "Bỏ Rương Gia Truyền, Đài Phúc Lành"): ô W là Đá Dịch Chuyển, chạm thì ghi nhận
    {%{ok: true, msg: "🗿 Đá Dịch Chuyển ở #{map.name} đã ghi nhận bạn."}, p}
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
            if HacLong.ChaosCastle.map?(map_id), do: HacLong.ChaosCastle.kill(uid, :monster)

            if map_id == HacLong.CastleSiege.map_id(),
              do: HacLong.CastleSiege.defeated(uid, mid, p[:guild])

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

    # đấu trực tiếp thua không phải gục ngã (không chết, đã về chỗ cũ): giữ nguyên chỗ đứng và có mặt trên bản đồ
    duel? = match?(%{duel: true}, b[:encounter])

    if b.result == "lose" and not duel? do
      leave(p, uid)
      # gục trong bản đồ sự kiện (Hỗn Chiến Thành): bị loại, về Làng
      # gục ở bản đồ thường: hồi sinh cạnh Đài Phúc Lành đã chạm, chưa chạm đài nào thì về Làng
      cond do
        Maps.get(p.pos.map)[:event] -> %{p | pos: village_spawn()}
        pos = HacLong.Game.Blessing.respawn(p) -> %{p | pos: pos}
        true -> %{p | pos: Maps.home_spawn()}
      end
    else
      p
    end
  end

  def finish_encounter(p, _uid), do: p
end

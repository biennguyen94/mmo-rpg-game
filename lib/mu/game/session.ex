defmodule Mu.Game.Session do
  @moduledoc """
  Một tiến trình / tài khoản đang online (`KB_TECH_STACK §4`), giữ trạng thái nhân vật.
  Mọi lệnh của tài khoản đi qua đúng tiến trình này nên được xử lý tuần tự.

  Khung lấy từ `HacLong.Game.Session` (Registry + DynamicSupervisor, `call` thử lại khi
  tiến trình vừa tự tắt, theo dõi tab bằng monitor, `trap_exit` + ghi nốt khi tắt).

  Sở hữu dữ liệu (PHASE1_PLAN R5):
  - Session giữ tiến độ (level, EXP, stat, điểm tự do, Zen) và là nơi **duy nhất** ghi DB.
  - `Mu.World.MapServer` giữ vị trí, HP/MP, cooldown khi đang online; gửi về
    `{:map_reward, ...}` (hạ quái) và `{:map_died, _}`.

  Ghi DB (`Characters.save/2`, optimistic lock `version`):
  - ngay khi lên cấp, nhận Zen (G12), cộng điểm, rời map;
  - còn lại (EXP, vị trí, HP/MP) mỗi `session.saveIntervalSeconds` nếu có đổi.

  Tab: `session.singleLoginPerAccount` — tab mới vào thì tab cũ nhận `{:session_kicked, _}`;
  nhân vật vẫn ở trên map. Tab cuối đóng: rời map ngay, hoặc ở lại
  `session.logoutInCombatSeconds` nếu đang combat (G21). Session đẩy `{:push, "player", view}`
  cho các tab khi tiến độ đổi.
  """
  use GenServer, restart: :transient
  require Logger

  alias Mu.Game.{Characters, Config, Engine}
  alias Mu.World.MapServer

  # không còn tab nào trong khoảng này thì tự tắt
  @idle_timeout :timer.minutes(1)

  @doc """
  Tab `pid` vào game với nhân vật `character_id`.
  `{:ok, character, map_info}` (`map_info`: `MapServer.join/3`) hoặc `{:error, :not_found}`.
  """
  def attach(account_id, character_id, pid), do: call(account_id, {:attach, character_id, pid})

  @doc "Nhân vật đang được giữ (`nil` nếu chưa có tab nào vào)."
  def get(account_id), do: call(account_id, :get)

  @doc "Lệnh `act` đã qua kiểm tra phong bì/rate-limit: `:ok` hoặc `{:error, code}`."
  def command(account_id, act, payload), do: call(account_id, {:command, act, payload})

  @doc "Pid của Session nếu đang chạy."
  def whereis(account_id) do
    case Registry.lookup(Mu.Game.Registry, account_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp call(account_id, msg, retry \\ true) do
    pid =
      case DynamicSupervisor.start_child(Mu.Game.SessionSupervisor, {__MODULE__, account_id}) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    GenServer.call(pid, msg)
  catch
    # tiến trình vừa tự tắt vì rảnh đúng lúc gọi: khởi động lại và thử một lần nữa
    :exit, {reason, _} when retry and reason in [:noproc, :normal] ->
      call(account_id, msg, false)
  end

  def start_link(account_id) do
    GenServer.start_link(__MODULE__, account_id,
      name: {:via, Registry, {Mu.Game.Registry, account_id}}
    )
  end

  @impl true
  def init(account_id) do
    Process.flag(:trap_exit, true)

    s = %{
      account_id: account_id,
      # `character`: trạng thái hiện tại; `saved`: bản đã ghi DB (để biết cột nào đổi)
      character: nil,
      saved: nil,
      tabs: %{},
      on_map: false,
      save_timer: nil,
      leave_timer: nil
    }

    {:ok, s, @idle_timeout}
  end

  @impl true
  def handle_call({:attach, character_id, pid}, _from, s) do
    case load(s, character_id) do
      nil ->
        reply({:error, :not_found}, s)

      character ->
        s = cancel_leave(s)

        # nhân vật khác với nhân vật đang trên map (Phase 1 không xảy ra: 1 nhân vật/tài khoản)
        s = if s.character && s.character.id != character.id, do: leave_map(s), else: s
        s = if s.saved && s.saved.id == character.id, do: s, else: %{s | saved: character}
        s = kick_tabs(%{s | character: character}, pid)
        s = %{s | tabs: Map.put(s.tabs, Process.monitor(pid), pid)}

        {:ok, info} = MapServer.join(character.map_id, map_player(character), self())

        c = %{
          s.character
          | position_x: info.x,
            position_y: info.y,
            hp_current: info.hp,
            mana_current: info.mp
        }

        s = %{s | character: c, on_map: true} |> schedule_save()
        reply({:ok, c, info}, s)
    end
  end

  def handle_call(:get, _from, s), do: reply(s.character && refresh(s).character, s)

  def handle_call({:command, act, payload}, _from, %{on_map: true} = s) do
    {result, s} = run(act, payload, s)
    reply(result, s)
  end

  def handle_call({:command, _act, _payload}, _from, s), do: reply({:error, "FORBIDDEN"}, s)

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, s) do
    s = %{s | tabs: Map.delete(s.tabs, ref)}
    s = if map_size(s.tabs) == 0, do: last_tab_closed(s), else: s
    {:noreply, s, timeout(s)}
  end

  def handle_info({:map_reward, %{exp: exp, zen: zen}}, %{character: c} = s) when c != nil do
    s = refresh(s)
    {c, levels} = Engine.add_exp(s.character, exp)
    s = %{s | character: %{c | zen: c.zen + zen}}

    s =
      if levels > 0 do
        # lên cấp: hồi đầy HP/MP (G10), báo MapServer chỉ số mới
        d = Engine.derived(s.character)
        c = %{s.character | hp_current: d.hp_max, mana_current: d.mp_max}
        sync_map(%{s | character: c}, %{hp: d.hp_max, mp: d.mp_max})
      else
        s
      end

    # Zen và lên cấp ghi ngay (G12, KB_TECH_STACK §4); EXP thường đi cùng lần ghi này
    s = if zen > 0 or levels > 0, do: persist(s), else: s
    push_player(s)
    {:noreply, s, timeout(s)}
  end

  def handle_info({:map_died, _}, s) do
    s = refresh(s)
    push_player(s)
    {:noreply, s, timeout(s)}
  end

  def handle_info(:save, %{on_map: true} = s) do
    s = %{s | save_timer: nil} |> refresh() |> persist()
    {:noreply, schedule_save(s), timeout(s)}
  end

  def handle_info(:delayed_leave, s) do
    s = %{s | leave_timer: nil}
    s = if map_size(s.tabs) == 0, do: leave_map(s), else: s
    {:noreply, s, timeout(s)}
  end

  def handle_info(:timeout, %{tabs: tabs, leave_timer: nil} = s) when map_size(tabs) == 0,
    do: {:stop, :normal, s}

  def handle_info(_msg, s), do: {:noreply, s, timeout(s)}

  @impl true
  def terminate(_reason, s) do
    leave_map(s)
    :ok
  end

  # ---------- Lệnh ----------

  defp run("move_to", %{"x" => x, "y" => y}, s),
    do: {MapServer.move_to(s.character.map_id, s.character.id, x, y), s}

  defp run("move_to", _, s), do: {{:error, "INVALID_TARGET"}, s}

  defp run("attack", %{"target" => target} = p, s),
    do: {skill(s, "basic_attack", target, p["rid"]), s}

  defp run("attack", _, s), do: {{:error, "INVALID_TARGET"}, s}

  defp run("skill", %{"id" => id} = p, s) when is_binary(id) do
    target =
      case p do
        %{"target" => t} when is_binary(t) -> t
        %{"x" => x, "y" => y} -> {x, y}
        _ -> nil
      end

    {skill(s, id, target, p["rid"]), s}
  end

  defp run("skill", _, s), do: {{:error, "INVALID_TARGET"}, s}

  defp run("alloc", %{"stat" => stat, "points" => points}, s) do
    case Engine.alloc(refresh(s).character, stat, points) do
      {:ok, c} ->
        s = %{s | character: c} |> sync_map(%{}) |> persist()
        push_player(s)
        {:ok, s}

      error ->
        {error, s}
    end
  end

  defp run("alloc", _, s), do: {{:error, "FORBIDDEN"}, s}

  # act khác: M4 (item, shop) — DEC-16
  defp run(_act, _payload, s), do: {{:error, "FORBIDDEN"}, s}

  defp skill(s, id, target, rid) do
    with :ok <- Engine.can_use_skill(s.character, id) do
      MapServer.use_skill(s.character.map_id, s.character.id, id, target, rid)
    end
  end

  # ---------- Map ----------

  # Nhân vật đang giữ trùng id thì dùng luôn (không đọc lại DB, tránh mất trạng thái chưa lưu)
  defp load(%{character: %{id: id} = c}, id), do: c
  defp load(s, character_id), do: Characters.get_owned(s.account_id, character_id)

  defp kick_tabs(s, pid) do
    if Config.get(["session", "singleLoginPerAccount"]) do
      for {ref, old} <- s.tabs, old != pid do
        Process.demonitor(ref, [:flush])
        send(old, {:session_kicked, :new_login})
      end

      %{s | tabs: %{}}
    else
      s
    end
  end

  defp map_player(c) do
    %{
      character_id: c.id,
      name: c.name,
      class: c.class,
      level: c.level,
      hp: c.hp_current,
      mp: c.mana_current,
      x: c.position_x,
      y: c.position_y,
      stats: Engine.derived(c),
      skills: Engine.skills(c)
    }
  end

  # Báo MapServer chỉ số mới (sau lên cấp/cộng điểm), kèm `extra` (hp/mp).
  defp sync_map(%{on_map: true, character: c} = s, extra) do
    changes =
      Map.merge(%{level: c.level, stats: Engine.derived(c), skills: Engine.skills(c)}, extra)

    :ok = MapServer.update_player(c.map_id, c.id, changes)
    s
  end

  defp sync_map(s, _), do: s

  # Lấy vị trí/HP/MP hiện tại từ MapServer vào `character`.
  defp refresh(%{on_map: true, character: c} = s) do
    case MapServer.player_state(c.map_id, c.id) do
      nil ->
        s

      p ->
        %{
          s
          | character: %{
              c
              | position_x: p.x,
                position_y: p.y,
                hp_current: p.hp,
                mana_current: p.mp
            }
        }
    end
  end

  defp refresh(s), do: s

  defp last_tab_closed(%{on_map: true, character: c} = s) do
    case MapServer.player_state(c.map_id, c.id) do
      %{combat_remaining_ms: ms} when ms > 0 ->
        # đang combat: ở lại logoutInCombatSeconds rồi mới rời (G21)
        stay = Config.get(["session", "logoutInCombatSeconds"]) * 1000
        %{s | leave_timer: Process.send_after(self(), :delayed_leave, stay)}

      _ ->
        leave_map(s)
    end
  end

  defp last_tab_closed(s), do: s

  defp cancel_leave(%{leave_timer: nil} = s), do: s

  defp cancel_leave(s) do
    Process.cancel_timer(s.leave_timer)
    %{s | leave_timer: nil}
  end

  defp leave_map(%{on_map: true, character: c} = s) do
    if s.save_timer, do: Process.cancel_timer(s.save_timer)
    s = %{s | on_map: false, save_timer: nil}

    s =
      case MapServer.leave(c.map_id, c.id) do
        {:ok, p} ->
          %{
            s
            | character: %{
                c
                | position_x: p.x,
                  position_y: p.y,
                  hp_current: p.hp,
                  mana_current: p.mp
              }
          }

        :error ->
          s
      end

    persist(s)
  end

  defp leave_map(s), do: s

  defp persist(s) do
    case Characters.save(s.saved, s.character) do
      {:ok, saved} ->
        # giữ version mới ở cả bản đang dùng
        %{s | saved: saved, character: %{s.character | version: saved.version}}

      {:error, reason} ->
        Logger.error("Không lưu được nhân vật #{s.character.id}: #{inspect(reason)}")
        s
    end
  end

  defp push_player(s) do
    view = Characters.player_view(s.character)
    for {_, pid} <- s.tabs, do: send(pid, {:push, "player", view})
    :ok
  end

  defp schedule_save(%{save_timer: nil} = s) do
    ms = Config.get(["session", "saveIntervalSeconds"]) * 1000
    %{s | save_timer: Process.send_after(self(), :save, ms)}
  end

  defp schedule_save(s), do: s

  defp reply(result, s), do: {:reply, result, s, timeout(s)}

  defp timeout(%{tabs: tabs, leave_timer: nil}) when map_size(tabs) == 0, do: @idle_timeout
  defp timeout(_), do: :infinity
end

defmodule HacLong.World.SecretWatch do
  @moduledoc """
  Canh Động Bí Ẩn (DECISIONS "Động Bí Ẩn"), mỗi `@tick_ms`:

  - tới giờ trùm đêm thức giấc (`HacLong.World.Secret.boss_due?/1`) và đêm nay chưa thả: thả Thạch Long Ẩn ở một ô trống
    trong động, báo cả server;
  - còn ≤ `warn_min` phút là sáng: báo riêng người trong động "đá bắt đầu rơi" (một lần mỗi đêm);
  - cửa đã đóng (trời sáng / đêm không mở): đưa người còn trong động ra cổng Đền Cổ (`RULES.secret.exit`).

  `config :hac_long, :secret_watch, auto: false` (test) thì không tự chạy; test gọi `tick/1`.
  """
  use GenServer
  require Logger

  alias HacLong.World.{MapServer, Maps, Secret}
  alias HacLong.Game.{Data, Session}

  @tick_ms 20_000

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    if Application.get_env(:hac_long, :secret_watch, [])[:auto] != false, do: schedule()
    {:ok, %{boss_night: nil, warned: nil}}
  end

  @impl true
  def handle_info(:tick, s) do
    schedule()
    {:noreply, tick(s, DateTime.utc_now())}
  rescue
    e ->
      Logger.warning("SecretWatch: #{inspect(e)}")
      {:noreply, s}
  end

  defp schedule, do: Process.send_after(self(), :tick, @tick_ms)

  @doc "Một nhịp canh lúc `now` (hàm có tác dụng phụ: thả trùm, báo, đưa người ra). Trả trạng thái mới."
  def tick(s, now) do
    night = Secret.night_of(now)
    map = Secret.map_id()

    cond do
      Secret.boss_due?(now) and s.boss_night != night ->
        spawn_boss(map)
        %{s | boss_night: night}

      Secret.open?(now) and Secret.collapse_soon?(now) and s.warned != night ->
        for uid <- players(map) do
          Phoenix.PubSub.broadcast(
            HacLong.PubSub,
            Session.topic(uid),
            {:notice, "⚠ Đá bắt đầu rơi lả tả… Trời sắp sáng, động sắp sụp! Hãy ra khỏi động."}
          )
        end

        %{s | warned: night}

      not Secret.open?(now) ->
        r = Secret.rules()

        for uid <- players(map),
            do: Session.teleport(uid, %{map: r.exit.map, x: r.exit.x, y: r.exit.y})

        s

      true ->
        s
    end
  end

  defp players(map) do
    case Registry.lookup(HacLong.World.Registry, map) do
      [_] -> MapServer.snapshot(map).players |> Enum.map(& &1.id)
      [] -> []
    end
  end

  defp spawn_boss(map) do
    spec = Data.side_monster(Secret.rules().boss)
    m = Maps.get(map)

    if Enum.any?(MapServer.snapshot(map).monsters, & &1.boss) do
      {:error, "#{spec.name} đang thức rồi."}
    else
      pos =
        Enum.find(
          Enum.shuffle(for y <- 2..(m.height - 4), x <- 2..(m.width - 3), do: {x, y}),
          fn {x, y} ->
            Maps.walkable?(m, x, y) and Maps.portal_at(m, x, y) == nil
          end
        )

      MapServer.put_monster(map, spec.id, pos, false, false, %{
        name: spec.name,
        level: spec.level,
        night_boss: true
      })

      HacLong.Chat.system(
        "🐉 #{spec.name} đã thức giấc trong động sâu! Kẻ nào đủ gan thì tìm tới."
      )

      :ok
    end
  end

  @doc "Quản trị gọi trùm đêm thức giấc ngay (đêm nay không tự thả nữa). `:ok` | `{:error, lý do}`."
  def summon_boss do
    GenServer.call(__MODULE__, :summon_boss)
  catch
    :exit, _ -> spawn_boss(Secret.map_id())
  end

  @impl true
  def handle_call(:summon_boss, _from, s) do
    {:reply, spawn_boss(Secret.map_id()), %{s | boss_night: Secret.night_of(DateTime.utc_now())}}
  end
end

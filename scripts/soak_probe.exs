# Đo server đang soak từ một node Erlang khác (CHỈ cho test, xem docs/ACCEPTANCE.md):
#   server: TRUSTED_PROXIES=127.0.0.1 elixir --sname mu -S mix phx.server
#   probe:  elixir --sname probe scripts/soak_probe.exs mu@<host> <số_lần> <giây_giữa_hai_lần>
[node, n, every] = System.argv()
node = String.to_atom(node)
true = Node.connect(node)

for i <- 1..String.to_integer(n) do
  if i > 1, do: Process.sleep(String.to_integer(every) * 1000)

  stats = :rpc.call(node, Mu.World.MapServer, :stats, ["lorencia"])
  [{map_pid, _}] = :rpc.call(node, Registry, :lookup, [Mu.World.Registry, "lorencia"])
  {:message_queue_len, q} = :rpc.call(node, Process, :info, [map_pid, :message_queue_len])
  {:memory, map_mem} = :rpc.call(node, Process, :info, [map_pid, :memory])
  mem = :rpc.call(node, :erlang, :memory, [:total])
  procs = :rpc.call(node, :erlang, :system_info, [:process_count])
  sessions = :rpc.call(node, DynamicSupervisor, :count_children, [Mu.Game.SessionSupervisor]).active
  {uptime_ms, _} = :rpc.call(node, :erlang, :statistics, [:wall_clock])
  # nhóm (P3-M4): hàng đợi tiến trình Mu.Party + số nhóm đang có
  party_pid = :rpc.call(node, Process, :whereis, [Mu.Party])
  {:message_queue_len, pq} = :rpc.call(node, Process, :info, [party_pid, :message_queue_len])
  parties = map_size(:rpc.call(node, :sys, :get_state, [Mu.Party]).parties)
  # guild (P4-M5): hàng đợi Mu.Guild, số người online đăng ký, số war đang diễn ra
  guild_pid = :rpc.call(node, Process, :whereis, [Mu.Guild])
  {:message_queue_len, gq} = :rpc.call(node, Process, :info, [guild_pid, :message_queue_len])
  gs = :rpc.call(node, :sys, :get_state, [Mu.Guild])
  wars = div(map_size(gs.war.wars), 2)

  IO.puts(
    "#{DateTime.utc_now() |> DateTime.truncate(:second)} | tick #{stats.ticks} " <>
      "(kỳ vọng ~#{div(uptime_ms, 50)} theo uptime VM) | max_drift #{stats.max_drift_ms} ms | " <>
      "người chơi #{stats.players} | session #{sessions} | MapServer queue #{q}, " <>
      "#{div(map_mem, 1024)} KB | Party queue #{pq}, #{parties} nhóm | " <>
      "Guild queue #{gq}, online #{map_size(gs.online)}, war #{wars} | " <>
      "RAM VM #{div(mem, 1_048_576)} MB | process #{procs}"
  )
end

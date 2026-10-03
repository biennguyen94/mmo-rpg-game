defmodule MuWeb.ChannelCase do
  @moduledoc "Test Channel: database (sandbox dùng chung) và tiện ích vào game."
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import MuWeb.ChannelCase
      import Mu.DataCase, only: [create_account: 0, create_character: 0, create_character: 1]
      @endpoint MuWeb.Endpoint
    end
  end

  setup tags do
    # Session (không phải tiến trình test) cũng đọc/ghi database nên sandbox dùng chung:
    # test Channel không chạy async.
    Mu.DataCase.setup_sandbox(Map.put(tags, :async, false))
    Mu.RateLimit.reset()
    reset_map("lorencia")

    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Mu.Game.SessionSupervisor),
          do: DynamicSupervisor.terminate_child(Mu.Game.SessionSupervisor, pid)
    end)

    :ok
  end

  @doc "Khởi động lại MapServer của map (quái mới, không còn người/đồ từ test trước)."
  def reset_map(map_id) do
    id = {Mu.World.MapServer, map_id}
    :ok = Supervisor.terminate_child(Mu.World.MapSupervisor, id)
    {:ok, _} = Supervisor.restart_child(Mu.World.MapSupervisor, id)
    :ok
  end

  @doc "Mở socket bằng ticket thật (như client)."
  def connect_account(account) do
    ticket = Mu.Accounts.issue_ws_ticket(account)
    Phoenix.ChannelTest.__connect__(MuWeb.Endpoint, MuWeb.UserSocket, %{"ticket" => ticket}, [])
  end

  def client_version, do: Mu.Game.Config.get(["server", "clientVersion"])
end

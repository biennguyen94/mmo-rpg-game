defmodule Mu.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MuWeb.Telemetry,
      Mu.Repo,
      {Phoenix.PubSub, name: Mu.PubSub},
      Mu.RateLimit,
      Mu.Accounts.WsTicket,
      # 1 Session / tài khoản đang online (KB_TECH_STACK §4)
      {Registry, keys: :unique, name: Mu.Game.Registry},
      {DynamicSupervisor, name: Mu.Game.SessionSupervisor, strategy: :one_for_one},
      MuWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Mu.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MuWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

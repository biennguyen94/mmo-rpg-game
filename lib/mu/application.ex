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
      Mu.Chat,
      # nhóm (P3-M4): RAM + ETS, trước Session / MapServer
      Mu.Party,
      # guild đang online + lời mời (P4-M3); dữ liệu guild trong DB
      Mu.Guild,
      # giao dịch (P5-M4, KB_TECHNICAL §10): 1 TradeSettlement / giao dịch đang mở
      {Registry, keys: :unique, name: Mu.Trade.Registry},
      {DynamicSupervisor, name: Mu.Trade.Supervisor, strategy: :one_for_one},
      # bảng xếp hạng (P6-M1): cache RAM, đọc DB khi bảng cũ
      Mu.Leaderboard,
      Mu.Accounts.WsTicket,
      Mu.Game.OrphanSweeper,
      # 1 Session / tài khoản đang online (KB_TECH_STACK §4)
      {Registry, keys: :unique, name: Mu.Game.Registry},
      # tên nhân vật (chữ thường) → Session đang giữ nhân vật đó, cho WHISPER (P2-M5)
      {Registry, keys: :unique, name: Mu.Game.NameRegistry},
      {DynamicSupervisor, name: Mu.Game.SessionSupervisor, strategy: :one_for_one},
      # 1 MapServer / map (Phase 1: chỉ Lorencia)
      {Registry, keys: :unique, name: Mu.World.Registry},
      %{
        id: Mu.World.MapSupervisor,
        type: :supervisor,
        start:
          {Supervisor, :start_link,
           [
             Enum.map(Mu.World.Maps.ids(), &Mu.World.MapServer.child_spec/1),
             [strategy: :one_for_one, name: Mu.World.MapSupervisor]
           ]}
      },
      # lịch event thế giới (P6-M5): sau MapServer (ra lệnh sinh / thu quái event)
      Mu.WorldEvents,
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

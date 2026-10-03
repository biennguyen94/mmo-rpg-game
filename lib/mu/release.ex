defmodule Mu.Release do
  @moduledoc """
  Việc chạy trong bản release (không có `mix`), vd. trong container Docker:

      bin/mu eval "Mu.Release.migrate()"

  `rel/overlays/bin/start` gọi `migrate/0` rồi mới khởi động server.
  """
  @app :mu

  @doc "Chạy các migration còn thiếu."
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end

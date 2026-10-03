defmodule Mu.Repo do
  use Ecto.Repo,
    otp_app: :mu,
    adapter: Ecto.Adapters.Postgres
end

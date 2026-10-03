defmodule MuWeb.Router do
  use MuWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authed do
    plug MuWeb.Auth
  end

  # Đường dẫn đúng như KB_TECHNICAL §4 (không thêm tiền tố /api): OPEN_QUESTIONS P1
  scope "/", MuWeb do
    pipe_through :api
    post "/register", AuthController, :register
    post "/login", AuthController, :login
  end

  scope "/", MuWeb do
    pipe_through [:api, :authed]
    post "/logout", AuthController, :logout
    post "/ws-ticket", AuthController, :ws_ticket
    get "/characters", CharacterController, :index
    post "/characters", CharacterController, :create
  end

  scope "/", MuWeb do
    get "/", PageController, :index
  end
end

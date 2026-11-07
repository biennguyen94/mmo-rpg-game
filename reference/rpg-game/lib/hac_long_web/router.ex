defmodule HacLongWeb.Router do
  use HacLongWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", HacLongWeb do
    pipe_through :api
    post "/register", AuthController, :register
    post "/login", AuthController, :login
    post "/forgot", AuthController, :forgot
    post "/question", AuthController, :question
    post "/recover", AuthController, :recover
    post "/security", AuthController, :security
    get "/me", AuthController, :me
    post "/logout", AuthController, :logout
    post "/logout_all", AuthController, :logout_all
    post "/password", AuthController, :password
    post "/ws-ticket", AuthController, :ws_ticket
    post "/characters", AuthController, :new_character
    post "/characters/delete", AuthController, :delete_character
  end

  scope "/", HacLongWeb do
    get "/", PageController, :index
  end
end

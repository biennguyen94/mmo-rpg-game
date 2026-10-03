defmodule MuWeb do
  @moduledoc """
  Giao diện web: HTTP JSON (đăng ký, đăng nhập, ticket, nhân vật) và Channel `"game"`.

      use MuWeb, :controller
  """

  def static_paths, do: ~w(assets js css favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end

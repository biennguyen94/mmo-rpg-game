defmodule Mu.DataCase do
  @moduledoc "Test cần database (SQL sandbox) và tiện ích tạo tài khoản/nhân vật."
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Mu.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Mu.DataCase
    end
  end

  setup tags do
    Mu.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Mu.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  def unique_name(prefix \\ "u"), do: "#{prefix}#{System.unique_integer([:positive])}"

  @doc "Tạo tài khoản (mật khẩu `matkhau123`)."
  def create_account(username \\ unique_name("acc")) do
    {:ok, account} =
      Mu.Accounts.register(%{"username" => username, "password" => "matkhau123"})

    account
  end

  @doc "Tạo tài khoản + một DK, trả về `{account, character}`."
  def create_character(name \\ nil) do
    account = create_account()
    name = name || "Dk#{rem(System.unique_integer([:positive]), 10_000_000)}"
    {:ok, character} = Mu.Game.Characters.create(account, %{"name" => name})
    {account, character}
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

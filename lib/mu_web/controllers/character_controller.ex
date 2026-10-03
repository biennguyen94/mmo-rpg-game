defmodule MuWeb.CharacterController do
  @moduledoc "`GET /characters`, `POST /characters {name, class?}` (OPEN_QUESTIONS P1)."
  use MuWeb, :controller

  import MuWeb.HttpHelpers

  alias Mu.Game.Characters

  def index(conn, _params) do
    account = conn.assigns.current_account
    json(conn, %{characters: Enum.map(Characters.list(account.id), &Characters.summary/1)})
  end

  def create(conn, params) do
    account = conn.assigns.current_account

    with :ok <- limit(conn, {:create_character, account.id}, ["createCharacter", "perAccount"]) do
      case Characters.create(account, Map.take(params, ["name", "class"])) do
        {:ok, c} ->
          conn |> put_status(:created) |> json(%{character: Characters.summary(c)})

        {:error, reason} ->
          {status, code, msg} = describe(reason)
          error(conn, status, code, msg)
      end
    end
  end

  defp describe(:invalid_name),
    do:
      {:unprocessable_entity, "INVALID_NAME",
       "Tên nhân vật phải dài 4–10 ký tự, chỉ chữ không dấu và số."}

  defp describe(:banned_name),
    do: {:unprocessable_entity, "INVALID_NAME", "Tên nhân vật không được phép."}

  defp describe(:name_taken), do: {:conflict, "NAME_TAKEN", "Tên nhân vật đã có người dùng."}

  defp describe(:invalid_class),
    do: {:unprocessable_entity, "INVALID_CLASS", "Class không hợp lệ."}

  defp describe(:character_limit),
    do: {:conflict, "CHARACTER_LIMIT", "Tài khoản đã đủ số nhân vật."}

  defp describe(_), do: {:unprocessable_entity, "VALIDATION", "Dữ liệu không hợp lệ."}
end

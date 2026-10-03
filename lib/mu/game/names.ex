defmodule Mu.Game.Names do
  @moduledoc """
  Tên nhân vật (`KB_GAME_DESIGN §18`, `KB_TECHNICAL §9`): 4–10 ký tự ASCII chữ/số
  (`names.characterPattern`), unique không phân biệt hoa thường (index `characters_name_ci`),
  qua bộ lọc từ cấm `names.bannedWords` (G22, mặc định rỗng).
  ASCII-only nên không cần chuẩn hóa NFC như repo nền.
  """

  alias Mu.Game.Config

  @doc "`{:ok, tên}` hoặc `{:error, :invalid_name | :banned_name}`."
  def validate(name) when is_binary(name) do
    name = String.trim(name)
    pattern = Regex.compile!(Config.get(["names", "characterPattern"]))

    cond do
      not Regex.match?(pattern, name) -> {:error, :invalid_name}
      banned?(name) -> {:error, :banned_name}
      true -> {:ok, name}
    end
  end

  def validate(_), do: {:error, :invalid_name}

  defp banned?(name) do
    lower = String.downcase(name)

    Config.get(["names", "bannedWords"])
    |> Enum.any?(&String.contains?(lower, String.downcase(&1)))
  end
end

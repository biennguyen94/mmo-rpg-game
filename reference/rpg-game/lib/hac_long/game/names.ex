defmodule HacLong.Game.Names do
  @moduledoc """
  Tên nhân vật: 2–16 ký tự gồm chữ (có dấu), số, khoảng trắng, `-` và `_`.
  Hai tên trùng nhau nếu giống nhau sau khi bỏ khoảng trắng thừa và chuyển chữ thường
  (`key/1`); database có ràng buộc duy nhất trên khóa này.

  Tên không được chứa từ cấm (`RULES.names` trong `priv/game_data/rules.json`, xem `banned?/1`).
  """

  @rules HacLong.Game.Data.rules().names
  @words @rules.banned_words
  @parts @rules.banned_parts
  @leet %{"0" => "o", "1" => "i", "3" => "e", "4" => "a", "5" => "s", "7" => "t", "8" => "b"}

  @doc "Chuẩn hóa tên người chơi gõ: NFC, bỏ khoảng trắng đầu cuối và khoảng trắng thừa."
  def normalize(name) do
    name
    |> to_string()
    |> :unicode.characters_to_nfc_binary()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  def key(name), do: name |> normalize() |> String.downcase()

  @doc "`{:ok, tên_đã_chuẩn_hóa}` hoặc `{:error, lý_do}`."
  def validate(name) do
    name = normalize(name)
    len = String.length(name)

    cond do
      len < 2 or len > 16 ->
        {:error, "Tên nhân vật phải dài 2–16 ký tự."}

      not Regex.match?(~r/^[\p{L}\p{M}\p{N} _\-]+$/u, name) ->
        {:error, "Tên chỉ gồm chữ, số, khoảng trắng, - và _."}

      banned?(name) ->
        {:error, banned_msg()}

      true ->
        {:ok, name}
    end
  end

  def banned_msg,
    do: "Tên có từ không được dùng (chửi thề hoặc giả danh quản trị). Chọn tên khác."

  @doc """
  Tên có từ cấm không. So sánh sau khi bỏ dấu, chữ thường, `đ` → `d`:

  - `banned_words`: khớp **nguyên từ** (cụm từ được, như `"du ma"`); số và ký hiệu tính là chỗ ngắt
    từ, nên `"GM01"` khớp `gm` còn `"Long"` không khớp `lon`.
  - `banned_parts`: khớp **một phần** của tên đã bỏ hết khoảng trắng / ký hiệu, có đổi số kiểu
    `4dm1n` → `admin` (chỉ để những từ dài, không lẫn với tên thường).
  """
  def banned?(name) do
    s = fold(name)
    words = " " <> (s |> String.split(~r/[^a-z]+/, trim: true) |> Enum.join(" ")) <> " "
    compact = s |> String.replace(Map.keys(@leet), &@leet[&1]) |> String.replace(~r/[^a-z]/, "")

    Enum.any?(@words, &String.contains?(words, " " <> &1 <> " ")) or
      Enum.any?(@parts, &String.contains?(compact, &1))
  end

  @doc "Bỏ dấu tiếng Việt, chữ thường (`\"Đụ Má\"` → `\"du ma\"`)."
  def fold(name) do
    name
    |> to_string()
    |> String.replace(["đ", "Đ"], "d")
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end
end

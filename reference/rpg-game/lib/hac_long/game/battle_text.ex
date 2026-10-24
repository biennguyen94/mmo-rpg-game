defmodule HacLong.Game.BattleText do
  @moduledoc """
  Đổi góc nhìn nhật ký trận đánh người (DECISIONS "Nhật ký đánh người chi tiết"): `Engine` ghi nhật ký theo
  người đánh ("Bạn gây N sát thương", đối thủ là "quái" mang tên người kia). Đồ sát, PK cược, đấu trường dùng
  hàm ở đây để bên kia (hoặc người xem) đọc được đúng đòn đó: kỹ năng, chí mạng, nhiều đòn, khắc hệ, trượt, thú cưng…
  """

  @doc """
  Một dòng nhật ký của người đánh `name`, nhắc người bị đánh `foe_name`:
  "Bạn" → `name`, `foe_name` → `you` ("bạn" cho người bị đánh đọc, hoặc tên họ cho người xem),
  "gây / cắn thêm N sát thương" thêm "cho `you`"; dòng không nhắc tên người đánh (trượt, Khiên Thánh hồi máu,
  thú cưng cắn…) thì thêm "`name`: " ở đầu.
  """
  def mirror(text, name, foe_name, you \\ "bạn") do
    word = fn w -> ~r/(?<![\p{L}\p{N}_])#{w}(?![\p{L}\p{N}_])/u end

    # \0 giữ chỗ người bị đánh để không lẫn với "bạn" (người đánh) trong câu gốc
    t = Regex.replace(word.(Regex.escape(foe_name)), text, "\0")
    t = Regex.replace(word.("[Bb]ạn"), t, name)

    t =
      if String.contains?(t, "\0"),
        do: t,
        else:
          Regex.replace(~r/(gây|cắn thêm) \d+ sát thương(?! cho)/u, t, "\\0 cho \0",
            global: false
          )

    t =
      if you == "bạn",
        do: Regex.replace(~r/(^|[!:.] |^[^\p{L}\p{N}]+ )\x{0}/u, t, "\\1Bạn"),
        else: t

    t = String.replace(t, "\0", you)
    if String.contains?(t, name), do: t, else: "#{name}: #{t}"
  end

  @doc "Các dòng nhật ký (`%{text, kind}`) của một lượt → góc nhìn khác (`mirror/4`), bỏ dòng thừa (hồi 0 máu)."
  def view(log, name, foe_name, you \\ "bạn") do
    for l <- log,
        not (l.text =~ ~r/ hồi 0 máu/u),
        do: %{l | text: mirror(l.text, name, foe_name, you)}
  end
end

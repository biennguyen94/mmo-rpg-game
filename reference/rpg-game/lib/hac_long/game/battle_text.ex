defmodule HacLong.Game.BattleText do
  @moduledoc """
  Đổi góc nhìn nhật ký trận đánh người (DECISIONS "Nhật ký đánh người chi tiết"): `Engine` ghi nhật ký theo
  người đánh (đối thủ là "quái" mang tên người kia). Đồ sát, đấu trường dùng
  hàm ở đây để bên kia (hoặc người xem) đọc được đúng đòn đó: kỹ năng, chí mạng, nhiều đòn, khắc hệ, trượt, thú cưng…
  """

  @doc """
  Một dòng nhật ký của người đánh `name` cho người khác đọc. Nhật ký trận đã ghi tên hai bên ("Tên, dùng gì, gây N
  sát thương", DECISIONS "Nhật ký trận: tên, dùng gì, gây bao nhiêu"), không xưng "bạn", nên chỉ thêm "`name`: " ở đầu
  dòng không nhắc tên người đánh. `foe_name`, `you` giữ cho các chỗ gọi cũ.
  """
  def mirror(text, name, _foe_name, _you \\ nil) do
    if text =~ ~r/(?<![\p{L}\p{N}_])#{Regex.escape(name)}(?![\p{L}\p{N}_])/u,
      do: text,
      else: "#{name}: #{text}"
  end

  @doc "Các dòng nhật ký (`%{text, kind}`) của một lượt → góc nhìn khác (`mirror/4`), bỏ dòng thừa (hồi 0 máu)."
  def view(log, name, foe_name, you \\ nil) do
    for l <- log,
        not (l.text =~ ~r/ hồi 0 máu/u),
        do: %{l | text: mirror(l.text, name, foe_name, you)}
  end
end

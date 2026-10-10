defmodule HacLong.TienLen.Chat do
  @moduledoc """
  Chat trong bàn Tiến Lên (G1–G4 của repo gốc, thu gọn cho Hắc Long): biểu cảm, câu nhanh và
  chuẩn hóa tin. Tin giữ trong `HacLong.TienLen.RoomServer` (bộ nhớ, 50 tin), không lưu database.
  Kiểm tra bị khóa chat (`Accounts.muted?/1`) ở kênh, như chat thế giới.
  """

  @max_length 200
  @rate_limit 5
  @rate_window 10_000

  # R1: biểu cảm trên ghế (không phải chat, không lưu)
  @reactions ~w(😂 👏 😮 😡 👍 🔥)

  # G3: câu nhanh
  @phrases [
    "Nhanh lên!",
    "Hay quá!",
    "Chúc may mắn!",
    "Cảm ơn!",
    "Xin lỗi, mạng lag",
    "Ván này căng!",
    "Chơi lại không?",
    "Hẹn gặp lại!"
  ]

  def reactions, do: @reactions
  def phrases, do: @phrases

  @doc "Chuẩn hóa chữ: bỏ ký tự điều khiển, gộp khoảng trắng, 1–#{@max_length} ký tự."
  def normalize(text) when is_binary(text) do
    if String.valid?(text) do
      text =
        text
        |> String.replace(~r/[\p{Cc}\p{Cf}]/u, " ")
        |> String.replace(~r/\s+/u, " ")
        |> String.trim()

      if String.length(text) in 1..@max_length, do: {:ok, text}, else: {:error, :invalid_message}
    else
      {:error, :invalid_message}
    end
  end

  def normalize(_), do: {:error, :invalid_message}

  @doc "Dựng tin của người chơi `user_id` tên `name`: `{:ok, tin}` hoặc `{:error, lý_do}`."
  def prepare(user_id, name, text) do
    with {:ok, text} <- normalize(text),
         :ok <- rate(user_id) do
      {:ok,
       %{
         id: System.unique_integer([:positive, :monotonic]),
         user_id: user_id,
         name: name,
         text: text,
         at: DateTime.utc_now(:second)
       }}
    end
  end

  defp rate(user_id) do
    case HacLong.RateLimit.hit({:tienlen_chat, user_id}, @rate_limit, @rate_window) do
      :ok -> :ok
      _ -> {:error, :chat_too_fast}
    end
  end
end

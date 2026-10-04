defmodule Mu.Chat do
  @moduledoc """
  Chat (`KB_GAME_DESIGN §16`, `KB_TECHNICAL §5`, P2-12). Học từ `HacLong.Chat` (làm sạch chữ:
  bỏ ký tự điều khiển, gộp khoảng trắng, cắt độ dài; tin không lưu DB) và ý tưởng cấm chat có
  thời hạn của `HacLong.Moderation` (ở đây giữ trong RAM, không thêm bảng ngoài §9).

  - `NORMAL`: mọi người trên cùng map (`chat.normalScope` = `"map"`), qua topic PubSub của map.
  - `WHISPER`: tới nhân vật đang online theo tên (không phân biệt hoa thường); người gửi nhận
    bản sao có `to`.
  - `PARTY`: từ P3-M4 qua `Mu.Party.chat/2` (không có nhóm → `INVALID_TARGET`). `GUILD`: tắt tới
    Phase 4 (`FORBIDDEN`). `SYSTEM`: chỉ server gửi (`system/1`).
  - Từ cấm `chat.bannedWords` thay bằng `chat.mask`. Hiển thị ở client bằng text node (chống XSS).

  Event `chat`: `{channel, from, text, t}` (+ `to` ở bản sao whisper của người gửi).
  """
  use GenServer

  alias Mu.Game.Config
  alias Mu.World.{Maps, MapServer}

  @table :mu_chat_mutes

  # ---------- Hàm thuần ----------

  @doc """
  Làm sạch tin: ký tự điều khiển → khoảng trắng, gộp khoảng trắng, bỏ đầu/cuối, cắt
  `chat.maxLength` ký tự. `{:ok, text}` hoặc `{:error, "INVALID_TARGET"}` (trống / sai kiểu).
  """
  def clean(text) when is_binary(text) do
    text =
      text
      |> String.replace(~r/[\p{Cc}\p{Cf}]/u, " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
      |> String.slice(0, Config.get(["chat", "maxLength"]))

    if text == "", do: {:error, "INVALID_TARGET"}, else: {:ok, text}
  end

  def clean(_), do: {:error, "INVALID_TARGET"}

  @doc "Thay từ cấm `words` (mặc định `chat.bannedWords`, không phân biệt hoa thường) bằng `chat.mask`."
  def filter(text, words \\ Config.get(["chat", "bannedWords"])) do
    mask = Config.get(["chat", "mask"])

    Enum.reduce(words, text, fn w, acc ->
      String.replace(acc, ~r/#{Regex.escape(w)}/iu, mask)
    end)
  end

  @doc "Payload event `chat`."
  def message(channel, from, text),
    do: %{channel: channel, from: from, text: text, t: System.os_time(:millisecond)}

  # ---------- Gửi ----------

  @doc "Tin NORMAL tới mọi người trên `map_id`."
  def say(map_id, from, text) do
    Phoenix.PubSub.broadcast(
      Mu.PubSub,
      MapServer.topic(map_id),
      {:map_event, "chat", message("NORMAL", from, text)}
    )
  end

  @doc "Dòng SYSTEM tới mọi người trên `map_id` (vd. ép đồ +7 trở lên, P5-M2)."
  def system_map(map_id, text) do
    msg = message("SYSTEM", Config.get(["chat", "systemName"]), text)
    Phoenix.PubSub.broadcast(Mu.PubSub, MapServer.topic(map_id), {:map_event, "chat", msg})
  end

  @doc "Thông báo hệ thống tới mọi map (quản trị: `mix mu.chat system \"...\"`)."
  def system(text) do
    {:ok, text} = clean(text)
    msg = message("SYSTEM", Config.get(["chat", "systemName"]), text)

    for id <- Maps.ids(),
        do: Phoenix.PubSub.broadcast(Mu.PubSub, MapServer.topic(id), {:map_event, "chat", msg})

    :ok
  end

  # ---------- Cấm chat (RAM, mất khi server khởi động lại) ----------

  @doc "Cấm chat nhân vật `name` trong `minutes` phút (`nil` = tới khi server khởi động lại)."
  def mute(name, minutes) when is_binary(name) do
    until = if minutes, do: System.os_time(:second) + minutes * 60, else: :infinity
    :ets.insert(@table, {String.downcase(name), until})
    :ok
  end

  def unmute(name) when is_binary(name) do
    :ets.delete(@table, String.downcase(name))
    :ok
  end

  @doc "`nil` nếu được chat; ngược lại thời điểm hết cấm (giây epoch) hoặc `:infinity`."
  def muted_until(name) do
    case :ets.lookup(@table, String.downcase(name)) do
      [{_, :infinity}] -> :infinity
      [{_, until}] -> if until > System.os_time(:second), do: until, else: nil
      [] -> nil
    end
  end

  # tiến trình chỉ để sở hữu bảng ETS
  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end
end

defmodule HacLong.World.Secret do
  @moduledoc """
  Bản đồ bí mật (DECISIONS "Bản đồ đẹp hơn", B2): người đầu tiên bước vào mỗi đêm được báo cả server. Đêm tính theo
  giờ Việt Nam (đêm bắt đầu lúc 20 giờ, kéo qua sáng hôm sau), nhớ trong `:persistent_term` (khởi động lại thì báo lại
  một lần, không sao). Bot không được báo.
  """
  @utc_offset 7 * 3600

  @doc "Người chơi `p` (`uid`) vừa vào bản đồ bí mật `map`: nếu là người đầu tiên đêm nay thì báo cả server."
  def found(map, p, uid, now \\ DateTime.utc_now()) do
    key = {__MODULE__, map.id, night_of(now)}

    if :persistent_term.get(key, nil) == nil and not HacLong.Bots.bot?(uid) do
      :persistent_term.put(key, p.name)
      HacLong.Chat.system("🌙 #{p.name} là người đầu tiên đêm nay tìm ra #{map.name}!")
      :announced
    else
      :ok
    end
  end

  @doc "Ngày của đêm đang diễn ra (giờ Việt Nam lùi 12 tiếng: 20 giờ hôm nay → 5 giờ mai cùng một đêm)."
  def night_of(now) do
    now |> DateTime.add(@utc_offset - 12 * 3600, :second) |> DateTime.to_date()
  end
end

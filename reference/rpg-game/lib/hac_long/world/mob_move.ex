defmodule HacLong.World.MobMove do
  @moduledoc """
  Quái đi lang thang trên bản đồ: bật / tắt cho cả server từ Quản trị (DECISIONS "Quản trị: bật / tắt quái di chuyển").

  Không thêm bảng: trạng thái lấy từ dòng `admin_log` op `mob_move` mới nhất (khởi động lại vẫn giữ), đệm trong
  `:persistent_term` để MapServer đọc mỗi nhịp mà không chạm DB. Chưa từng đặt (hoặc DB lỗi) thì bật.
  """
  @key {__MODULE__, :on}

  @doc "Quái có đang được đi lang thang không."
  def on? do
    case :persistent_term.get(@key, :unset) do
      :unset ->
        v = load()
        :persistent_term.put(@key, v)
        v

      v ->
        v
    end
  end

  @doc "Đặt trạng thái (người gọi đã ghi `admin_log` với `params.on`)."
  def set(on) when is_boolean(on), do: :persistent_term.put(@key, on)

  defp load do
    case HacLong.Admin.recent_op("mob_move", 1) do
      [%{params: %{"on" => v}}] when is_boolean(v) -> v
      _ -> true
    end
  rescue
    _ -> true
  end
end

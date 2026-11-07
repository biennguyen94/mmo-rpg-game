defmodule HacLong.NamePack do
  @moduledoc """
  Bộ tên cho cả server (DECISIONS "Bộ tên thay cho tên MU"): `"mu"` (tên gốc, theo MU) hoặc `"alt"` (tên mới trong
  `priv/static/i18n/names_alt.json`). Trình duyệt đổi tên khi hiện chữ (`i18n.js`); dữ liệu game, database và tin
  server vẫn dùng tên gốc, nên đổi qua lại không mất gì.

  Không thêm bảng (như `HacLong.World.MobMove`): trạng thái là dòng `admin_log` op `name_pack` mới nhất (`params.pack`),
  đệm trong `:persistent_term`. Chưa đặt bao giờ (hoặc DB lỗi) thì `"mu"`.
  """
  @key {__MODULE__, :pack}
  @packs ~w(mu alt)
  @topic "name_pack"

  def packs, do: @packs
  def topic, do: @topic

  @doc "Bộ tên đang dùng."
  def get do
    case :persistent_term.get(@key, :unset) do
      :unset ->
        v = load()
        :persistent_term.put(@key, v)
        v

      v ->
        v
    end
  end

  @doc "Đặt bộ tên (người gọi đã ghi `admin_log` với `params.pack`) và báo mọi người đang chơi tải lại."
  def set(pack) when pack in @packs do
    :persistent_term.put(@key, pack)
    Phoenix.PubSub.broadcast(HacLong.PubSub, @topic, {:name_pack, pack})
    :ok
  end

  defp load do
    case HacLong.Admin.recent_op("name_pack", 1) do
      [%{params: %{"pack" => v}}] when v in @packs -> v
      _ -> "mu"
    end
  rescue
    _ -> "mu"
  end
end

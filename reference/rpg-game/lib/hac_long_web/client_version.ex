defmodule HacLongWeb.ClientVersion do
  @moduledoc """
  Phiên bản giao diện (FEATURE_CATALOG I3): mã băm nội dung `priv/static/js/*.js` và
  `priv/static/css/*.css`, tính lúc biên dịch (`@external_resource`: sửa file giao diện thì mã đổi).

  Trang chủ chèn mã này vào `window.CLIENT_VERSION`; client gửi lại khi vào kênh `"game"`
  (`%{"v" => ...}`). Tab mở từ trước khi cập nhật server (mã cũ) bị từ chối với
  `reason: "version"` và tự tải lại trang, nên không gửi lệnh theo giao thức cũ.
  """
  @static Path.expand("../../priv/static", __DIR__)
  @files Enum.sort(
           Path.wildcard(Path.join(@static, "js/*.js")) ++
             Path.wildcard(Path.join(@static, "css/*.css"))
         )
  for f <- @files, do: @external_resource(f)

  @version :crypto.hash(:sha256, Enum.map(@files, &File.read!/1))
           |> Base.encode16(case: :lower)
           |> binary_part(0, 12)

  @doc "Mã phiên bản giao diện hiện tại."
  def current, do: @version
end

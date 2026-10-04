defmodule Mix.Tasks.HacLong.Admin do
  @shortdoc "Đặt vai trò (player / mod / admin) cho một tài khoản"
  @moduledoc """
  Cấp quyền quản trị (thấy tab Quản trị trong game):

      mix hac_long.admin ten_dang_nhap               # admin: mọi lệnh quản trị
      mix hac_long.admin ten_dang_nhap --role mod    # mod: báo cáo, tra cứu, cấm chat, thông báo
      mix hac_long.admin ten_dang_nhap --revoke      # về người chơi thường

  Người đó đăng nhập lại (hoặc tải lại trang) để thấy tab. Khi chạy bản release:
  `bin/hac_long eval 'HacLong.Release.admin("ten_dang_nhap")'` (hoặc `HacLong.Release.role/2`).
  """
  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, names, _} = OptionParser.parse(args, strict: [revoke: :boolean, role: :string])

    case names do
      [name] ->
        role = if opts[:revoke], do: "player", else: opts[:role] || "admin"

        case HacLong.Moderation.set_role(name, role) do
          {:ok, u} -> Mix.shell().info("#{u.username}: vai trò #{u.role}.")
          {:error, msg} when is_binary(msg) -> Mix.raise(msg)
          {:error, other} -> Mix.raise(inspect(other))
        end

      _ ->
        Mix.raise(
          "Cách dùng: mix hac_long.admin TEN_DANG_NHAP [--role player|mod|admin] [--revoke]"
        )
    end
  end
end

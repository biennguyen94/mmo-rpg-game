defmodule HacLong.Release do
  @moduledoc """
  Việc chạy trong bản release (không có `mix`), vd. trong container Docker:

      bin/hac_long eval "HacLong.Release.migrate()"
      bin/hac_long eval 'HacLong.Release.admin("ten_dang_nhap")'
      bin/hac_long eval 'HacLong.Release.role("ten_dang_nhap", "mod")'
      bin/hac_long eval 'HacLong.Release.audit(7)'
      bin/hac_long eval 'HacLong.Release.prune_logs(180)'

  `rel/overlays/bin/start` gọi `migrate/0` rồi mới khởi động server.
  """
  @app :hac_long

  @doc "Chạy các migration còn thiếu."
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc "Cấp (hoặc thu hồi với `false`) quyền quản trị cho tài khoản `username`."
  def admin(username, admin? \\ true), do: role(username, if(admin?, do: "admin", else: "player"))

  @doc "Đặt vai trò `\"player\"` / `\"mod\"` / `\"admin\"` cho tài khoản `username`."
  def role(username, role) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(HacLong.Repo, fn _ ->
        case HacLong.Moderation.set_role(username, role) do
          {:ok, u} -> IO.puts("#{u.username}: vai trò #{u.role}")
          {:error, msg} when is_binary(msg) -> IO.puts("Lỗi: " <> msg)
          {:error, other} -> IO.puts("Lỗi: #{inspect(other)}")
        end
      end)
  end

  @doc """
  Đối soát vàng / đồ hiếm (`HacLong.Audit`), in kết quả; có lỗi thì thoát mã 1 (dùng cho cron).
  Chạy bằng `eval` (node riêng, không đụng server đang chạy).
  """
  def audit(days \\ 1) do
    load_app()

    {:ok, problems, _} =
      Ecto.Migrator.with_repo(HacLong.Repo, fn _ ->
        r = HacLong.Audit.run(days: days)
        IO.inspect(r.stats, label: "thống kê", limit: :infinity)
        for p <- r.problems, do: IO.puts(:stderr, "[#{p.kind}] #{p.text}")
        r.problems
      end)

    if problems == [], do: IO.puts("Không có lỗi."), else: System.halt(1)
  end

  @doc "Dọn nhật ký vàng / đồ hiếm cũ hơn `days` ngày (`HacLong.Audit.prune/1`)."
  def prune_logs(days \\ 180) do
    load_app()
    {:ok, r, _} = Ecto.Migrator.with_repo(HacLong.Repo, fn _ -> HacLong.Audit.prune(days) end)
    IO.puts("Đã xóa #{r.gold} dòng nhật ký vàng, #{r.gear} dòng đồ hiếm.")
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end

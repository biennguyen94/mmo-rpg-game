# Chuẩn bị cho e2e (`e2e/`): tài khoản quản trị dùng để tặng vàng / đồ cho nhân vật test qua lệnh quản
# trị như người vận hành thật. Chạy lại nhiều lần được.
#
#     mix run scripts/e2e_seed.exs
#
# Tên / mật khẩu: HL_E2E_ADMIN / HL_E2E_ADMIN_PASS (mặc định e2e_admin / e2e-admin-pass).
name = System.get_env("HL_E2E_ADMIN", "e2e_admin")
pass = System.get_env("HL_E2E_ADMIN_PASS", "e2e-admin-pass")

case HacLong.Accounts.register(%{"username" => name, "password" => pass}) do
  {:ok, _} -> IO.puts("Tạo tài khoản #{name}.")
  {:error, _} -> IO.puts("Tài khoản #{name} đã có.")
end

{:ok, u} = HacLong.Moderation.set_role(name, "admin")
IO.puts("#{u.username}: vai trò #{u.role}.")

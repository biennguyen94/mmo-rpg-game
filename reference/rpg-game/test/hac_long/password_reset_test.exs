defmodule HacLong.PasswordResetTest do
  # DECISIONS "Đăng nhập nhanh hơn", "Quên mật khẩu"
  use HacLong.DataCase, async: true

  alias HacLong.Accounts
  alias HacLong.Accounts.{Password, PasswordReset}

  test "băm bằng :crypto dùng lẫn được với hash pbkdf2_elixir cũ" do
    old = Pbkdf2.hash_pwd_salt("matkhau1")
    new = Password.hash("matkhau1")
    assert Password.verify("matkhau1", old) and not Password.verify("sai", old)
    assert Pbkdf2.verify_pass("matkhau1", new) and Password.verify("matkhau1", new)
    refute Password.verify("matkhau1", "rác")
  end

  test "yêu cầu quên mật khẩu → quản trị đặt lại → mật khẩu tạm đăng nhập được, token cũ hết hạn" do
    {:ok, u} = Accounts.register(%{"username" => "quenmk", "password" => "matkhau1"})
    {:ok, admin} = Accounts.register(%{"username" => "quantri", "password" => "matkhau1"})
    token = Accounts.sign_token(u)

    # tên không tồn tại / liên lạc trống: vẫn ok, không ghi gì
    assert :ok = PasswordReset.request("khongco", "zalo 0123")
    assert :ok = PasswordReset.request("quenmk", "  ")
    assert PasswordReset.open() == []

    assert :ok = PasswordReset.request("QuenMK ", "zalo 0123")
    assert :ok = PasswordReset.request("quenmk", "fb abc")
    assert [%{uid: uid, contact: "fb abc", username: "quenmk"}] = PasswordReset.open()
    assert uid == u.id

    {:ok, "quenmk", temp} = PasswordReset.reset(u.id, admin.id)
    assert String.length(temp) == 8
    assert PasswordReset.open() == []
    assert {:ok, _} = Accounts.authenticate("quenmk", temp)
    assert {:error, :invalid} = Accounts.authenticate("quenmk", "matkhau1")
    assert {:error, _} = Accounts.verify_token(token)
  end
end

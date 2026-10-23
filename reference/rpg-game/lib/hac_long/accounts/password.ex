defmodule HacLong.Accounts.Password do
  @moduledoc """
  Băm / kiểm mật khẩu PBKDF2 bằng `:crypto.pbkdf2_hmac/5` (C trong OTP) thay cho vòng lặp Elixir của
  `pbkdf2_elixir` (DECISIONS "Đăng nhập nhanh hơn"): cùng thuật toán, số vòng, định dạng chuỗi
  `$pbkdf2-sha512$<vòng>$<muối>$<hash>` (base64 kiểu passlib), nên hash cũ và mới dùng lẫn được,
  chỉ nhanh hơn vài lần.
  """

  @digest :sha512
  @length 64
  @salt 16

  defp rounds, do: Application.get_env(:pbkdf2_elixir, :rounds, 160_000)

  def hash(password) when is_binary(password) do
    salt = :crypto.strong_rand_bytes(@salt)
    n = rounds()
    key = :crypto.pbkdf2_hmac(@digest, password, salt, n, @length)
    "$pbkdf2-sha512$#{n}$#{Pbkdf2.Base64.encode(salt)}$#{Pbkdf2.Base64.encode(key)}"
  end

  def verify(password, "$pbkdf2-" <> rest) when is_binary(password) do
    with [dg, n, salt, key] when dg in ~w(sha512 sha256 sha) <- String.split(rest, "$"),
         {n, ""} <- Integer.parse(n),
         salt = Pbkdf2.Base64.decode(salt),
         key = Pbkdf2.Base64.decode(key) do
      out = :crypto.pbkdf2_hmac(String.to_existing_atom(dg), password, salt, n, byte_size(key))
      Plug.Crypto.secure_compare(out, key)
    else
      _ -> false
    end
  end

  def verify(_, _), do: false

  @doc "Chạy một lần băm giả (không có tài khoản) để thời gian trả lời không lộ tên đăng nhập."
  def no_user_verify do
    :crypto.pbkdf2_hmac(@digest, "x", :crypto.strong_rand_bytes(@salt), rounds(), @length)
    false
  end
end

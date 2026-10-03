defmodule Mu.AccountsTest do
  use Mu.DataCase, async: true

  alias Mu.Accounts
  alias Mu.Accounts.{AccessToken, Account}

  describe "register/1" do
    test "tạo tài khoản, mật khẩu băm Argon2id" do
      assert {:ok, %Account{} = a} =
               Accounts.register(%{"username" => "Player_1", "password" => "matkhau123"})

      assert a.username == "Player_1"
      assert String.starts_with?(a.password_hash, "$argon2id$")
      refute Repo.get!(Account, a.id).password_hash =~ "matkhau123"
    end

    test "username unique không phân biệt hoa thường" do
      assert {:ok, _} = Accounts.register(%{"username" => "Alice", "password" => "matkhau123"})

      assert {:error, cs} =
               Accounts.register(%{"username" => "aLICE", "password" => "matkhau123"})

      assert %{username: ["đã có người dùng"]} = errors_on(cs)
    end

    test "luật username/mật khẩu (P6)" do
      for name <- ["ab", String.duplicate("a", 33), "có dấu", "a-b", "a b"] do
        assert {:error, cs} = Accounts.register(%{"username" => name, "password" => "matkhau123"})
        assert errors_on(cs)[:username], name
      end

      assert {:error, cs} = Accounts.register(%{"username" => "abc", "password" => "1234567"})
      assert errors_on(cs)[:password]

      assert {:error, cs} =
               Accounts.register(%{"username" => "abc", "password" => String.duplicate("x", 73)})

      assert errors_on(cs)[:password]
      assert {:ok, _} = Accounts.register(%{"username" => "abc", "password" => "12345678"})
    end

    test "email bỏ trống được, có thì unique" do
      assert {:ok, a} =
               Accounts.register(%{"username" => "e1x", "password" => "matkhau123", "email" => ""})

      assert a.email == nil

      assert {:ok, _} =
               Accounts.register(%{
                 "username" => "e2x",
                 "password" => "matkhau123",
                 "email" => "X@Mail.com"
               })

      assert {:error, cs} =
               Accounts.register(%{
                 "username" => "e3x",
                 "password" => "matkhau123",
                 "email" => "x@mail.com"
               })

      assert errors_on(cs)[:email]
    end
  end

  describe "authenticate/2" do
    setup do
      %{account: create_account("Bob_9")}
    end

    test "đúng mật khẩu, tên không phân biệt hoa thường", %{account: a} do
      assert {:ok, %{id: id}} = Accounts.authenticate("bob_9", "matkhau123")
      assert id == a.id
      assert {:ok, _} = Accounts.authenticate(" BOB_9 ", "matkhau123")
    end

    test "sai mật khẩu, không có tài khoản, kiểu sai" do
      assert {:error, :invalid} = Accounts.authenticate("bob_9", "sai")
      assert {:error, :invalid} = Accounts.authenticate("khongco", "matkhau123")
      assert {:error, :invalid} = Accounts.authenticate(nil, "matkhau123")
    end
  end

  describe "access token" do
    setup do
      %{account: create_account()}
    end

    test "≥ 256 bit, DB chỉ lưu hash, verify được", %{account: a} do
      token = Accounts.create_access_token(a)
      assert {:ok, raw} = Base.url_decode64(token, padding: false)
      assert byte_size(raw) >= 32

      [row] = Repo.all(from t in AccessToken, where: t.account_id == ^a.id)
      assert row.token_hash == :crypto.hash(:sha256, raw)
      refute row.token_hash == raw

      assert {:ok, %{id: id}} = Accounts.verify_access_token(token)
      assert id == a.id
    end

    test "hết hạn thì bị từ chối (TTL auth.accessTokenTtlSeconds)", %{account: a} do
      token = Accounts.create_access_token(a)
      [row] = Repo.all(from t in AccessToken, where: t.account_id == ^a.id)

      ttl = Mu.Game.Config.get(["auth", "accessTokenTtlSeconds"])
      assert_in_delta DateTime.diff(row.expires_at, DateTime.utc_now()), ttl, 5

      Repo.update_all(from(t in AccessToken, where: t.id == ^row.id),
        set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
      )

      assert {:error, :invalid} = Accounts.verify_access_token(token)
      assert Accounts.delete_expired_tokens() == 1
    end

    test "thu hồi được; token rác bị từ chối", %{account: a} do
      token = Accounts.create_access_token(a)
      other = Accounts.create_access_token(a)
      assert :ok = Accounts.revoke_access_token(token)
      assert {:error, :invalid} = Accounts.verify_access_token(token)
      assert {:ok, _} = Accounts.verify_access_token(other)

      assert {:error, :invalid} = Accounts.verify_access_token("không phải base64!")
      assert {:error, :invalid} = Accounts.verify_access_token(Base.url_encode64("x"))
      assert {:error, :invalid} = Accounts.verify_access_token(nil)
    end
  end
end

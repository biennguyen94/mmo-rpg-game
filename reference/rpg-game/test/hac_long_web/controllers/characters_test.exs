defmodule HacLongWeb.CharactersTest do
  # DECISIONS "Nhiều nhân vật": tối đa 5 nhân vật mỗi tài khoản, chọn nhân vật khi vào game, xóa thì đồ mất hẳn
  use HacLongWeb.ConnCase, async: false

  alias HacLong.Accounts
  alias HacLong.Game.Session

  setup do
    HacLong.RateLimit.reset()
    :ok
  end

  defp api(method, path, body, token \\ nil) do
    conn = build_conn()
    conn = if token, do: put_req_header(conn, "authorization", "Bearer " <> token), else: conn
    conn = dispatch(conn, @endpoint, method, path, body)
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp new_char(token, name, cls \\ "dk") do
    {200, %{"cid" => cid}} = api(:post, "/api/characters", %{}, token)
    {%{ok: true}, _} = Session.command(cid, %{"act" => "create", "name" => name, "cls" => cls})
    cid
  end

  test "tạo tới 5 nhân vật, vé vào đúng nhân vật của mình, xóa cần tên + mật khẩu và đồ mất hẳn" do
    {201, %{"token" => t}} =
      api(:post, "/api/register", %{username: "nhieunv", password: "matkhau1"})

    {200, %{"characters" => [], "max_characters" => max}} = api(:get, "/api/me", %{}, t)
    assert max == Accounts.max_characters()

    # nhân vật đầu nằm trên chính dòng tài khoản (như tài khoản cũ)
    acct = Accounts.authenticate("nhieunv", "matkhau1") |> elem(1)
    c1 = new_char(t, "Mot Nhan Vat")
    assert c1 == acct.id

    # bỏ dở màn tạo nhân vật: lần sau dùng lại chỗ trống, không tạo thêm
    {200, %{"cid" => c2}} = api(:post, "/api/characters", %{}, t)
    {200, %{"cid" => ^c2}} = api(:post, "/api/characters", %{}, t)

    {%{ok: true}, _} =
      Session.command(c2, %{"act" => "create", "name" => "Hai Nhan Vat", "cls" => "elf"})

    for i <- 3..max, do: new_char(t, "Nhan Vat So #{i}")

    {200, %{"characters" => list}} = api(:get, "/api/me", %{}, t)
    assert length(list) == max
    assert Enum.map(list, & &1["name"]) |> hd() == "Mot Nhan Vat"

    assert {422, %{"error" => "Mỗi tài khoản tối đa" <> _}} =
             api(:post, "/api/characters", %{}, t)

    # vé: nhân vật của mình được, của tài khoản khác thì không
    {201, %{"token" => other}} =
      api(:post, "/api/register", %{username: "nguoikhac", password: "matkhau1"})

    assert {200, %{"ticket" => _}} = api(:post, "/api/ws-ticket", %{cid: c2}, t)
    assert {403, _} = api(:post, "/api/ws-ticket", %{cid: c2}, other)

    # dòng nhân vật thêm không đăng nhập được
    child = Accounts.get_user(c2)
    assert child.account_id == acct.id
    assert {:error, :invalid} = Accounts.authenticate(child.username, "matkhau1")

    # xóa: sai tên / sai mật khẩu thì thôi; đúng thì mất hẳn, đồ không chuyển đi đâu
    Session.command(c2, %{"act" => "noop"})

    assert {422, %{"error" => "Tên nhân vật" <> _}} =
             api(
               :post,
               "/api/characters/delete",
               %{cid: c2, name: "Sai Ten", password: "matkhau1"},
               t
             )

    assert {422, %{"error" => "Mật khẩu" <> _}} =
             api(
               :post,
               "/api/characters/delete",
               %{cid: c2, name: "hai nhan vat", password: "sai"},
               t
             )

    assert {422, _} =
             api(
               :post,
               "/api/characters/delete",
               %{cid: c2, name: "Hai Nhan Vat", password: "matkhau1"},
               other
             )

    assert {200, %{"ok" => true, "characters" => left}} =
             api(
               :post,
               "/api/characters/delete",
               %{cid: c2, name: "Hai Nhan Vat", password: "matkhau1"},
               t
             )

    assert length(left) == max - 1
    assert Accounts.get_user(c2) == nil
    assert Session.get(c1).name == "Mot Nhan Vat"

    # xóa nhân vật trên dòng tài khoản: tài khoản vẫn đăng nhập được, có chỗ tạo lại
    assert {200, _} =
             api(
               :post,
               "/api/characters/delete",
               %{cid: c1, name: "Mot Nhan Vat", password: "matkhau1"},
               t
             )

    assert {:ok, _} = Accounts.authenticate("nhieunv", "matkhau1")
    assert {200, %{"cid" => ^c1}} = api(:post, "/api/characters", %{}, t)
  end
end

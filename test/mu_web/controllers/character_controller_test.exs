defmodule MuWeb.CharacterControllerTest do
  use MuWeb.ConnCase, async: false

  setup %{conn: conn} do
    account = create_account()
    %{conn: authed(conn, account), account: account}
  end

  test "tạo DK rồi liệt kê", %{conn: conn} do
    assert json_response(get(conn, "/characters"), 200) == %{"characters" => []}

    res = post(conn, "/characters", %{name: "MyKnight"})

    assert %{"character" => %{"id" => id, "name" => "MyKnight", "class" => "DK", "level" => 1}} =
             json_response(res, 201)

    assert %{"characters" => [%{"id" => ^id}]} = json_response(get(conn, "/characters"), 200)
  end

  test "lỗi: tên sai, tên trùng, quá số nhân vật, class sai", %{conn: conn} do
    assert %{"error" => "INVALID_NAME"} =
             json_response(post(conn, "/characters", %{name: "x!"}), 422)

    assert %{"error" => "INVALID_CLASS"} =
             json_response(post(conn, "/characters", %{name: "Wizard1", class: "DW"}), 422)

    other = build_conn() |> authed(create_account())
    assert json_response(post(other, "/characters", %{name: "Taken1"}), 201)

    assert %{"error" => "NAME_TAKEN"} =
             json_response(post(conn, "/characters", %{name: "TAKEN1"}), 409)

    assert json_response(post(conn, "/characters", %{name: "Mine1"}), 201)

    assert %{"error" => "CHARACTER_LIMIT"} =
             json_response(post(conn, "/characters", %{name: "Mine2"}), 409)
  end

  test "client không đặt được chỉ số (server-authoritative)", %{conn: conn} do
    res =
      post(conn, "/characters", %{
        name: "Cheater1",
        level: 99,
        strength: 999,
        zen: 1_000_000,
        hp_current: 9999
      })

    assert %{"character" => %{"id" => id, "level" => 1}} = json_response(res, 201)
    c = Mu.Repo.get!(Mu.Game.Character, id)
    assert {c.strength, c.zen, c.hp_current} == {28, 0, 185}
  end

  test "danh sách chỉ có nhân vật của mình", %{conn: conn} do
    other = build_conn() |> authed(create_account())
    post(other, "/characters", %{name: "NotMine1"})
    assert json_response(get(conn, "/characters"), 200) == %{"characters" => []}
  end
end

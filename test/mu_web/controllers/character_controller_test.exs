defmodule MuWeb.CharacterControllerTest do
  use MuWeb.ConnCase, async: false

  setup %{conn: conn} do
    account = create_account()
    %{conn: authed(conn, account), account: account}
  end

  test "tạo DK rồi liệt kê", %{conn: conn} do
    # danh sách class tạo được (P2-M2), mục đầu là mặc định; MG khóa tới cấp 20 (P3-M5)
    assert json_response(get(conn, "/characters"), 200) == %{
             "characters" => [],
             "maxCharacters" => 4,
             "classes" => [
               %{"id" => "DK", "name" => "Dark Knight", "locked" => false},
               %{"id" => "DW", "name" => "Dark Wizard", "locked" => false},
               %{"id" => "ELF", "name" => "Fairy Elf", "locked" => false},
               %{"id" => "MG", "name" => "Magic Gladiator", "locked" => true, "unlockLevel" => 20}
             ]
           }

    res = post(conn, "/characters", %{name: "MyKnight"})

    assert %{"character" => %{"id" => id, "name" => "MyKnight", "class" => "DK", "level" => 1}} =
             json_response(res, 201)

    assert %{"characters" => [%{"id" => ^id}]} = json_response(get(conn, "/characters"), 200)
  end

  test "lỗi: tên sai, tên trùng, quá số nhân vật, class sai", %{conn: conn} do
    assert %{"error" => "INVALID_NAME"} =
             json_response(post(conn, "/characters", %{name: "x!"}), 422)

    assert %{"error" => "INVALID_CLASS"} =
             json_response(post(conn, "/characters", %{name: "Gladiat1", class: "XX"}), 422)

    assert %{"error" => "CLASS_LOCKED", "message" => msg} =
             json_response(post(conn, "/characters", %{name: "Gladiat1", class: "MG"}), 409)

    assert msg =~ "cấp 20"

    other = build_conn() |> authed(create_account())
    assert json_response(post(other, "/characters", %{name: "Taken1"}), 201)

    assert %{"error" => "NAME_TAKEN"} =
             json_response(post(conn, "/characters", %{name: "TAKEN1"}), 409)

    # tối đa 4 nhân vật (P3-3)
    for i <- 1..4, do: assert(json_response(post(conn, "/characters", %{name: "Mine#{i}"}), 201))

    assert %{"error" => "CHARACTER_LIMIT"} =
             json_response(post(conn, "/characters", %{name: "Mine5"}), 409)
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
    assert %{"characters" => []} = json_response(get(conn, "/characters"), 200)
  end
end

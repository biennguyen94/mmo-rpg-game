defmodule HacLongWeb.SecurityQuestionTest do
  # DECISIONS "Câu hỏi bảo mật": đăng ký kèm câu hỏi bảo mật, quên mật khẩu thì trả lời đúng là đặt được mật khẩu mới
  # Bộ đếm giới hạn tần suất dùng chung nên không chạy song song.
  use HacLongWeb.ConnCase, async: false

  @acc HacLong.Game.Data.rules().account

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

  defp register(name, extra) do
    api(:post, "/api/register", Map.merge(%{username: name, password: "matkhau1"}, extra))
  end

  test "đăng ký kèm câu hỏi → quên mật khẩu: xem câu hỏi, trả lời đúng (không phân biệt hoa thường, khoảng trắng) là đặt mật khẩu mới" do
    {201, %{"token" => old}} = register("cauhoi1", %{question: "pet", answer: "Mèo  Mun"})

    assert {200, %{"question" => "pet"}} = api(:post, "/api/question", %{username: "CauHoi1 "})
    assert {200, %{"question" => "pet"}} = api(:get, "/api/me", %{}, old)

    # sai câu trả lời: không đổi gì
    assert {401, %{"error" => _}} =
             api(:post, "/api/recover", %{
               username: "cauhoi1",
               answer: "chó",
               password: "moi12345"
             })

    assert {200, _} = api(:post, "/api/login", %{username: "cauhoi1", password: "matkhau1"})

    # đúng (chữ hoa / khoảng trắng khác): mật khẩu mới, đăng nhập luôn, token cũ hết hiệu lực
    assert {200, %{"token" => t}} =
             api(:post, "/api/recover", %{
               username: "cauhoi1",
               answer: " mèo mun ",
               password: "moi12345"
             })

    assert {200, _} = api(:get, "/api/me", %{}, t)
    assert {401, _} = api(:get, "/api/me", %{}, old)
    assert {401, _} = api(:post, "/api/login", %{username: "cauhoi1", password: "matkhau1"})
    assert {200, _} = api(:post, "/api/login", %{username: "cauhoi1", password: "moi12345"})

    # mật khẩu mới quá ngắn: báo lỗi, không đổi
    assert {422, %{"error" => "Mật khẩu" <> _}} =
             api(:post, "/api/recover", %{username: "cauhoi1", answer: "mèo mun", password: "123"})
  end

  test "câu hỏi không hợp lệ / thiếu câu trả lời: không tạo tài khoản" do
    assert {422, %{"error" => "Câu hỏi bảo mật" <> _}} =
             register("cauhoi2", %{question: "xyz", answer: "abc"})

    assert {422, %{"error" => "Câu trả lời" <> _}} =
             register("cauhoi2", %{question: "pet", answer: " "})

    assert {201, _} = register("cauhoi2", %{question: "school", answer: "Lê Lợi"})
  end

  test "tài khoản chưa đặt câu hỏi (tài khoản cũ) / không tồn tại: không có câu hỏi, không khôi phục được" do
    {201, %{"token" => t}} = register("cauhoi3", %{})
    assert {200, %{"question" => nil}} = api(:post, "/api/question", %{username: "cauhoi3"})
    assert {200, %{"question" => nil}} = api(:post, "/api/question", %{username: "khongco"})

    assert {401, _} =
             api(:post, "/api/recover", %{username: "cauhoi3", answer: "x", password: "moi12345"})

    # đặt câu hỏi sau trong cài đặt: cần mật khẩu hiện tại
    assert {401, _} =
             api(:post, "/api/security", %{current: "sai", question: "pet", answer: "mèo"}, t)

    assert {200, %{"question" => "food"}} =
             api(
               :post,
               "/api/security",
               %{current: "matkhau1", question: "food", answer: "Phở"},
               t
             )

    assert {200, %{"token" => _}} =
             api(:post, "/api/recover", %{
               username: "cauhoi3",
               answer: "phở",
               password: "moi12345"
             })
  end

  test "trả lời sai quá nhiều lần: phải đợi (chống dò câu trả lời)" do
    {201, _} = register("cauhoi4", %{question: "pet", answer: "mèo"})

    for _ <- 1..@acc.recover_per_user,
        do:
          api(:post, "/api/recover", %{username: "cauhoi4", answer: "sai", password: "moi12345"})

    assert {429, _} =
             api(:post, "/api/recover", %{
               username: "cauhoi4",
               answer: "mèo",
               password: "moi12345"
             })
  end
end

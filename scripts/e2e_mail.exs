# CHỈ DÙNG CHO TEST E2E: gửi một mail quà (500 Zen + 3 HP potion nhỏ) cho nhân vật `name`
# qua Mu.Mail (như quản trị). Chạy ở VM riêng nên người chơi đang online chưa thấy badge ngay;
# mở lại panel Hộp thư là thấy.
#
#   mix run scripts/e2e_mail.exs <tên_nhân_vật>
require Logger
Logger.configure(level: :warning)
[name] = System.argv()

{:ok, m} =
  Mu.Mail.deliver_to_name(name, %{
    kind: "GIFT",
    title: "Quà thử nghiệm",
    body: "Tặng 500 Zen và 3 potion",
    zen: 500,
    item: "hp_potion_small",
    quantity: 3
  })

IO.puts("mail #{m.id} → #{name}")

# test cân bằng (chạy lâu): mix test --only balance
ExUnit.start(assert_receive_timeout: 1000, exclude: [:balance])
Ecto.Adapters.SQL.Sandbox.mode(HacLong.Repo, :manual)

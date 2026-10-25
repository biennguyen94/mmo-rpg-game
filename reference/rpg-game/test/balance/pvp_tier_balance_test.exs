defmodule HacLong.PvpTierBalanceTest do
  @moduledoc """
  Cân bằng lớp khi đồ sát theo mốc chuyển sinh (RULES.pvp.class_taken_by_rebirth): 4 lớp đồ giống hệt nhau mỗi mốc,
  không lớp nào thắng lệch 50% quá BALANCE_TOL (mặc định 15%). Chạy lâu (vài phút) nên không chạy cùng `mix test`:
      mix test --only balance
      BALANCE_N=48 BALANCE_TOL=0.10 mix test --only balance
  Lỗi thì chạy `TUNE=1 mix run --no-start scripts/pvp/tune.exs` để có bảng gợi ý (scripts/pvp/README.md).
  """
  use ExUnit.Case, async: false

  @moduletag :balance
  @moduletag timeout: :infinity

  Code.require_file("scripts/pvp/balance.exs")

  test "mỗi mốc chuyển sinh 0–10: không lớp nào lệch 50% quá ngưỡng" do
    n = String.to_integer(System.get_env("BALANCE_N") || "24")
    tol = String.to_float(System.get_env("BALANCE_TOL") || "0.15")
    table = PvpBalance.rules_table()

    rows =
      for k <- 0..10 do
        m = PvpBalance.measure(PvpBalance.row(table, k), k, n, 1)
        IO.puts("r#{k}: #{PvpBalance.fmt_m(m)}  lệch #{round(PvpBalance.dev(m) * 100)}%")
        {k, m}
      end

    bad = for {k, m} <- rows, PvpBalance.dev(m) > tol, do: "r#{k} (#{PvpBalance.fmt_m(m)})"
    assert bad == [], "lệch quá #{round(tol * 100)}%: #{Enum.join(bad, "; ")}"
  end
end

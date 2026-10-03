defmodule Mu.Accounts.WsTicketTest do
  use Mu.DataCase, async: true

  alias Mu.Accounts
  alias Mu.Accounts.WsTicket

  test "dùng một lần" do
    id = Ecto.UUID.generate()
    ticket = WsTicket.issue(id)
    assert {:ok, ^id} = WsTicket.consume(ticket)
    assert :error = WsTicket.consume(ticket)
  end

  test "hết hạn sau auth.wsTicketTtlSeconds" do
    ttl_ms = Mu.Game.Config.get(["auth", "wsTicketTtlSeconds"]) * 1000
    assert ttl_ms == 30_000

    t0 = System.monotonic_time(:millisecond)
    a = WsTicket.issue("a", t0)
    b = WsTicket.issue("b", t0)
    assert {:ok, "a"} = WsTicket.consume(a, t0 + ttl_ms - 1)
    assert :error = WsTicket.consume(b, t0 + ttl_ms)
    # ticket hết hạn cũng bị xóa khi thử dùng
    assert :error = WsTicket.consume(b, t0)
  end

  test "ticket sai/kiểu sai" do
    assert :error = WsTicket.consume("khongco")
    assert :error = WsTicket.consume(nil)
  end

  test "hai tiến trình dùng cùng ticket: chỉ một thành công" do
    ticket = WsTicket.issue("x")

    results =
      1..20
      |> Enum.map(fn _ -> Task.async(fn -> WsTicket.consume(ticket) end) end)
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
  end

  test "Accounts.consume_ws_ticket trả tài khoản" do
    account = create_account()
    ticket = Accounts.issue_ws_ticket(account)
    assert {:ok, %{id: id}} = Accounts.consume_ws_ticket(ticket)
    assert id == account.id
    assert :error = Accounts.consume_ws_ticket(ticket)
  end
end

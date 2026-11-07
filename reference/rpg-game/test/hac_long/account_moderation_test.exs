defmodule HacLong.AccountModerationTest do
  # DECISIONS "Nhiều nhân vật": cấm chat, khóa, chặn chat theo tài khoản (mọi nhân vật)
  use HacLong.DataCase, async: false

  alias HacLong.{Accounts, Moderation}

  defp account(name) do
    {:ok, u} = Accounts.register(%{"username" => name, "password" => "matkhau1"})
    {:ok, extra} = Accounts.character_slot(u)

    # chỗ đầu là chính dòng tài khoản (chưa có nhân vật); tạo thêm một dòng nhân vật nữa
    if extra == u.id, do: insert_char(u.id)
    {:ok, c2} = Accounts.character_slot(u)
    {u, c2}
  end

  defp insert_char(uid) do
    {_, p} =
      HacLong.Game.Commands.run(nil, %{"act" => "create", "name" => "Nv#{uid}", "cls" => "dk"})

    HacLong.Game.Characters.save!(uid, p, "TEST")
  end

  test "cấm chat / khóa một nhân vật là cả tài khoản; nhân vật tạo sau cũng bị" do
    {u, c2} = account("khoachung")
    :ok = Moderation.mute(c2, 60)
    assert Accounts.muted?(Accounts.get_user(u.id)) and Accounts.muted?(Accounts.get_user(c2))

    :ok = Moderation.ban(u.id, 60, "test")
    assert Accounts.banned?(Accounts.get_user(c2))
    insert_char(c2)
    {:ok, c3} = Accounts.character_slot(Accounts.get_user(u.id))
    assert Accounts.banned?(Accounts.get_user(c3)) and Accounts.muted?(Accounts.get_user(c3))

    # bị khóa: không lấy được vé vào nhân vật nào
    ticket = Accounts.issue_ws_ticket(Accounts.get_user(u.id), c2)
    assert Accounts.consume_ws_ticket(ticket) == :error

    :ok = Moderation.unban(c2)
    refute Accounts.banned?(Accounts.get_user(u.id))
  end

  test "chặn một nhân vật là chặn cả tài khoản đó, cho mọi nhân vật của mình; không tự chặn nhân vật cùng tài khoản" do
    {a, a2} = account("nguoichan")
    {b, b2} = account("bichan")

    assert {:error, _} = Moderation.block(a.id, a2)
    :ok = Moderation.block(a.id, b2)

    for mine <- [a.id, a2] do
      ids = Moderation.blocked_ids(mine)
      assert MapSet.member?(ids, b.id) and MapSet.member?(ids, b2)
      assert Moderation.blocked_by?(mine, b.id)
    end

    refute Moderation.blocked_by?(b.id, a.id)
    # bỏ chặn từ nhân vật khác của mình, chặn bằng nhân vật kia của họ
    :ok = Moderation.unblock(a2, b.id)
    assert Moderation.blocked_ids(a.id) == MapSet.new()
  end
end

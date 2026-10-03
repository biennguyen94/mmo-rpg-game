defmodule MuWeb.ChatChannelTest do
  @moduledoc "P2-M5 qua kênh thật: NORMAL theo map, WHISPER theo tên, kênh tắt, cấm chat, rate-limit."
  use MuWeb.ChannelCase

  alias Mu.Chat
  alias MuWeb.GameChannel
  alias Phoenix.Socket.Message

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  defp cmd(socket, payload, reset \\ true) do
    if reset, do: Mu.RateLimit.reset()
    ref = push(socket, "cmd", Map.put_new(payload, "act", "chat"))
    assert_reply ref, status, reply
    {status, reply}
  end

  # tin `chat` theo join_ref (mọi kênh trong test đẩy về cùng tiến trình test)
  defp chats(join_ref, acc \\ []) do
    receive do
      %Message{event: "chat", join_ref: ^join_ref, payload: p} -> chats(join_ref, [p | acc])
    after
      60 -> Enum.reverse(acc)
    end
  end

  setup do
    {a1, c1} = create_character()
    {a2, c2} = create_character()
    {:ok, _, s1} = join_game(a1, c1)
    {:ok, _, s2} = join_game(a2, c2)
    %{c1: c1, c2: c2, s1: s1, s2: s2}
  end

  test "NORMAL: mọi người cùng map nhận {channel, from, text, t}; chữ được làm sạch", %{
    c1: c1,
    s1: s1,
    s2: s2
  } do
    assert {:ok, _} =
             cmd(s1, %{"rid" => "c1", "channel" => "NORMAL", "text" => "  chào\n\nmọi  người "})

    from = c1.name

    for s <- [s1, s2] do
      assert [%{channel: "NORMAL", from: ^from, text: "chào mọi người", t: t}] = chats(s.join_ref)
      assert is_integer(t)
    end
  end

  test "NORMAL chỉ trong map: người ở Noria không nhận", %{c1: c1, c2: c2, s1: s1, s2: s2} do
    # đưa c2 sang Noria qua cổng (cấp 10)
    pid = Mu.Game.Session.whereis(c2.account_id)
    :sys.replace_state(pid, fn st -> put_in(st.character.level, 10) end)

    send(
      pid,
      {:map_portal, c2.id, Mu.World.Maps.portal_at(Mu.World.Maps.get("lorencia"), 15, 8)}
    )

    assert_push "map_change", %{map: %{id: "noria"}}
    _ = c1

    {:ok, _} = cmd(s1, %{"rid" => "c2", "channel" => "NORMAL", "text" => "ở Lorencia"})
    assert [_] = chats(s1.join_ref)
    assert [] = chats(s2.join_ref)
  end

  test "WHISPER: theo tên (không phân biệt hoa thường), người gửi nhận bản sao có to; offline / chính mình → INVALID_TARGET",
       %{c1: c1, c2: c2, s1: s1, s2: s2} do
    assert {:ok, _} =
             cmd(s1, %{
               "rid" => "w1",
               "channel" => "WHISPER",
               "to" => String.upcase(c2.name),
               "text" => "bí mật"
             })

    {from, to} = {c1.name, c2.name}
    assert [%{channel: "WHISPER", from: ^from, text: "bí mật"} = got] = chats(s2.join_ref)
    refute Map.has_key?(got, :to)
    assert [%{channel: "WHISPER", from: ^from, to: ^to}] = chats(s1.join_ref)

    for to <- ["KhongCo99", c1.name, nil] do
      assert {:error, %{error: "INVALID_TARGET"}} =
               cmd(s1, %{"rid" => "w-#{to}", "channel" => "WHISPER", "to" => to, "text" => "x"})
    end
  end

  test "kênh tắt / sai, tin trống", %{s1: s1} do
    for {ch, code} <- [
          {"PARTY", "FORBIDDEN"},
          {"GUILD", "FORBIDDEN"},
          {"SYSTEM", "FORBIDDEN"},
          {"XYZ", "INVALID_TARGET"}
        ] do
      assert {:error, %{error: ^code}} =
               cmd(s1, %{"rid" => "k#{ch}", "channel" => ch, "text" => "hi"})
    end

    assert {:error, %{error: "INVALID_TARGET"}} =
             cmd(s1, %{"rid" => "e1", "channel" => "NORMAL", "text" => "   "})

    assert {:error, %{error: "INVALID_TARGET"}} = cmd(s1, %{"rid" => "e2", "channel" => "NORMAL"})
  end

  test "bị cấm chat: FORBIDDEN + dòng SYSTEM cho chính người đó; unmute thì chat lại được", %{
    c1: c1,
    s1: s1,
    s2: s2
  } do
    :ok = Chat.mute(c1.name, 30)

    assert {:error, %{error: "FORBIDDEN"}} =
             cmd(s1, %{"rid" => "m1", "channel" => "NORMAL", "text" => "hi"})

    assert [%{channel: "SYSTEM", text: "Bạn đang bị cấm chat tới " <> _}] = chats(s1.join_ref)
    assert [] = chats(s2.join_ref)
    :ok = Chat.unmute(c1.name)
    assert {:ok, _} = cmd(s1, %{"rid" => "m2", "channel" => "NORMAL", "text" => "hi"})
  end

  test "SYSTEM từ server tới mọi map", %{s1: s1, s2: s2} do
    :ok = Chat.system("Bảo trì lúc 3h")

    for s <- [s1, s2],
        do:
          assert(
            [%{channel: "SYSTEM", from: "Hệ thống", text: "Bảo trì lúc 3h"}] = chats(s.join_ref)
          )
  end

  test "rate-limit: tin thứ 6 trong 5 s → RATE_LIMITED", %{s1: s1} do
    Mu.RateLimit.reset()

    results =
      for i <- 1..6,
          do:
            elem(cmd(s1, %{"rid" => "r#{i}", "channel" => "NORMAL", "text" => "#{i}"}, false), 0)

    assert results == [:ok, :ok, :ok, :ok, :ok, :error]
  end
end

defmodule HacLongWeb.ToVillageTest do
  # DECISIONS "Đưa về Làng": quản trị gỡ kẹt người chơi / bot
  use HacLongWeb.ChannelCase

  alias HacLong.{Accounts, Moderation}
  alias HacLong.Game.{Characters, Commands, Session}
  alias HacLongWeb.{ClientVersion, UserSocket}

  setup do
    HacLong.RateLimit.reset()
    :ok
  end

  defp player(user, attrs) do
    name = "Vl #{rem(System.unique_integer([:positive]), 100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    p = p |> Map.put(:tutorial, nil) |> Map.merge(attrs)
    Characters.save!(user.id, p, "TEST")
    p
  end

  defp join(user) do
    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})
    {:ok, _reply, socket} = subscribe_and_join(socket, "game", %{"v" => ClientVersion.current()})
    socket
  end

  defp admin(socket, op, payload) do
    ref = push(socket, "admin", Map.put(payload, "op", op))
    assert_reply ref, status, r
    {status, r}
  end

  test "đưa về Làng: đang đánh thì trận kết thúc như bỏ chạy, về Đá Dịch Chuyển; người thường không làm được" do
    a = create_user()
    {:ok, _} = Moderation.set_admin(a.username, true)
    player(a, %{pos: %{map: "village", x: 12, y: 14}})
    sa = join(a)

    u = create_user()
    p = player(u, %{pos: %{map: "forest_1", x: 3, y: 3}})
    # đang giữa trận
    {_, p} = HacLong.Game.Engine.start_battle(p, 0, false)
    Characters.save!(u.id, p, "TEST")
    su = join(u)
    assert %{battle: %{over: false}} = Session.get(u.id)
    gold = p.gold

    assert {:error, _} = admin(su, "to_village", %{"uid" => a.id})
    assert {:ok, %{msg: "Đã đưa " <> _}} = admin(sa, "to_village", %{"uid" => u.id})

    q = Session.get(u.id)
    assert q.pos == HacLong.World.village_spawn()
    assert q.battle == nil and q[:tower] == nil
    assert q.gold == gold
    assert {:ok, %{msg: "Đã đưa " <> _}} = admin(sa, "bots_to_village", %{})
  end

  test "quản trị tới chỗ người chơi: nhân vật của quản trị sang đúng bản đồ, ô; bản đồ riêng thì thôi" do
    a = create_user()
    {:ok, _} = Moderation.set_admin(a.username, true)
    player(a, %{pos: %{map: "village", x: 12, y: 14}})
    sa = join(a)

    u = create_user()
    player(u, %{pos: %{map: "forest_1", x: 3, y: 3}})
    _ = join(u)

    assert {:ok, %{msg: "Đã tới " <> _}} = admin(sa, "goto_player", %{"uid" => u.id})

    assert Session.get(a.id).pos == Session.get(u.id).pos and
             Session.get(a.id).pos.map == "forest_1"

    assert {:error, _} = admin(sa, "goto_player", %{"uid" => a.id})

    # người thường không dùng được
    su = join(create_user() |> tap(&player(&1, %{})))
    assert {:error, _} = admin(su, "goto_player", %{"uid" => a.id})
  end
end

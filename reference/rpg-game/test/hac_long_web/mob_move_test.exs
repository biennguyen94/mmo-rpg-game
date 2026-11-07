defmodule HacLongWeb.MobMoveTest do
  # DECISIONS "Quản trị: bật / tắt quái di chuyển": một công tắc cho cả server, lưu qua admin_log
  use HacLongWeb.ChannelCase

  alias HacLong.{Accounts, Moderation}
  alias HacLong.Game.{Characters, Commands}
  alias HacLong.World.{MapServer, MobMove}
  alias HacLongWeb.{ClientVersion, UserSocket}

  @map "swamp_1"

  setup do
    HacLong.RateLimit.reset()
    on_exit(fn -> MobMove.set(true) end)
    :ok
  end

  defp join(user) do
    {_, p} =
      Commands.run(nil, %{
        "act" => "create",
        "name" => "Mm #{rem(System.unique_integer([:positive]), 100_000)}",
        "cls" => "elf"
      })

    Characters.save!(
      user.id,
      Map.merge(p, %{tutorial: nil, pos: %{map: "village", x: 12, y: 14}}),
      "TEST"
    )

    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})
    {:ok, _reply, socket} = subscribe_and_join(socket, "game", %{"v" => ClientVersion.current()})
    socket
  end

  defp admin(socket, op, payload \\ %{}) do
    ref = push(socket, "admin", Map.put(payload, "op", op))
    assert_reply ref, status, r
    {status, r}
  end

  defp positions do
    MapServer.snapshot(@map).monsters |> Map.new(&{&1.id, {&1.x, &1.y}})
  end

  # chạy `n` nhịp lang thang ngay (test tắt hẹn giờ :wander_ms)
  defp tick(n) do
    [{pid, _}] = Registry.lookup(HacLong.World.Registry, @map)
    for _ <- 1..n, do: send(pid, :wander)
    _ = MapServer.snapshot(@map)
  end

  test "quản trị tắt: quái đứng yên; bật lại: đi tiếp; khởi động lại vẫn nhớ; người thường không đổi được" do
    a = create_user()
    {:ok, _} = Moderation.set_admin(a.username, true)
    sa = join(a)
    su = join(create_user())

    assert {:ok, %{mob_move: true}} = admin(sa, "flags")
    assert {:error, _} = admin(su, "mob_move", %{"on" => false})

    assert {:ok, %{mob_move: false}} = admin(sa, "mob_move", %{"on" => false})
    assert {:ok, %{mob_move: false}} = admin(sa, "flags")
    before = positions()
    assert map_size(before) > 0
    tick(30)
    now = positions()
    assert Enum.all?(before, fn {id, pos} -> now[id] in [nil, pos] end)

    # như vừa khởi động lại: đọc từ admin_log
    :persistent_term.erase({MobMove, :on})
    refute MobMove.on?()

    assert {:ok, %{mob_move: true}} = admin(sa, "mob_move", %{"on" => true})
    tick(30)
    now = positions()
    assert Enum.any?(before, fn {id, pos} -> now[id] not in [nil, pos] end)
  end
end

defmodule HacLongWeb.AutoHuntChannelTest do
  @moduledoc "Phase 4 (B-31): tự đánh chạy ở server khi còn tab mở, đóng tab là tắt."
  use HacLongWeb.ChannelCase

  alias HacLong.Accounts
  alias HacLong.Game.{Characters, Commands, Session}
  alias HacLong.World.MapServer
  alias HacLongWeb.UserSocket

  @map "forest_1"

  defp join_game(user) do
    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})

    {:ok, _reply, socket} =
      subscribe_and_join(socket, "game", %{"v" => HacLongWeb.ClientVersion.current()})

    socket
  end

  defp player_at(user, pos) do
    name = "Săn #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    p = p |> Map.put(:tutorial, nil) |> Map.put(:pos, pos) |> Map.put(:inv, %{"potion_s" => 20})
    {p, _} = HacLong.Game.Achievements.check(p)
    Characters.save!(user.id, p)
    p
  end

  defp wait_until(fun, n \\ 100) do
    cond do
      fun.() -> true
      n == 0 -> false
      true -> Process.sleep(100) && wait_until(fun, n - 1)
    end
  end

  test "bật tự đánh: server tự đi tới quái, đánh, rời trận; đóng tab thì tắt" do
    MapServer.clear_monsters(@map)
    user = create_user()
    player_at(user, %{map: @map, x: 13, y: 16})
    socket = join_game(user)
    MapServer.put_monster(@map, "bat", {13, 14})

    ref = push(socket, "cmd", %{"act" => "auto", "on" => true, "target" => "bat", "hp" => 30})
    assert_reply ref, :ok, %{ok: true, player: %{auto: %{target: "bat"}, view: %{autoMap: m}}}
    assert m.ok and Enum.any?(m.kinds, &(&1.id == "bat"))

    # hạ được dơi và rời bảng kết quả mà client không gửi thêm lệnh nào
    assert wait_until(fn ->
             p = Session.get(user.id)
             p.kills >= 1 and p.battle == nil
           end)

    assert Session.get(user.id).auto.target == "bat"

    # cài đặt tự đánh không ghi database
    refute Map.has_key?(Characters.load(user.id), :auto)

    Process.unlink(socket.channel_pid)
    close(socket)
    assert wait_until(fn -> not Map.has_key?(Session.get(user.id), :auto) end)
  end

  test "tắt bằng lệnh; bản đồ không có quái thì không bật được" do
    user = create_user()
    player_at(user, %{map: "village", x: 10, y: 10})
    socket = join_game(user)

    ref = push(socket, "cmd", %{"act" => "auto", "on" => true, "target" => "level"})
    assert_reply ref, :ok, %{ok: false, msg: "Bản đồ này không tự đánh được."}

    ref = push(socket, "cmd", %{"act" => "auto", "on" => false})
    assert_reply ref, :ok, %{ok: true}
  end
end

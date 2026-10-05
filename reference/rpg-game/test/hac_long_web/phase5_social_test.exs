defmodule HacLongWeb.Phase5SocialTest do
  @moduledoc "Phase 5: giao dịch tự hủy (E5), hộp thư (H12), danh sách người online (K10)."
  use HacLongWeb.ChannelCase

  import Ecto.Query

  alias HacLong.{Accounts, Audit, Mailbox, Moderation, Repo, Trade}
  alias HacLong.Game.{Characters, Commands, Session}
  alias HacLong.World.Maps
  alias HacLongWeb.{ClientVersion, UserSocket}

  setup do
    HacLong.RateLimit.reset()
    Trade.reset()
    :ok
  end

  defp player(user, pos, attrs \\ %{}) do
    name = "Xh #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "elf"})
    p = p |> Map.put(:tutorial, nil) |> Map.put(:pos, pos) |> Map.merge(attrs)
    {p, _} = HacLong.Game.Achievements.check(p)
    Characters.save!(user.id, p, "TEST")
    p
  end

  defp join(user) do
    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})
    {:ok, _reply, socket} = subscribe_and_join(socket, "game", %{"v" => ClientVersion.current()})
    socket
  end

  defp top(socket, op, payload \\ %{}) do
    ref = push(socket, "trade", Map.put(payload, "op", op))
    assert_reply ref, status, r
    {status, r}
  end

  defp cmd(socket, payload) do
    ref = push(socket, "cmd", payload)
    assert_reply ref, :ok, reply

    if reply[:msg] == "Thao tác quá nhanh." do
      Process.sleep(100)
      cmd(socket, payload)
    else
      reply
    end
  end

  describe "giao dịch tự hủy (E5)" do
    test "đứng xa / khác bản đồ thì không mời được" do
      ua = create_user()
      ub = create_user()
      uc = create_user()
      v = Maps.get("village")

      {fx, fy} =
        Enum.find(for(x <- 0..(v.width - 1), y <- 0..(v.height - 1), do: {x, y}), fn {x, y} ->
          Maps.walkable?(v, x, y) and max(abs(x - 12), abs(y - 14)) > 10 and
            !Maps.portal_at(v, x, y)
        end)

      player(ua, %{map: "village", x: 12, y: 14})
      player(ub, %{map: "village", x: fx, y: fy})
      player(uc, %{map: "forest_1", x: 2, y: 2})
      sa = join(ua)
      _ = join(ub)
      _ = join(uc)

      assert {:error, %{msg: "Hãy đứng gần" <> _}} = top(sa, "request", %{"uid" => ub.id})
      assert {:error, %{msg: "Hãy đứng gần" <> _}} = top(sa, "request", %{"uid" => uc.id})
    end

    test "lời mời hết hạn, giao dịch mở quá lâu, một bên rời bản đồ: tự hủy" do
      ua = create_user()
      ub = create_user()
      player(ua, %{map: "village", x: 12, y: 14})
      player(ub, %{map: "village", x: 13, y: 14})
      sa = join(ua)
      sb = join(ub)

      # lời mời hết hạn
      {:ok, _} = top(sa, "request", %{"uid" => ub.id})
      id = :sys.get_state(Trade).of[ua.id]
      send(Trade, {:expire, id, :pending})
      assert Trade.of(ua.id) == nil
      assert_push "notice", %{msg: "Lời mời giao dịch đã hết hạn."}

      # mở quá lâu
      {:ok, _} = top(sa, "request", %{"uid" => ub.id})
      {:ok, %{trade: %{status: :open}}} = top(sb, "accept")
      id = :sys.get_state(Trade).of[ua.id]
      send(Trade, {:expire, id, :pending})
      assert Trade.of(ua.id).status == :open
      send(Trade, {:expire, id, :open})
      assert Trade.of(ua.id) == nil

      # rời bản đồ
      {:ok, _} = top(sa, "request", %{"uid" => ub.id})
      {:ok, _} = top(sb, "accept")
      :ok = Trade.left(ub.id, "đã rời bản đồ")
      assert Trade.of(ua.id) == nil
    end

    test "Session báo rời bản đồ: đi qua cổng thì giao dịch hủy" do
      ua = create_user()
      ub = create_user()

      # đứng cạnh cổng Làng → Nhà ở (vị trí cổng lấy từ dữ liệu bản đồ)
      v = Maps.get("village")
      {x, y} = Enum.find(v.portals, &(&1.to == "home")).at

      {dir, ax, ay} =
        Enum.find(
          [{"left", x + 1, y}, {"right", x - 1, y}, {"up", x, y + 1}, {"down", x, y - 1}],
          fn {_, ax, ay} ->
            Maps.walkable?(v, ax, ay)
          end
        )

      player(ua, %{map: "village", x: ax, y: ay})
      player(ub, %{map: "village", x: ax, y: ay})
      sa = join(ua)
      sb = join(ub)
      {:ok, _} = top(sa, "request", %{"uid" => ub.id})
      {:ok, _} = top(sb, "accept")
      r = cmd(sa, %{"act" => "move", "dir" => dir})
      assert r.player.pos.map != "village"
      Process.sleep(50)
      assert Trade.of(ub.id) == nil
    end
  end

  describe "hộp thư (H12)" do
    test "nhận tất cả trong một transaction, xóa thư đã đọc, thư hết hạn (trừ thư còn quà)" do
      u = create_user()
      player(u, %{map: "village", x: 12, y: 14}, %{gold: 100})
      s = join(u)

      :ok = Mailbox.send(u.id, %{subject: "A", gold: 50})
      :ok = Mailbox.send(u.id, %{subject: "B", gold: 25, items: %{"potion_s" => 2}})
      :ok = Mailbox.send(u.id, %{subject: "C"})

      r = cmd(s, %{"act" => "mail_claim_all"})
      assert r.ok and r.msg =~ "Mở 3 thư"
      assert Session.get(u.id).gold == 175
      assert Session.get(u.id).inv["potion_s"] >= 2
      assert %{ok: false} = cmd(s, %{"act" => "mail_claim_all"})

      ref = push(s, "mail", %{"op" => "delete_read"})
      assert_reply ref, :ok, %{mails: [], unread: 0}

      # thư cũ: không quà / đã đọc thì xóa, còn quà chưa nhận thì giữ
      :ok = Mailbox.send(u.id, %{subject: "cu khong qua"})
      :ok = Mailbox.send(u.id, %{subject: "cu co qua", gold: 10})
      :ok = Mailbox.send(u.id, %{subject: "moi"})

      old =
        DateTime.utc_now() |> DateTime.add(-31 * 86_400, :second) |> DateTime.truncate(:second)

      Repo.update_all(from(m in "mails", where: m.user_id == ^u.id and like(m.subject, "cu%")),
        set: [inserted_at: old]
      )

      assert Enum.map(Mailbox.list(u.id), & &1.subject) |> Enum.sort() == ["cu co qua", "moi"]
      assert Enum.filter(Audit.run().problems, &(&1[:user_id] == u.id)) == []
    end
  end

  test "quản trị xem người đang online (K10)" do
    admin = create_user()
    {:ok, _} = Moderation.set_admin(admin.username, true)
    pa = player(admin, %{map: "village", x: 12, y: 14})
    u = create_user()
    pu = player(u, %{map: "forest_1", x: 3, y: 3})
    sa = join(admin)
    _ = join(u)

    ref = push(sa, "admin", %{"op" => "online"})
    assert_reply ref, :ok, %{online: %{count: n, players: players}}
    names = Enum.map(players, & &1.name)
    assert n >= 2 and pa.name in names and pu.name in names
    assert Enum.find(players, &(&1.name == pu.name)).map == "forest_1"
  end
end

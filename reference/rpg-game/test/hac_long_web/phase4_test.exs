defmodule HacLongWeb.Phase4Test do
  @moduledoc "Phase 4 qua Session + database: Tủ Đồ lưu / nạp, nhật ký đồ hiếm, đối soát; trần vàng thư quản trị."
  use HacLongWeb.ChannelCase

  import Ecto.Query

  alias HacLong.{Accounts, Audit, Moderation, Repo}
  alias HacLong.Game.{Characters, Commands, Gear, Session}
  alias HacLongWeb.{ClientVersion, UserSocket}

  setup do
    HacLong.RateLimit.reset()
    :ok
  end

  defp player(user, attrs) do
    name = "Bon #{System.unique_integer([:positive]) |> rem(1_000_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    p = p |> Map.put(:tutorial, nil) |> Map.merge(attrs)
    {p, _} = HacLong.Game.Achievements.check(p)
    Characters.save!(user.id, p, "TEST")
    p
  end

  defp join(user) do
    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})
    {:ok, reply, socket} = subscribe_and_join(socket, "game", %{"v" => ClientVersion.current()})
    {reply, socket}
  end

  test "cất đồ vào tủ, vứt đồ: lưu / nạp lại đúng; nhật ký đồ hiếm đúng; audit sạch" do
    u = create_user()
    g = Gear.new("dagger", 2, %{str: 2})
    junk = Gear.new("dagger", 1, %{agi: 1})

    player(u, %{
      gear: [g, junk],
      inv: %{"herb" => 3, "jewel_life" => 1},
      pos: %{map: "home", x: 6, y: 1}
    })

    {_, _} = join(u)

    {%{ok: true}, _} = Session.command(u.id, %{"act" => "store", "id" => g.uid})
    {%{ok: true}, _} = Session.command(u.id, %{"act" => "store", "id" => "herb", "n" => 2})
    {%{ok: true}, _} = Session.command(u.id, %{"act" => "discard", "id" => junk.uid})

    # ép ghi ngay (không chờ lần lưu định kỳ); Session.get đồng bộ nên :flush đã xử lý xong
    [{pid, _}] = Registry.lookup(HacLong.Game.Registry, u.id)
    send(pid, :flush)
    _ = Session.get(u.id)

    p = Characters.load(u.id)
    assert Gear.stored?(p, g.uid)
    assert p.storage.inv == %{"herb" => 2} and p.inv["herb"] == 1

    logs =
      Repo.all(
        from l in "gear_log", where: l.user_id == ^u.id, select: {l.uid, l.action, l.reason}
      )

    # cất vào tủ không phải "ra" khỏi nhân vật; vứt đồ ghi "out" lý do DISCARD
    assert Enum.sort(logs) ==
             Enum.sort([
               {g.uid, "in", "TEST"},
               {junk.uid, "in", "TEST"},
               {junk.uid, "out", "DISCARD"}
             ])

    refute Gear.find(p, junk.uid)
    assert Enum.filter(Audit.run().problems, &(&1[:user_id] == u.id)) == []
  end

  test "thư quản trị vượt trần vàng / EXP bị từ chối" do
    admin = create_user()
    {:ok, _} = Moderation.set_admin(admin.username, true)
    player(admin, %{})
    target = create_user()
    player(target, %{})
    {_, sa} = join(admin)
    cap = HacLong.Game.Data.rules().mail

    ref =
      push(sa, "admin", %{
        "op" => "gift",
        "uid" => target.id,
        "subject" => "x",
        "gold" => cap.max_gold + 1
      })

    assert_reply ref, :error, %{msg: msg}
    assert msg =~ "tối đa"

    ref =
      push(sa, "admin", %{
        "op" => "gift",
        "uid" => target.id,
        "subject" => "x",
        "xp" => cap.max_xp + 1
      })

    assert_reply ref, :error, _

    ref =
      push(sa, "admin", %{
        "op" => "gift",
        "uid" => target.id,
        "subject" => "x",
        "gold" => cap.max_gold
      })

    assert_reply ref, :ok, %{sent: 1}
  end
end

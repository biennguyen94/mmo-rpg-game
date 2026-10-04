defmodule HacLongWeb.Batch2Test do
  @moduledoc """
  Đợt 2 tích hợp từ MU Web (docs/INTEGRATION_PLAN.md, FEATURE_CATALOG E1 / E4 / K1 / K2):
  nhật ký vàng + đồ hiếm và đối soát, giao dịch trực tiếp một transaction, vai trò
  player/mod/admin, lệnh quản trị trên nhân vật, nhật ký quản trị.
  """
  use HacLongWeb.ChannelCase

  import Ecto.Query

  alias HacLong.{Accounts, Audit, Moderation, Repo, Trade}
  alias HacLong.Game.{Characters, Commands, Engine, Session}
  alias HacLongWeb.{ClientVersion, UserSocket}

  @smith %{map: "village", x: 8, y: 11}

  setup do
    HacLong.RateLimit.reset()
    Trade.reset()
    :ok
  end

  defp player(user, attrs \\ %{}) do
    name = "Hai #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "mg"})
    p = p |> Map.put(:tutorial, nil) |> Map.put(:pos, %{map: "village", x: 12, y: 14})
    p = Map.merge(p, attrs)
    {p, _} = HacLong.Game.Achievements.check(p)
    Characters.save!(user.id, p, "TEST")
    p
  end

  defp join(user) do
    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})
    {:ok, reply, socket} = subscribe_and_join(socket, "game", %{"v" => ClientVersion.current()})
    {reply, socket}
  end

  defp gold_log(uid) do
    Repo.all(
      from l in "gold_log",
        where: l.user_id == ^uid,
        order_by: [l.inserted_at, l.id],
        select: %{delta: l.delta, balance: l.balance, reason: l.reason, ref: l.ref}
    )
  end

  defp gear_log(uid) do
    Repo.all(
      from l in "gear_log",
        where: l.user_id == ^uid,
        order_by: l.id,
        select: {l.uid, l.action, l.reason}
    )
  end

  defp mine(problems, uids), do: Enum.filter(problems, &(&1[:user_id] in uids))

  defp wait_for(get, ok?, tries \\ 50) do
    v = get.()

    cond do
      ok?.(v) -> v
      tries == 0 -> flunk("đợi mãi không thấy: #{inspect(v, limit: 5)}")
      true -> Process.sleep(50) && wait_for(get, ok?, tries - 1)
    end
  end

  describe "E1 nhật ký vàng và đồ hiếm" do
    test "mỗi lần lưu ghi đúng lý do; tổng nhật ký khớp vàng; đối soát bắt chỗ lệch" do
      u = create_user()
      p = player(u, %{gold: 100, inv: %{"dagger" => 1}, pos: @smith})
      assert [%{delta: 100, balance: 100, reason: "TEST"}] = gold_log(u.id)

      {%{ok: true}, p2} = Session.command(u.id, %{"act" => "sell", "id" => "dagger"})
      assert p2.gold > p.gold

      assert [_, %{reason: "SELL", ref: "dagger", balance: b}] = gold_log(u.id)
      assert b == p2.gold
      assert mine(Audit.run().problems, [u.id]) == []

      # sửa thẳng database (không qua Characters.save!): đối soát báo lệch
      Repo.query!("UPDATE characters SET gold = gold + 7 WHERE user_id = $1", [u.id])
      assert [%{kind: "gold_mismatch"}] = mine(Audit.run().problems, [u.id])
    end

    test "đồ hiếm vào/ra có nhật ký; cùng uid ở hai nhân vật bị báo trùng" do
      g = %{
        uid: "#AUD#{System.unique_integer([:positive])}",
        base: "club",
        rarity: 1,
        bonus: %{str: 1}
      }

      ua = create_user()
      player(ua, %{gear: [g]})
      assert [{_, "in", "TEST"}] = gear_log(ua.id)

      ub = create_user()
      player(ub, %{gear: [g]})
      problems = Audit.run().problems
      assert Enum.any?(problems, &(&1.kind == "gear_duplicate" and &1.uid == g.uid))

      # dòng nhật ký cuối của uid là "in" cho B, nên A bị báo đồ không khớp nhật ký
      assert [%{kind: "gear_unlogged"}] = mine(problems, [ua.id])

      Characters.delete!(ua.id)
      assert [{_, "in", _}, {_, "out", "DELETE"}] = gear_log(ua.id)
      assert List.last(gold_log(ua.id)).reason == "DELETE"
    end

    test "dọn nhật ký cũ gộp vàng thành dòng CARRY, tổng vẫn khớp" do
      u = create_user()
      p = player(u, %{gold: 300})
      Characters.save!(u.id, %{p | gold: 250}, "SPEND")

      Repo.query!(
        "UPDATE gold_log SET inserted_at = now() - interval '200 days' WHERE user_id = $1",
        [u.id]
      )

      Characters.save!(u.id, %{p | gold: 400}, "LOOT")
      assert %{gold: 2} = Audit.prune(180)
      assert [%{reason: "CARRY", delta: 250}, %{reason: "LOOT", delta: 150}] = gold_log(u.id)
      assert mine(Audit.run().problems, [u.id]) == []

      # dọn lần nữa (cả dòng CARRY cũ) vẫn khớp
      Repo.query!(
        "UPDATE gold_log SET inserted_at = now() - interval '200 days' WHERE user_id = $1",
        [u.id]
      )

      Audit.prune(180)
      assert [%{reason: "CARRY", delta: 400}] = gold_log(u.id)
      assert mine(Audit.run().problems, [u.id]) == []
    end
  end

  describe "E4 giao dịch một transaction" do
    test "đổi xong: cả hai lưu cùng mã TRADE, nhật ký vàng và đồ hiếm khớp" do
      sword = %{
        uid: "#TX#{System.unique_integer([:positive])}",
        base: "club",
        rarity: 2,
        bonus: %{str: 3}
      }

      ua = create_user()
      pa = player(ua, %{gold: 500, gear: [sword]})
      ub = create_user()
      pb = player(ub, %{gold: 1000})
      {_, _sa} = join(ua)
      {_, _sb} = join(ub)

      :ok = Trade.request(ua.id, pa.name, ub.id)
      :ok = Trade.accept(ub.id, pb.name)
      {:ok, oa} = HacLong.Game.TradeOffer.parse(pa, %{"gear" => [sword.uid], "gold" => 100})
      {:ok, ob} = HacLong.Game.TradeOffer.parse(pb, %{"gold" => 300})
      :ok = Trade.offer(ua.id, oa)
      :ok = Trade.offer(ub.id, ob)
      :ok = Trade.ready(ua.id)
      :ok = Trade.ready(ub.id)
      wait_for(fn -> Trade.of(ua.id) end, &is_nil/1)

      assert Characters.load(ua.id).gold == 700 and Characters.load(ub.id).gold == 800
      assert Session.get(ua.id).gold == 700
      [%{reason: "TRADE", ref: ref, delta: 200}] = Enum.drop(gold_log(ua.id), 1)
      assert [%{reason: "TRADE", ref: ^ref, delta: -200}] = Enum.drop(gold_log(ub.id), 1)
      assert {sword.uid, "out", "TRADE"} in gear_log(ua.id)
      assert {sword.uid, "in", "TRADE"} in gear_log(ub.id)
      assert mine(Audit.run().problems, [ua.id, ub.id]) == []
    end

    test "một bên thiếu: không ai đổi gì, không có nhật ký TRADE" do
      ua = create_user()
      pa = player(ua, %{gold: 500})
      ub = create_user()
      pb = player(ub, %{gold: 500})
      {_, _} = join(ua)
      {_, _} = join(ub)

      :ok = Trade.request(ua.id, pa.name, ub.id)
      :ok = Trade.accept(ub.id, pb.name)
      {:ok, oa} = HacLong.Game.TradeOffer.parse(pa, %{"gold" => 100})
      {:ok, ob} = HacLong.Game.TradeOffer.parse(pb, %{"gold" => 400})
      :ok = Trade.offer(ua.id, oa)
      :ok = Trade.offer(ub.id, ob)

      # B tiêu vàng trước khi đổi
      :sys.replace_state({:via, Registry, {HacLong.Game.Registry, ub.id}}, fn st ->
        put_in(st.player.gold, 10)
      end)

      :ok = Trade.ready(ua.id)
      :ok = Trade.ready(ub.id)
      wait_for(fn -> Trade.of(ua.id) end, &(&1 && &1.status == :open))

      assert Session.get(ua.id).gold == 500 and Characters.load(ua.id).gold == 500
      refute Enum.any?(gold_log(ua.id) ++ gold_log(ub.id), &(&1.reason == "TRADE"))
    end

    test "Session đang bị giữ: lệnh khác xếp hàng, chạy sau khi nhả; nhả muộn bị bỏ qua" do
      u = create_user()
      player(u, %{gold: 50})
      {:ok, ref, p} = Session.hold(u.id)
      task = Task.async(fn -> Session.command(u.id, %{"act" => "title_set"}) end)
      refute Task.yield(task, 150)

      :ok = Session.release(u.id, ref, %{p | gold: 60})
      assert {_, %{gold: 60}} = Task.await(task)
      assert :ok = Session.release(u.id, ref, nil)
      assert Session.get(u.id).gold == 60
    end
  end

  describe "K1/K2 vai trò, lệnh quản trị, nhật ký quản trị" do
    defp adm(socket, op, payload \\ %{}) do
      ref = push(socket, "admin", Map.put(payload, "op", op))
      assert_reply ref, status, r
      {status, r}
    end

    test "mod chỉ dùng lệnh kiểm duyệt; admin sửa nhân vật, có nhật ký" do
      target = create_user()
      tp = player(target, %{gold: 100})

      mod = create_user()
      {:ok, _} = Moderation.set_role(mod.username, "mod")
      assert {:error, _} = Moderation.set_role(mod.username, "vua")
      player(mod)
      {reply, smod} = join(mod)
      assert reply.admin and reply.role == "mod"
      assert {:ok, %{user: %{id: tid}}} = adm(smod, "lookup", %{"name" => tp.name})
      assert tid == target.id

      assert {:error, %{msg: "Cần quyền quản trị viên."}} =
               adm(smod, "give_xp", %{"uid" => target.id, "xp" => 10})

      assert {:error, _} = adm(smod, "ban", %{"uid" => target.id})

      admin = create_user()
      {:ok, _} = Moderation.set_admin(admin.username, true)
      player(admin)
      {reply, sa} = join(admin)
      assert reply.role == "admin"

      assert {:ok, %{msg: msg}} = adm(sa, "set_level", %{"uid" => target.id, "level" => 50})
      assert msg =~ "cấp 50"
      t = Session.get(target.id)
      assert t.level == 50 and t.points == tp.points + 49 * Engine.points_per_level(tp.cls)

      assert {:ok, _} = adm(sa, "add_gold", %{"uid" => target.id, "amount" => 1_000_000})
      assert {:ok, _} = adm(sa, "add_gold", %{"uid" => target.id, "amount" => -5_000_000})
      assert Session.get(target.id).gold == 0

      # đồ không bán, không rơi thường (relic, dragonshield) vẫn tặng được, kèm cấp nâng
      assert {:ok, _} =
               adm(sa, "give_item", %{
                 "uid" => target.id,
                 "id" => "relic",
                 "count" => 1,
                 "up" => 5
               })

      assert {:error, _} = adm(sa, "give_item", %{"uid" => target.id, "id" => "xyz"})

      assert {:ok, %{msg: gmsg}} =
               adm(sa, "give_gear", %{
                 "uid" => target.id,
                 "base" => "dragonshield",
                 "rarity" => 3,
                 "bonus" => %{"str" => 9, "vit" => 9, "ene" => 9},
                 "up" => 5
               })

      assert gmsg =~ "Đã tặng"
      t = Session.get(target.id)
      # đồ +N là món riêng (Đợt 3, cấp nâng theo từng món)
      assert [
               %{base: "relic", rarity: 0, uid: ruid},
               %{base: "dragonshield", rarity: 3, bonus: %{str: 9}, uid: guid}
             ] =
               t.gear

      assert t.upgrades[ruid] == 5 and t.upgrades[guid] == 5

      assert {:ok, _} = adm(sa, "add_stats", %{"uid" => target.id, "str" => 100})
      assert Session.get(target.id).stats.str == tp.stats.str + 100

      # đã lưu database, nhật ký vàng/đồ ghi lý do ADMIN kèm mã dòng admin_log
      assert Characters.load(target.id).level == 50
      assert Enum.any?(gold_log(target.id), &(&1.reason == "ADMIN" and &1.ref =~ "admin:"))
      assert {guid, "in", "ADMIN"} in gear_log(target.id)

      assert {:ok, %{log: log}} = adm(sa, "admin_log", %{"uid" => target.id})
      ops = Enum.map(log, & &1.op)
      assert "set_level" in ops and "give_gear" in ops
      assert Enum.find(log, &(&1.op == "give_item" and &1.result =~ "lỗi"))
      assert Enum.all?(log, &(&1.admin == admin.username))

      assert {:ok, %{log: [%{balance: 0} | _]}} = adm(sa, "gold_log", %{"uid" => target.id})
      assert {:ok, %{audit: %{problems: problems}}} = adm(sa, "audit")
      assert mine(problems, [target.id]) == []

      # lệnh cũ (thông báo) cũng có nhật ký
      assert {:ok, _} = adm(sa, "announce", %{"text" => "Bảo trì"})
      assert {:ok, %{log: [%{op: "announce", result: "ok"} | _]}} = adm(sa, "admin_log")

      # từ dòng lệnh server (bin/hac_long rpc)
      assert {:ok, "Đã hồi đầy máu và MP."} = HacLong.Admin.console(tp.name, "heal")
      assert {:error, _} = HacLong.Admin.console("khong-co-ai", "heal")
      assert [%{admin: "console", op: "heal"} | _] = HacLong.Admin.recent(1)
    end

    test "người chơi thường không dùng được" do
      u = create_user()
      player(u)
      {reply, s} = join(u)
      assert reply.admin == false and reply.role == "player"
      assert {:error, %{msg: "Không có quyền."}} = adm(s, "audit")
    end
  end
end

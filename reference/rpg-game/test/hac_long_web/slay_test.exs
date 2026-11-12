defmodule HacLongWeb.SlayTest do
  @moduledoc "Đồ sát: không cần đồng ý, luân phiên lượt, thua / bỏ chạy là chết, vàng chuyển cho người thắng."
  use HacLongWeb.ChannelCase

  import Ecto.Query

  alias HacLong.{Accounts, Audit, Repo, Slay}
  alias HacLong.Game.{Characters, Commands, Session}
  alias HacLong.World.Maps
  alias HacLongWeb.{ClientVersion, UserSocket}

  setup do
    HacLong.RateLimit.reset()
    Slay.reset()
    :ok
  end

  # chỗ đứng hợp lệ ở bản đồ chung không an toàn
  defp field do
    [p | _] = Maps.get("forest_1").portals
    {x, y} = p.at
    %{map: "forest_1", x: x, y: y - 1}
  end

  defp player(user, attrs, pos \\ nil) do
    name = "Ds #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    p = p |> Map.put(:tutorial, nil) |> Map.put(:pos, pos || field()) |> Map.merge(attrs)
    {p, _} = HacLong.Game.Achievements.check(p)
    Characters.save!(user.id, p, "TEST")
    p
  end

  defp join(user) do
    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})
    {:ok, _reply, socket} = subscribe_and_join(socket, "game", %{"v" => ClientVersion.current()})
    socket
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

  defp strong, do: %{level: 40, stats: %{str: 400, agi: 100, vit: 300, ene: 20}}

  # chờ trận của `uid` được chốt (settle chạy ở tiến trình riêng)
  defp back_home(uid, map, n \\ 100) do
    p = Session.get(uid)
    if p.pos.map == map or n == 0, do: p, else: Process.sleep(20) && back_home(uid, map, n - 1)
  end

  defp settled(uid, n \\ 250) do
    p = Session.get(uid)

    cond do
      p.battle && p.battle.over -> p
      n == 0 -> flunk("trận đồ sát chưa được chốt")
      true -> Process.sleep(20) && settled(uid, n - 1)
    end
  end

  test "điều kiện: cấp, vùng an toàn, khác bản đồ, đang đánh" do
    {_, a} = Commands.run(nil, %{"act" => "create", "name" => "A", "cls" => "dk"})
    a = %{a | level: 20, pos: field()}
    b = %{a | name: "B"}

    assert Slay.check(a, b) == :ok
    assert {:error, "Cần đạt cấp 10" <> _} = Slay.check(%{a | level: 5}, b)
    assert {:error, "B dưới cấp 10" <> _} = Slay.check(a, %{b | level: 9})
    village = %{map: "village", x: 12, y: 14}

    assert {:error, "Đây là vùng an toàn" <> _} =
             Slay.check(%{a | pos: village}, %{b | pos: village})

    assert {:error, "Hãy đến cùng bản đồ" <> _} = Slay.check(a, %{b | pos: village})
    assert {:error, "Bạn đang trong trận đấu."} = Slay.check(%{a | battle: %{}}, b)

    # người bị đánh đang đánh quái vẫn đồ sát được; đang trong trận đồ sát khác thì không
    assert Slay.check(a, %{b | battle: %{over: false, encounter: %{map: "forest_1", mid: 1}}}) ==
             :ok

    assert {:error, "B đang bị đồ sát" <> _} =
             Slay.check(a, %{b | battle: %{over: false, encounter: %{slay: 7}}})
  end

  test "đồ sát người đang đánh quái: trận đánh quái bị cắt ngang, vào trận đồ sát ngay" do
    ua = create_user()
    ub = create_user()
    player(ua, strong())
    pb = player(ub, %{level: 12})

    {_, fight} =
      HacLong.Game.Engine.start_with_monster(
        pb,
        0,
        HacLong.Game.Engine.make_monster(%{level: 1, id: "bat", name: "Dơi Hang"}, false)
      )

    Characters.save!(ub.id, fight, "TEST")
    sa = join(ua)
    _sb = join(ub)
    assert Session.get(ub.id).battle.monster.name == "Dơi Hang"

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :ok, _

    pb = Session.get(ub.id)
    assert pb.battle.live and pb.battle.encounter[:slay]
    assert pb.battle.monster.name == Session.get(ua.id).name
    assert Enum.any?(pb.battle.log, &(&1.text =~ "Dơi Hang bị cắt ngang"))
  end

  test "đồ sát → luân phiên lượt → người thua chết, vàng mất chuyển cho người thắng, audit sạch" do
    ua = create_user()
    ub = create_user()
    player(ua, Map.put(strong(), :gold, 5000))
    player(ub, %{level: 10, gold: 3000})
    sa = join(ua)
    sb = join(ub)

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :ok, _

    # bên bị đánh vào trận ngay, không cần đồng ý; người tấn công đi trước
    pb = Session.get(ub.id)
    assert pb.battle.live and pb.battle.encounter.mine == false
    assert pb.battle.monster.name == Session.get(ua.id).name
    assert Session.get(ua.id).battle.encounter.mine

    assert %{ok: false, msg: "Chưa tới lượt bạn."} = cmd(sb, %{"act" => "attack"})
    # đang đồ sát thì không bị đồ sát thêm
    ref = push(sb, "slay", %{"uid" => ua.id})
    assert_reply ref, :error, %{msg: _}

    Enum.reduce_while(1..200, nil, fn _, _ ->
      case Slay.peek(ua.id) do
        nil -> {:halt, :ok}
        %{mine: true} -> {:cont, cmd(sa, %{"act" => "attack"})}
        %{mine: false} -> {:cont, cmd(sb, %{"act" => "attack"})}
      end
    end)

    pa = settled(ua.id)
    pb = settled(ub.id)
    assert pa.battle.result == "win" and pb.battle.result == "lose"
    assert pb.gold == 2700 and pa.gold == 5300
    assert pa.battle.reward.gold == 300
    assert pb.deaths == 1 and pb.pos == Maps.home_spawn()
    assert pb.hp > 0

    # bên bị đánh thấy chi tiết đòn của người đánh (đổi góc nhìn), cả đòn kết liễu
    name_a = pa.name
    texts = Enum.map(pb.battle.log, & &1.text)
    assert Enum.any?(texts, &(&1 =~ ~r/^#{name_a}, [^,]+, gây \d+ sát thương/u))
    refute Enum.any?(texts, &(&1 =~ ~r/(?<![\p{L}])[Bb]ạn(?![\p{L}])/u))

    # dòng đòn của người đánh trên màn bên bị đánh vẽ chi tiết như dòng của mình: tên (bên kia), sát thương thật,
    # máu còn lại thật của bên bị đánh (không phải số tạm của máy tính trận)
    max_b0 = HacLong.Game.Engine.derived(pb).maxHp

    foe_hits =
      Enum.filter(
        pb.battle.log,
        &(&1[:who] == "foe" and &1[:name] == name_a and is_integer(&1[:dmg]))
      )

    assert foe_hits != []
    assert Enum.all?(foe_hits, &(&1.dmg <= max_b0 and (&1[:left] == nil or &1.left <= max_b0)))

    # đòn mở màn của người tấn công (RULES.slay.first_strike_mult); đòn thường đầu tiên có thể bị né (không sát thương)
    assert Enum.any?(texts, &(&1 =~ "Đòn mở màn")) or
             Enum.any?(texts, &(&1 =~ ", đánh trượt."))

    # nhật ký người đánh: máu còn lại là máu thật của đối thủ (không phải số tạm của máy tính trận), sát thương ≤ máu tối đa
    max_b = HacLong.Game.Engine.derived(pb).maxHp
    hits = Enum.filter(pa.battle.log, &(&1[:who] == "me" and is_integer(&1[:left])))
    assert hits != []
    assert Enum.all?(hits, &(&1.left <= max_b and &1.dmg <= max_b))

    # đòn mở màn ghi ngay trong dòng đánh đầu của người tấn công, không thành dòng riêng
    refute Enum.any?(pa.battle.log, &String.starts_with?(&1.text, "⚔ Đòn mở màn"))
    first = Enum.find(hits, &(&1.dmg > 0))
    if first && first.turn <= 1, do: assert(first.note =~ "đòn mở màn")

    ko = Enum.find_index(texts, &(&1 == "#{name_a} hạ gục #{pb.name}."))
    assert ko && Enum.at(texts, ko - 1) =~ name_a

    assert [%{wager: 300, winner_id: winner}] =
             Repo.all(
               from m in "pk_matches",
                 where: m.a_id == ^ua.id and m.b_id == ^ub.id,
                 select: %{wager: m.wager, winner_id: m.winner_id}
             )

    assert winner == ua.id

    # lịch sử đồ sát qua kênh (tab Khác → Đấu trường)
    ref = push(sa, "slay_history", %{})
    assert_reply ref, :ok, %{history: [%{wager: 300, b_id: b_id, winner_id: w}]}
    assert b_id == ub.id and w == ua.id

    deltas =
      Repo.all(
        from l in "gold_log",
          where: l.user_id in ^[ua.id, ub.id] and l.reason == "SLAY",
          select: l.delta
      )

    assert Enum.sort(deltas) == [-300, 300]
    assert Enum.filter(Audit.run().problems, &(&1[:user_id] in [ua.id, ub.id])) == []

    # rời trận được như thường
    assert %{ok: true} = cmd(sa, %{"act" => "leave"})
  end

  test "nhật ký người đánh cho bên kia đọc: đã ghi tên hai bên, không xưng bạn" do
    # DECISIONS "Nhật ký trận: tên, dùng gì, gây bao nhiêu"
    m = &HacLong.Game.BattleText.mirror(&1, "bien", "bien2")

    assert m.("bien, Hắc Long Trảm, gây 1842 sát thương (CHÍ MẠNG!).") ==
             "bien, Hắc Long Trảm, gây 1842 sát thương (CHÍ MẠNG!)."

    assert m.("bien, Đòn thường, đánh trượt.") == "bien, Đòn thường, đánh trượt."
    # dòng không nhắc tên người đánh: thêm tên ở đầu
    assert m.("☠ bien2 trúng độc.") == "bien: ☠ bien2 trúng độc."

    assert HacLong.Game.BattleText.view(
             [%{text: "Khiên Thánh hồi 0 máu.", kind: "good"}],
             "a",
             "b"
           ) ==
             []
  end

  test "bỏ chạy tính như gục ngã" do
    ua = create_user()
    ub = create_user()
    player(ua, %{level: 12, gold: 1000})
    player(ub, %{level: 12, gold: 500})
    sa = join(ua)
    _sb = join(ub)

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :ok, _
    assert %{ok: true} = cmd(sa, %{"act" => "flee"})

    pa = settled(ua.id)
    pb = settled(ub.id)
    assert pa.battle.result == "lose" and pb.battle.result == "win"
    assert pa.gold == 900 and pb.gold == 600
    assert pa.pos == Maps.home_spawn() and pa.deaths == 1
  end

  test "hết giờ lượt: server đánh thay, sang lượt đối thủ" do
    ua = create_user()
    ub = create_user()
    player(ua, %{level: 12})
    player(ub, %{level: 12})
    sa = join(ua)
    _sb = join(ub)

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :ok, _
    %{id: id, mine: true} = Slay.peek(ua.id)

    send(Process.whereis(Slay), {:turn_over, id, ua.id})

    Enum.reduce_while(1..100, nil, fn _, _ ->
      if Slay.peek(ub.id).mine, do: {:halt, :ok}, else: {:cont, Process.sleep(20)}
    end)

    assert %{mine: true} = Slay.peek(ub.id)
    assert Enum.any?(Session.get(ub.id).battle.log, &(&1.text =~ "hết giờ"))
  end

  test "từ chối: vùng an toàn, người không online" do
    ua = create_user()
    ub = create_user()
    uc = create_user()
    village = %{map: "village", x: 12, y: 14}
    player(ua, %{level: 12}, village)
    player(ub, %{level: 12}, village)
    player(uc, %{level: 12})
    sa = join(ua)
    _sb = join(ub)

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :error, %{msg: "Đây là vùng an toàn" <> _}

    ref = push(sa, "slay", %{"uid" => uc.id})
    assert_reply ref, :error, %{msg: "Người này không online."}
    assert Session.get(ub.id).battle == nil
  end

  test "chiến bang: hạ thành viên bang địch thì bang +1 điểm, không bị tên đỏ, vẫn nhận vàng" do
    HacLong.GuildWars.reset()
    ua = create_user()
    ub = create_user()
    player(ua, Map.put(strong(), :gold, 300_000))
    player(ub, %{level: 10, gold: 300_000})
    sa = join(ua)
    sb = join(ub)
    ga = cmd(sa, %{"act" => "guild_create", "name" => "Bang Sa", "tag" => "SA1"}).player.guild.id
    cmd(sb, %{"act" => "guild_create", "name" => "Bang Sb", "tag" => "SB1"})
    ref = push(sa, "guild", %{"op" => "war_declare", "tag" => "SB1"})
    assert_reply ref, :ok, _
    ref = push(sb, "guild", %{"op" => "war_accept"})
    assert_reply ref, :ok, _

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :ok, _

    Enum.reduce_while(1..200, nil, fn _, _ ->
      case Slay.peek(ua.id) do
        nil -> {:halt, :ok}
        %{mine: true} -> {:cont, cmd(sa, %{"act" => "attack"})}
        %{mine: false} -> {:cont, cmd(sb, %{"act" => "attack"})}
      end
    end)

    settled(ub.id)
    refute Slay.red?(ua.id)
    assert Slay.protected_s(ub.id) > 0
    assert %{mine: 1, theirs: 0} = HacLong.GuildWars.brief(ga)
    assert Session.get(ua.id).gold > 300_000
  end

  test "đấu trường trực tiếp: mời → nhận, khác bản đồ được, vào trận đầy máu, xong trả máu cũ, không mất vàng / tên đỏ, đổi Elo" do
    ua = create_user()
    ub = create_user()
    player(ua, Map.merge(strong(), %{gold: 5000, hp: 50}))
    player(ub, %{level: 10, gold: 3000}, %{map: "village", x: 12, y: 14})
    sa = join(ua)
    sb = join(ub)

    ref = push(sb, "duel", %{"op" => "accept"})
    assert_reply ref, :error, %{msg: "Không có lời mời" <> _}

    ref = push(sa, "duel", %{"op" => "invite", "uid" => ub.id})
    assert_reply ref, :ok, %{msg: msg}
    assert msg =~ "Đã mời"
    assert_push "duel_invite", %{from: from}
    assert from == ua.id

    ref = push(sb, "duel", %{"op" => "accept"})
    assert_reply ref, :ok, _

    # vào Hồ Tỷ Thí ở hai đầu, chưa vào trận: tự đi lại gần rồi đồ sát nhau
    assert Session.get(ua.id).pos == Slay.duel_spot(true)
    assert Session.get(ub.id).pos == Slay.duel_spot(false)
    assert Session.get(ua.id).battle == nil

    # xa quá (không cánh: phải đứng sát bên)
    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :error, %{msg: far}
    assert far =~ "xa quá"

    # người khác không đánh được người đang đấu ở hồ; lại gần thì đánh
    a0 = Slay.duel_spot(true)
    Session.teleport(ub.id, %{a0 | x: a0.x + 1})
    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :ok, _
    pa = Session.get(ua.id)
    assert pa.battle.encounter.duel and pa.battle.encounter.hp0 == 50
    assert pa.hp == HacLong.Game.Engine.derived(pa).maxHp

    Enum.reduce_while(1..200, nil, fn _, _ ->
      case Slay.peek(ua.id) do
        nil -> {:halt, :ok}
        %{mine: true} -> {:cont, cmd(sa, %{"act" => "attack"})}
        %{mine: false} -> {:cont, cmd(sb, %{"act" => "attack"})}
      end
    end)

    pb = settled(ub.id)
    pa = settled(ua.id)
    assert pa.battle.result == "win" and pb.battle.result == "lose"

    # về chỗ cũ chạy trong Session từng người ngay sau khi chốt trận (giữ màn kết quả)
    pb = back_home(ub.id, "village")
    assert pb.battle.result == "lose"
    assert pa.gold == 5000 and pb.gold == 3000
    assert pa.hp == 50
    # xong trận về đúng chỗ cũ
    assert pb.pos == %{map: "village", x: 12, y: 14}

    # đóng màn kết quả: người thua đấu trực tiếp không bị tính gục ngã (vẫn ở chỗ cũ, vẫn có mặt trên bản đồ)
    assert HacLong.World.finish_encounter(pb, ub.id).pos == pb.pos
    snap = HacLong.World.MapServer.snapshot("village")
    assert Enum.any?(snap.players, &(&1.id == ub.id))
    assert pa.pos.map != Slay.duel_map()
    refute Slay.red?(ua.id)
    assert HacLong.Arena.stats(ua.id).rating > 1000
    assert HacLong.Arena.stats(ub.id).rating < 1000
    assert HacLong.Arena.stats(ua.id).today == 1
  end

  test "thắng: người tấn công bị tên đỏ, người thua được bảo vệ, báo kênh thế giới" do
    ua = create_user()
    ub = create_user()
    player(ua, Map.put(strong(), :gold, 5000))
    player(ub, %{level: 10, gold: 3000})
    sa = join(ua)
    sb = join(ub)

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :ok, _

    Enum.reduce_while(1..200, nil, fn _, _ ->
      case Slay.peek(ua.id) do
        nil -> {:halt, :ok}
        %{mine: true} -> {:cont, cmd(sa, %{"act" => "attack"})}
        %{mine: false} -> {:cont, cmd(sb, %{"act" => "attack"})}
      end
    end)

    settled(ub.id)
    assert Slay.red?(ua.id) and Slay.red_s(ua.id) > 1700
    refute Slay.red?(ub.id)
    assert Slay.protected_s(ub.id) in 20..30
    assert Enum.any?(HacLong.Chat.history(), &(&1.text =~ "đã đồ sát"))

    # hồ sơ hiện tên đỏ; ảnh chụp bản đồ có cờ đỏ
    ref = push(sb, "inspect", %{"uid" => ua.id})
    assert_reply ref, :ok, %{profile: %{red_s: red_s}}
    assert red_s > 0

    # đang được bảo vệ thì không bị đồ sát
    assert {:error, msg} = Slay.start(ua.id, ub.id, Session.get(ua.id), Session.get(ub.id))
    assert msg =~ "đang được bảo vệ"
  end

  test "không giới hạn số lần đồ sát cùng một người; tự đi đồ sát thì mất bảo vệ" do
    pa = %{name: "A", hp: 100, pos: field()}
    pb = %{name: "B", hp: 100, pos: field()}

    for _ <- 1..6 do
      {:ok, f} = Slay.start(1, 2, pa, pb)
      Slay.abort(f.id)
    end

    # người khác cũng đánh được
    assert {:ok, f} = Slay.start(3, 2, %{pa | name: "C"}, pb)
    Slay.abort(f.id)

    :ets.insert(:slay_marks, {{3, :safe}, System.system_time(:millisecond) + 60_000})
    assert Slay.protected_s(3) > 0
    assert {:ok, f} = Slay.start(3, 4, %{pa | name: "C"}, %{pb | name: "D"})
    Slay.abort(f.id)
    assert Slay.protected_s(3) == 0
  end

  test "tên đỏ gục: mất vàng gấp đôi, người thắng nhận hết" do
    {_, a} = Commands.run(nil, %{"act" => "create", "name" => "Thang", "cls" => "dk"})
    {_, b} = Commands.run(nil, %{"act" => "create", "name" => "Do", "cls" => "dk"})

    f = %{
      id: 7,
      a: 1,
      b: 2,
      names: %{1 => "Thang", 2 => "Do"},
      hp: %{1 => 50, 2 => 0},
      red: %{1 => false, 2 => true},
      map: "forest_1",
      turns: 3
    }

    in_slay = fn p, foe, uid ->
      {_, p} = HacLong.Game.Engine.start_with_monster(p, 0, Slay.opponent(foe, uid))

      b =
        Map.merge(p.battle, %{live: true, encounter: %{slay: 7, foe: uid, mine: false, until: 0}})

      %{p | battle: b, pos: field()}
    end

    pw = in_slay.(%{a | gold: 1000}, b, 2)
    pl = in_slay.(%{b | gold: 1000}, a, 1)
    {pw2, pl2, lost} = Slay.outcome(f, pw, pl, 1, :ko)

    assert lost == 200 and pl2.gold == 800 and pw2.gold == 1200
    assert pl2.battle.result == "lose" and pw2.battle.result == "win"
    assert Enum.any?(pl2.battle.log, &(&1.text =~ "Tên đỏ"))
  end

  test "⚡ Đồ sát nhanh: hai bên bật ⚡ thì server tự đánh theo combo từng lượt tới khi có người gục" do
    ua = create_user()
    ub = create_user()
    player(ua, Map.merge(strong(), %{gold: 5000}))
    player(ub, %{level: 10, gold: 3000})
    sa = join(ua)
    sb = join(ub)
    assert %{ok: true} = cmd(sa, %{"act" => "quick", "on" => true})
    assert %{ok: true} = cmd(sb, %{"act" => "quick", "on" => true})

    ref = push(sa, "slay", %{"uid" => ub.id})
    assert_reply ref, :ok, _

    # không gửi lệnh đánh nào: server tự đánh lượt của cả hai rồi tự rời màn trận
    done =
      Enum.reduce_while(1..150, false, fn _, _ ->
        Process.sleep(100)
        a = Session.get(ua.id)
        b = Session.get(ub.id)
        if a.battle == nil and b.battle == nil, do: {:halt, true}, else: {:cont, false}
      end)

    assert done
    assert Session.get(ub.id).deaths == 1
    assert Slay.peek(ua.id) == nil
    _ = sb
  end
end

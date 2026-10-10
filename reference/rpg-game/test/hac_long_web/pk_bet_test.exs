defmodule HacLongWeb.PkBetTest do
  @moduledoc "Phase 5 (H7 + H8): PK cược vàng — trận tự đánh thuần; mời cược qua kênh đã tắt (thay bằng đồ sát)."
  use HacLongWeb.ChannelCase

  alias HacLong.{Accounts, Arena, PkBet}
  alias HacLong.Game.{Characters, Commands, PkFight, Rng, Session}
  alias HacLongWeb.{ClientVersion, UserSocket}

  setup do
    HacLong.RateLimit.reset()
    PkBet.reset()
    on_exit(&Rng.clear/0)
    :ok
  end

  defp player(user, attrs) do
    name = "Pk #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    p = p |> Map.put(:tutorial, nil) |> Map.put(:pos, %{map: "village", x: 12, y: 14})
    p = Map.merge(p, attrs)
    {p, _} = HacLong.Game.Achievements.check(p)
    Characters.save!(user.id, p, "TEST")
    p
  end

  defp join(user) do
    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})
    {:ok, _reply, socket} = subscribe_and_join(socket, "game", %{"v" => ClientVersion.current()})
    socket
  end

  describe "trận tự đánh (thuần)" do
    test "bên mạnh hơn thắng; cùng dãy số thì cùng kết quả" do
      {_, weak} = Commands.run(nil, %{"act" => "create", "name" => "Yeu", "cls" => "dw"})
      {_, strong} = Commands.run(nil, %{"act" => "create", "name" => "Manh", "cls" => "dk"})
      strong = %{strong | level: 40, stats: Map.new(strong.stats, fn {k, v} -> {k, v * 5} end)}

      Rng.put_sequence([0.5, 0.3, 0.7, 0.9, 0.1])
      r1 = PkFight.fight(Arena.opponent(strong, 1), Arena.opponent(weak, 2))
      Rng.put_sequence([0.5, 0.3, 0.7, 0.9, 0.1])
      r2 = PkFight.fight(Arena.opponent(strong, 1), Arena.opponent(weak, 2))

      assert r1.winner == :a and r1 == r2
      assert r1.hp.b == 0 and r1.rounds >= 1
      assert List.last(r1.log).text =~ "Manh thắng"

      # đổi chỗ: người mời yếu vẫn thua
      Rng.put_sequence([0.5])
      assert PkFight.fight(Arena.opponent(weak, 2), Arena.opponent(strong, 1)).winner == :b
    end

    test "hai bản sao không làm gì được nhau quá số lượt: hòa" do
      {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Hoa", "cls" => "dk"})
      a = %{Arena.opponent(p, 1) | maxHp: 10_000, hp: 10_000, dodge: 0.0, crit: 0.0}

      # cùng chỉ số, không né, không chí mạng, đòn cố định → máu hai bên giảm như nhau
      Rng.put_sequence([0.5])
      r = PkFight.fight(a, %{a | name: "Hoa 2"})
      assert r.winner == :draw and r.rounds == PkBet.rules().rounds
    end
  end

  describe "qua kênh" do
    test "mời cược đã tắt (thay bằng đồ sát), vẫn xem được lịch sử" do
      ua = create_user()
      ub = create_user()
      player(ua, %{gold: 5000})
      player(ub, %{gold: 3000})
      sa = join(ua)
      _sb = join(ub)

      ref = push(sa, "pk", %{"op" => "invite", "uid" => ub.id, "wager" => 1000})
      assert_reply ref, :error, %{msg: msg}
      assert msg =~ "Đồ sát"

      ref = push(sa, "pk", %{"op" => "info"})
      assert_reply ref, :ok, %{invite: nil, history: [], today: 0}
      assert Session.get(ua.id).gold == 5000
    end
  end
end

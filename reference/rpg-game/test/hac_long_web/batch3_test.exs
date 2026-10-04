defmodule HacLongWeb.Batch3Test do
  @moduledoc """
  Đợt 3 qua Session / database (FEATURE_CATALOG C10, C18, D1, D3): dữ liệu cũ tách cấp nâng khi nạp,
  ép thành công từ +7 báo cả server, đồ khóa không rao chợ được.
  """
  use HacLongWeb.ChannelCase

  alias HacLong.{Chat, Market}
  alias HacLong.Game.{Characters, Commands, Engine, Gear, Rng, Session}

  @smith %{map: "village", x: 8, y: 11}

  setup do
    HacLong.RateLimit.reset()
    :ok
  end

  defp player(user, attrs) do
    name = "Ba #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "warrior"})
    p = p |> Map.put(:tutorial, nil) |> Map.merge(attrs)
    {p, _} = HacLong.Game.Achievements.check(p)
    Characters.save!(user.id, p, "TEST")
    p
  end

  test "nạp nhân vật cũ: cấp nâng theo loại tách thành từng món" do
    u = create_user()
    player(u, %{upgrades: %{"club" => 4}, inv: %{"club" => 1}})
    p = Characters.load(u.id)
    assert [%{base: "club"} = a, %{base: "club"} = b] = p.gear
    assert p.upgrades == %{a.uid => 4, b.uid => 4}
    assert p.equip.weapon in [a.uid, b.uid] and p.equip.wing == nil
  end

  test "ép thành công +7 báo lên kênh chat hệ thống" do
    u = create_user()
    g = Gear.plain("greatsword")

    player(u, %{
      level: 30,
      gold: 100_000,
      pos: @smith,
      gear: [g],
      equip: %{weapon: g.uid, armor: "vest", shield: nil, wing: nil},
      upgrades: %{g.uid => 6},
      inv: %{"jewel_soul" => 1}
    })

    Phoenix.PubSub.subscribe(HacLong.PubSub, Chat.topic())

    # số ngẫu nhiên cố định trong chính tiến trình Session (ép chắc chắn thành công)
    {:ok, _} = Session.admin(u.id, fn p -> {:ok, p, Rng.put_sequence([0.0]) && "rng"} end)
    {r, p} = Session.command(u.id, %{"act" => "upgrade", "slot" => "weapon"})
    assert r.upgrade == %{result: "success", level: 7} and not Map.has_key?(r, :announce)
    assert Engine.upgrade_level(p, g.uid) == 7
    assert_receive {:chat, %{text: text}}
    assert text =~ "+7"
  end

  test "đồ khóa không rao chợ được" do
    u = create_user()
    g = Gear.plain("greatsword") |> Map.put(:locked, true)
    p = player(u, %{gear: [g]})
    assert {:error, msg} = Market.list(u.id, p, g.uid, 1, 100, &Characters.save!(u.id, &1))
    assert msg =~ "đang khóa"
    # khóa lưu được trong database
    assert [%{locked: true}] = Characters.load(u.id).gear
  end
end

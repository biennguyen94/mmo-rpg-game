defmodule HacLong.Bots.BrainPlayTest do
  # DECISIONS "Bot chơi như người thật": cánh trước, thú cưng, Tháp Vô Tận, Quảng Trường / Lâu Đài / Kalima
  use ExUnit.Case, async: false

  alias HacLong.Bots.Brain
  alias HacLong.Game.{BloodCastle, Data, DevilSquare, Engine, Gear, Kalima, Pets, Tower}

  @play Data.rules().bots.play

  setup do
    Application.put_env(:hac_long, :devil_square_always_open, true)
    on_exit(fn -> Application.delete_env(:hac_long, :devil_square_always_open) end)
  end

  defp player(attrs \\ %{}) do
    {:ok, p} = Engine.new_player("Bot", "dk")

    p =
      Map.merge(
        p,
        Map.merge(%{level: 45, gold: 10_000_000, pos: %{map: "village", x: 20, y: 8}}, attrs)
      )

    %{p | hp: Engine.derived(p).maxHp}
  end

  defp up(p, id, n), do: Map.put(p, :upgrades, Map.put(p[:upgrades] || %{}, id, n))
  defp d(p), do: Engine.derived(p)

  describe "cánh" do
    test "chưa có cánh: ép món làm cánh trước cả đồ đang mặc, kể cả khi chưa có Ngọc Hỗn Nguyên" do
      p = player(%{inv: %{"jewel_bless" => 1}})
      p = p |> Gear.add(%{Gear.new("item_8_33") | uid: "#SAC"}) |> elem(0)
      assert {"shop", %{"act" => "upgrade", "id" => "#SAC"}} = Brain.forge_job(p)

      # đủ +5 nhưng chưa có Ngọc Hỗn Nguyên: chưa ghép, ép đồ đang mặc như thường
      p = up(p, "#SAC", 5)
      assert {"shop", %{"act" => "upgrade", "slot" => _}} = Brain.forge_job(p)

      p = %{p | inv: Map.put(p.inv, "jewel_chaos", 1)}

      assert {"chaos", %{"act" => "chaos", "id" => "wing1", "gear" => "#SAC"}} =
               Brain.forge_job(p)
    end

    test "cánh vừa ghép nằm trong túi: mặc vào (trước đây không mặc, ghép cánh mãi)" do
      p = player()
      {p, _} = Gear.add(p, %{Gear.new("wing_dk_1") | uid: "#W1"})
      assert %{"act" => "equip", "id" => "#W1"} = Brain.decide(p, nil)

      {%{ok: true}, p} = Engine.equip(p, "#W1")
      # cánh cùng bậc, ép thấp hơn: giữ cánh đang mặc; cánh bậc cao hơn: thay
      p = up(p, "#W1", 3)
      {p, _} = Gear.add(p, %{Gear.new("wing_dk_1") | uid: "#W1B"})
      refute match?(%{"act" => "equip", "id" => "#W1B"}, Brain.decide(p, nil))
      {p, _} = Gear.add(p, %{Gear.new("wing_dk_2") | uid: "#W2"})
      assert %{"act" => "equip", "id" => "#W2"} = Brain.decide(p, nil)
    end
  end

  test "chưa cầm gì tay trái mà nhặt được khiên: mặc vào (trước đây lỗi `not nil`, bot đứng im)" do
    p = player()
    {_, p} = Engine.unequip(p, "shield")

    {id, _} =
      Data.items()
      |> Enum.filter(fn {id, i} ->
        i[:slot] == "shield" and i[:tier] != nil and
          Engine.can_wear?(p, Gear.resolve(Gear.new(id)))
      end)
      |> Enum.min_by(fn {_, i} -> i[:level] || 0 end)

    {p, _} = Gear.add(p, %{Gear.new(id) | uid: "#SH"})
    assert %{"act" => "equip", "id" => "#SH"} = Brain.decide(p, nil)
  end

  describe "thú cưng" do
    test "chưa có thú: mua con mạnh nhất trong tầm giá ở Người Nuôi Thú" do
      p = player(%{gold: 200_000})
      assert {"pets", %{"act" => "pet_buy", "id" => id}} = Brain.pet_job(p)
      budget = (p.gold - Data.rules().bots.forge.gold_keep_per_level * p.level) * @play.pet_budget
      assert Data.pet(id).price <= budget

      # nghèo: không mua
      assert Brain.pet_job(player(%{gold: 1000})) == nil
    end

    test "đã có thú: dắt con mạnh nhất, dư vàng thì cho ăn" do
      p = player(%{gold: 30_000, pets: ["sheep", "hound"], pet: "sheep"})
      best = Enum.max_by(["sheep", "hound"], &Pets.power(p, &1))

      if best != "sheep",
        do: assert({nil, %{"act" => "pet_choose", "id" => ^best}} = Brain.pet_job(p))

      p = %{p | pet: best}
      cost = Pets.feed_cost(p)
      keep = Data.rules().bots.forge.gold_keep_per_level * p.level
      rich = %{p | gold: keep + cost * @play.feed_mult + 1}
      # vàng dư nhỏ so với giá thú mạnh hơn: không mua thêm mà cho ăn
      assert {"pets", %{"act" => "pet_feed"}} = Brain.pet_job(%{rich | pet: best})
    end
  end

  describe "Tháp Vô Tận" do
    test "tới lượt (tiến trình bot hẹn giờ): vào từ tầng bắt đầu cao nhất đã mở; máu chưa đầy thì hồi trước" do
      p = player(%{tower_best: 23})
      due = %{tower_due: true}
      assert {"tower", %{"act" => "tower_enter", "floor" => 21}} = Brain.tower_job(p, d(p), due)
      assert Brain.tower_job(p, d(p), %{tower_due: false}) == nil
      assert Brain.tower_job(%{p | level: @play.tower_level - 1}, d(p), due) == nil
      assert Brain.tower_job(%{p | hp: 1}, d(p), due) == :heal
      # máu thấp, ở Làng: đi nghỉ trọ trước khi vào tháp
      assert %{"act" => _} = Brain.decide(%{p | hp: div(d(p).maxHp, 2)}, nil, due)
    end

    test "trong tháp: đánh quái, hết quái lên cầu thang, xong chặng 10 tầng hoặc máu thấp thì ra" do
      {_, p} = Tower.enter(player(), 1)
      %{"act" => "move"} = Brain.decide(p, nil)

      # đi tới quái: lặp lệnh của bot tới khi vào trận
      p = walk_until(p, &(&1.battle != nil))
      assert p.battle

      # hết quái: bước tới cầu thang lên
      {_, q} = Tower.enter(player(), 1)
      q = put_in(q.tower.monsters, [])
      q = walk_until(q, &(&1.tower.floor == 2))
      assert q.tower.floor == 2

      # tầng 10 xong: ra cổng (về Làng)
      q = put_in(q.tower, %{q.tower | floor: 10, monsters: []})
      q = walk_until(q, &(&1.pos.map == "village"))
      assert q.pos.map == "village"
    end
  end

  describe "sự kiện" do
    test "Quảng Trường / Lâu Đài đang mở: có vé thì vào, có mảnh thì ghép vé, không thì mua" do
      p = player(%{inv: %{DevilSquare.ticket() => 1}})
      assert {"tower", %{"act" => "ds_enter"}} = Brain.event_job(p)

      p = player(%{inv: %{"devil_eye" => 1, "devil_key" => 1}})
      assert {"chaos", %{"act" => "chaos", "id" => "ds_ticket"}} = Brain.event_job(p)

      assert {"tower", %{"act" => "ds_buy"}} = Brain.event_job(player())

      # đã vào Quảng Trường đợt này: sang Lâu Đài
      slot = DevilSquare.window().slot
      p = player(%{daily: %{ds_slot: slot}, inv: %{BloodCastle.ticket() => 1}})
      assert {"tower", %{"act" => "bc_enter"}} = Brain.event_job(p)

      # máu chưa đầy: hồi máu trước rồi mới vào
      assert Brain.event_job(%{player(%{inv: %{DevilSquare.ticket() => 1}}) | hp: 1}) == :heal
    end

    test "Kalima: đủ Dấu Ấn thì ghép Bản Đồ Thất Lạc, có bản đồ thì vào" do
      slot = DevilSquare.window().slot
      bc = BloodCastle.window().slot
      base = %{daily: %{ds_slot: slot, bc_slot: bc}, gold: 0 + 100_000}
      p = player(Map.put(base, :inv, %{Kalima.mark() => 5}))
      assert {"chaos", %{"act" => "chaos", "id" => "lost_map"}} = Brain.event_job(p)
      p = player(Map.put(base, :inv, %{Kalima.ticket() => 1}))
      assert {"tower", %{"act" => "kal_enter"}} = Brain.event_job(p)
    end

    test "trong Quảng Trường: hết quái thì lên cầu thang; Lâu Đài xong thì bước ra" do
      {%{ok: true}, p} = DevilSquare.enter(player(%{inv: %{DevilSquare.ticket() => 1}}))
      p = put_in(p.tower.monsters, [])
      p = walk_until(p, &(&1.tower == nil or &1.tower.floor == 2))
      assert p.tower.floor == 2

      {%{ok: true}, q} = BloodCastle.enter(player(%{inv: %{BloodCastle.ticket() => 1}}))
      q = put_in(q.tower.bc, %{q.tower.bc | done: true, stage: "done"})
      assert %{"act" => "move"} = Brain.decide(q, nil)
    end
  end

  # chạy lệnh bước của bot qua World.move (bản đồ riêng `tower` không cần MapServer) tới khi `stop?`
  defp walk_until(p, stop?, n \\ 80) do
    cond do
      stop?.(p) ->
        p

      n == 0 ->
        flunk("bot không tới đích: #{inspect(p.pos)}")

      true ->
        case Brain.decide(p, nil) do
          %{"act" => "move", "dir" => dir} ->
            {_r, p} = HacLong.World.move(p, -1, dir, true)
            walk_until(p, stop?, n - 1)

          other ->
            flunk("lệnh lạ: #{inspect(other)}")
        end
    end
  end
end

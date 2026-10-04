defmodule MuWeb.AoiChannelTest do
  @moduledoc "P3-M1 qua kênh thật: chỉ nhận entity trong 3×3 ô; ra / vào tầm nhìn → despawn / spawn."
  use MuWeb.ChannelCase

  alias Mu.World.MapServer
  alias MuWeb.GameChannel
  alias Phoenix.Socket.Message

  @map "lorencia"

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  # đặt chỗ + đánh dấu đổi rồi chạy tới snapshot
  defp place(c, {x, y}) do
    MapServer.debug_update(@map, fn st ->
      st = update_in(st.players[c.id], &%{&1 | x: x, y: y})
      %{st | dirty: MapSet.put(st.dirty, st.players[c.id].id)}
    end)

    MapServer.tick(@map, MapServer.debug_state(@map).snapshot_every)
  end

  # sự kiện `ev` theo join_ref (mọi kênh trong test đẩy về cùng tiến trình test)
  defp got(join_ref, ev, acc \\ []) do
    receive do
      %Message{event: ^ev, join_ref: ^join_ref, payload: p} -> got(join_ref, ev, [p | acc])
    after
      60 -> Enum.reverse(acc)
    end
  end

  defp flush do
    receive do
      %Message{} -> flush()
    after
      60 -> :ok
    end
  end

  test "vào map chỉ nhận spawn trong tầm nhìn; người khác ra / vào tầm → despawn / spawn" do
    {a1, c1} = create_character()
    {a2, c2} = create_character()
    {:ok, _, s1} = join_game(a1, c1)
    {:ok, _, s2} = join_game(a2, c2)

    # mọi entity s1 nhận lúc vào đều trong 3×3 ô quanh chỗ đứng
    size = Mu.Game.Config.get(["server", "aoiCellSize"])
    me = MapServer.debug_state(@map).players[c1.id]
    all = MapServer.debug_state(@map)

    for p <- got(s1.join_ref, "spawn") do
      assert MuWeb.Aoi.near?(MuWeb.Aoi.cell(me.x, me.y, size), MuWeb.Aoi.cell(p.x, p.y, size), 1)
    end

    # map có quái ngoài tầm nhìn (không được gửi)
    assert Enum.any?(Map.values(all.monsters), fn m ->
             not MuWeb.Aoi.near?(
               MuWeb.Aoi.cell(me.x, me.y, size),
               MuWeb.Aoi.cell(m.x, m.y, size),
               1
             )
           end)

    flush()
    p2 = "p_" <> c2.id

    # c2 đi xa (ô cách ≥ 2) → s1 nhận despawn, không nhận snapshot của c2
    place(c1, {20, 20})
    place(c2, {90, 90})
    assert [%{id: ^p2}] = got(s1.join_ref, "despawn")
    flush()

    place(c2, {91, 90})

    refute Enum.any?(got(s1.join_ref, "snapshot"), fn s ->
             Enum.any?(s.entities, &(&1.id == p2))
           end)

    # c2 quay lại → spawn với vị trí hiện tại
    place(c2, {30, 25})
    assert [%{id: ^p2, x: 30, y: 25, kind: "player"}] = got(s1.join_ref, "spawn")
    _ = s2
  end

  test "combat ngoài tầm nhìn không gửi; trong tầm thì gửi" do
    {a1, c1} = create_character()
    {:ok, _, s1} = join_game(a1, c1)
    place(c1, {20, 20})
    flush()

    hit = fn a, t ->
      Phoenix.PubSub.broadcast(
        Mu.PubSub,
        MapServer.topic(@map),
        {:map_event, "combat", %{rid: nil, attacker: a, target: t, dmg: 1, crit: false, hp: 1}}
      )
    end

    hit.("m_khong_co", "p_khong_co")
    assert [] = got(s1.join_ref, "combat")
    hit.("m_khong_co", "p_" <> c1.id)
    assert [_] = got(s1.join_ref, "combat")
  end
end

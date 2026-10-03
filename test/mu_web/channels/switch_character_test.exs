defmodule MuWeb.SwitchCharacterTest do
  @moduledoc "P3-M5 (P3-3): một tài khoản nhiều nhân vật, một nhân vật online; đổi nhân vật thì nhân vật cũ rời map + nhóm."
  use MuWeb.ChannelCase

  alias Mu.Game.Characters
  alias Mu.World.MapServer
  alias MuWeb.GameChannel

  @map "lorencia"

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  test "đổi sang nhân vật thứ hai: nhân vật đầu rời map (đã lưu) và rời nhóm" do
    {a, c1} = create_character()

    {:ok, c2} =
      Characters.create(a, %{"name" => "Alt#{rem(System.unique_integer([:positive]), 99_999)}"})

    {b, cb} = create_character()

    {:ok, _, s1} = join_game(a, c1)
    {:ok, _, _sb} = join_game(b, cb)

    :ok =
      Mu.Party.invite(%{cid: cb.id, name: cb.name, class: "DK", level: 1, map_id: @map}, c1.name)

    # chấp nhận bằng API Party (như Session của c1 gọi)
    :ok =
      Mu.Party.accept(%{cid: c1.id, name: c1.name, class: "DK", level: 1, map_id: @map}, cb.name)

    assert c1.id in Mu.Party.mates(cb.id)

    Process.unlink(s1.channel_pid)
    leave(s1)
    {:ok, reply, _s2} = join_game(a, c2)
    assert reply.player.name == c2.name

    assert MapServer.position(@map, c1.id) == nil
    assert MapServer.position(@map, c2.id) != nil
    assert Mu.Party.mates(cb.id) == [cb.id]
  end

  test "danh sách nhân vật theo thứ tự tạo; không vào được nhân vật của tài khoản khác" do
    {a, c1} = create_character()

    {:ok, c2} =
      Characters.create(a, %{"name" => "Sec#{rem(System.unique_integer([:positive]), 99_999)}"})

    assert Enum.map(Characters.list(a.id), & &1.id) == [c1.id, c2.id]

    {other, _} = create_character()
    assert {:error, %{error: "FORBIDDEN", reason: "character"}} = join_game(other, c2)
  end
end

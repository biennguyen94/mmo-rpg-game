defmodule MuWeb.RankingChannelTest do
  @moduledoc """
  P6-M1 (P6-7) qua kênh thật: act `ranking {board}` → event `ranking {board, rows, me, updatedAt}`;
  bảng cấp (tất cả / class) xếp cấp → EXP → tạo trước, kèm guild; bảng guild theo tổng cấp; hạng
  của mình kể cả ngoài top; cache tới khi hết `refreshSeconds`; bảng lạ → INVALID_TARGET.
  """
  use MuWeb.ChannelCase

  alias Mu.Game.Character
  alias MuWeb.GameChannel
  alias Phoenix.Socket.Message

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  defp char(level, exp \\ 0, class \\ "DK") do
    {a, c} = create_character(nil, class)
    c = Mu.Repo.update!(Ecto.Changeset.change(c, level: level, experience: exp))
    {a, c}
  end

  defp ranking(socket, board) do
    Mu.RateLimit.reset()

    ref =
      push(socket, "cmd", %{
        "act" => "ranking",
        "rid" => "r#{System.unique_integer([:positive])}",
        "board" => board
      })

    assert_reply ref, status, reply
    jr = socket.join_ref

    if status == :ok do
      assert_receive %Message{event: "ranking", join_ref: ^jr, payload: view}
      view
    else
      {:error, reply.error}
    end
  end

  setup do
    Mu.Leaderboard.reset()
    :ok
  end

  test "bảng cấp: thứ tự cấp → EXP → tạo trước, top theo config, hạng của mình; bảng class" do
    {_, top} = char(30, 500)
    {_, same_more_exp} = char(29, 900)
    {_, same_less_exp} = char(29, 100)
    {_, dw} = char(25, 0, "DW")
    {a, me} = char(2)
    {:ok, _, s} = join_game(a, me)

    v = ranking(s, "level")
    names = Enum.map(v.rows, & &1.name)
    assert Enum.take(names, 4) == [top.name, same_more_exp.name, same_less_exp.name, dw.name]
    assert hd(v.rows) |> Map.take([:rank, :class, :level]) == %{rank: 1, class: "DK", level: 30}
    assert v.me.name == me.name and v.me.rank == Enum.find_index(names, &(&1 == me.name)) + 1
    assert is_integer(v.updatedAt)

    dws = ranking(s, "level_DW").rows
    assert Enum.all?(dws, &(&1.class == "DW")) and hd(dws).name == dw.name
    # mình là DK: không có hạng ở bảng DW
    assert ranking(s, "level_DW").me == nil
    assert {:error, "INVALID_TARGET"} = ranking(s, "zen")
  end

  test "cache: nhân vật lên cấp sau lần đọc đầu chưa hiện tới khi làm mới; bảng guild" do
    {a, me} = char(20)
    {:ok, _, s} = join_game(a, me)
    first = ranking(s, "level")
    {_, newbie} = char(31)
    assert hd(ranking(s, "level").rows).name == hd(first.rows).name
    Mu.Leaderboard.reset()
    assert hd(ranking(s, "level").rows).name == newbie.name

    {:ok, _} = Mu.Game.ZenAudit.admin_set(me.id, 10_000, "test")

    {:ok, %{guild_id: _}, _} =
      Mu.Guilds.create(me.id, "R#{rem(System.unique_integer([:positive]), 99_999)}")

    {_, mate} = char(10)
    :ok = Mu.Guilds.add_member(Mu.Guilds.membership(me.id).guild_id, mate.id)
    Mu.Leaderboard.reset()
    g = ranking(s, "guild")
    mine = Enum.find(g.rows, &(&1.master == me.name))
    assert mine.totalLevel == 30 and mine.members == 2
    assert g.me.rank == mine.rank
    assert Enum.find(ranking(s, "level").rows, &(&1.name == me.name)).guild == mine.name
    assert Mu.Repo.get!(Character, me.id).level == 20
  end
end

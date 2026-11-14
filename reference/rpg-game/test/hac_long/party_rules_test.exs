defmodule HacLong.PartyRulesTest do
  @moduledoc "Phase 5 (H2, H3): lời mời tổ đội hết hạn, trưởng nhóm rời thì người vào sớm nhất lên thay, rớt mạng thì rời đội."
  use ExUnit.Case, async: false

  alias HacLong.Party

  defp uid, do: 9_000_000 + System.unique_integer([:positive])

  defp form(leader, others) do
    for o <- others do
      :ok = Party.invite(leader, o)
      :ok = Party.accept(o)
    end

    Party.of(leader)
  end

  defp leave_all(uids), do: Enum.each(uids, &Party.leave/1)

  test "lời mời hết hạn: người được mời không vào được, tổ đội một người tự tan" do
    [a, b] = [uid(), uid()]
    Phoenix.PubSub.subscribe(HacLong.PubSub, HacLong.Game.Session.topic(a))
    :ok = Party.invite(a, b)
    assert Party.of(a).members == [a]
    %{ref: ref} = Party.invitation(b)
    send(Party, {:invite_expired, b, ref})

    assert Party.invitation(b) == nil
    assert {:error, _} = Party.accept(b)
    assert Party.of(a) == nil
    assert_receive {:notice, "Lời mời tổ đội đã hết hạn."}
  end

  test "trưởng nhóm rời: người vào sớm nhất còn lại lên thay; còn một người thì tan" do
    [a, b, c] = [uid(), uid(), uid()]
    assert %{leader: ^a, members: [^a, ^b, ^c]} = form(a, [b, c])
    :ok = Party.leave(a)
    assert %{leader: ^b, members: [^b, ^c]} = Party.of(c)
    :ok = Party.leave(b)
    assert Party.of(c) == nil
  end

  test "rớt mạng quá hạn thì rời tổ đội; quay lại kịp thì ở lại" do
    [a, b, c] = [uid(), uid(), uid()]
    form(a, [b, c])

    Party.back(b)
    Party.away(b)
    %{away: %{^b => ref}} = :sys.get_state(Party)
    Party.back(b)
    send(Party, {:away_expired, b, ref})
    assert b in Party.of(a).members

    Party.away(c)
    %{away: %{^c => ref}} = :sys.get_state(Party)
    send(Party, {:away_expired, c, ref})
    refute c in Party.of(a).members
    leave_all([a, b])
  end

  test "trận chung với trùm Thức Tỉnh: mỗi người mạnh cộng máu chung một lần, mọi người thấy cùng máu tối đa" do
    [a, b, c] = [uid(), uid(), uid()]
    form(a, [b, c])
    key = "test_map:#{a}"

    # người mạnh mở trận: máu của mình đã gồm phần Thức Tỉnh (900 = 300 gốc + 600)
    :ok = Party.open_fight(key, a, %{hp: 900, maxHp: 900, xp: 10, gold: 10, awaken_extra: 600})
    # người thường vào: không cộng
    assert {:ok, %{hp: 900, max: 900}} = Party.join_fight(key, b, 0)
    # người mạnh thứ hai: cộng 600
    assert {:ok, %{hp: 1500, max: 1500, n: 3}} = Party.join_fight(key, c, 600)
    assert {:ok, %{max: 1500}} = Party.join_fight(key, c, 600)
    assert %{hp: 1500, max: 1500} = Party.fight(key)
    leave_all([a, b, c])
  end
end

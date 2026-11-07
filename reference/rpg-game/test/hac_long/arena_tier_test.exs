defmodule HacLong.ArenaTierTest do
  # DECISIONS "Đấu trường: chỉ thách cùng hạng hoặc hạng trên": hạng theo số lần chuyển sinh (khoảng của phòng sự
  # kiện), không thách người hạng dưới, không thách nhân vật cùng tài khoản
  use HacLong.DataCase, async: false

  alias HacLong.{Accounts, Arena}
  alias HacLong.Game.{Characters, Commands}

  defp hero(rebirths, acct \\ nil) do
    uid =
      case acct do
        nil ->
          {:ok, u} =
            Accounts.register(%{
              "username" => "dt#{System.unique_integer([:positive])}",
              "password" => "matkhau1"
            })

          u.id

        a ->
          {:ok, id} = Accounts.character_slot(a)
          id
      end

    {_, p} =
      Commands.run(nil, %{"act" => "create", "name" => "Dt#{rem(uid, 100_000)}x", "cls" => "dk"})

    Characters.save!(uid, Map.put(p, :rebirths, rebirths), "TEST")
    uid
  end

  test "cùng hạng hoặc hạng trên thì được; hạng dưới thì không; gợi ý / tìm cũng vậy" do
    me = hero(2)
    same = hero(3)
    above = hero(10)
    below = hero(1)

    assert Arena.tier_label(me) == "CS 2–3" and Arena.min_rebirths(me) == 2
    assert {:ok, _, _} = Arena.challenge(me, same)
    assert {:ok, _, _} = Arena.challenge(me, above)
    assert {:error, "Chỉ thách đấu người cùng hạng" <> _} = Arena.challenge(me, below)
    # người hạng dưới thách lên thì được
    assert {:ok, _, _} = Arena.challenge(below, me)

    ids = Enum.map(Arena.suggestions(me, 50), & &1.user_id)
    refute below in ids
    assert same in ids and above in ids
  end

  test "không thách đấu nhân vật cùng tài khoản" do
    a = hero(0)
    acct = Accounts.get_user(a)
    b = hero(0, acct)
    assert {:error, "Không thách đấu nhân vật cùng tài khoản."} = Arena.challenge(a, b)
    refute b in Enum.map(Arena.suggestions(a, 200), & &1.user_id)
  end
end

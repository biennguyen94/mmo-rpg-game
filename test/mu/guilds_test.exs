defmodule Mu.GuildsTest do
  @moduledoc "P4-M3 (P4-5): tầng DB của guild — tạo (cấp + Zen, một transaction), thành viên, vai trò."
  use Mu.DataCase, async: true

  alias Mu.Guilds
  alias Mu.Game.Config

  defp char(level, zen) do
    {_, c} = create_character()
    Mu.Repo.update!(Ecto.Changeset.change(c, level: level, zen: zen))
  end

  defp gname, do: "G#{rem(System.unique_integer([:positive]), 1_000_000)}"

  test "tạo: đủ cấp + Zen → master, trừ Zen, version + 1" do
    cost = Config.get(["guild", "createZen"])
    c = char(Config.get(["guild", "createLevel"]), cost + 5)
    name = gname()

    assert {:ok, %{name: ^name, role: "master", guild_id: gid}, %{zen: 5, version: v}} =
             Guilds.create(c.id, name)

    assert v == c.version + 1
    assert Mu.Repo.get(Mu.Game.Character, c.id).zen == 5
    assert %{guild_id: ^gid, role: "master"} = Guilds.membership(c.id)
    assert [%{name: cn, role: "master"}] = Guilds.members(gid)
    assert cn == c.name
  end

  test "tạo: sai tên / thiếu cấp / thiếu Zen / đã có guild / trùng tên (không phân biệt hoa thường)" do
    lvl = Config.get(["guild", "createLevel"])
    cost = Config.get(["guild", "createZen"])
    c = char(lvl, cost * 3)

    for bad <- ["ab", "abcdefghi", "a b c", "ạbc", nil] do
      assert {:error, "INVALID_TARGET"} = Guilds.create(c.id, bad)
    end

    assert {:error, "REQUIREMENT_NOT_MET"} = Guilds.create(char(lvl - 1, cost).id, gname())
    assert {:error, "NOT_ENOUGH_ZEN"} = Guilds.create(char(lvl, cost - 1).id, gname())

    name = gname()
    assert {:ok, _, _} = Guilds.create(c.id, name)
    assert {:error, "FORBIDDEN"} = Guilds.create(c.id, gname())
    assert {:error, "FORBIDDEN"} = Guilds.create(char(lvl, cost).id, String.downcase(name))
    # lỗi không trừ Zen
    assert Mu.Repo.get(Mu.Game.Character, c.id).zen == cost * 2
  end

  test "thành viên: thêm, đầy, phó guild tối đa, rời (master không), giải tán" do
    c = char(Config.get(["guild", "createLevel"]), Config.get(["guild", "createZen"]))
    {:ok, %{guild_id: gid}, _} = Guilds.create(c.id, gname())
    max = Config.get(["guild", "maxMembers"])
    others = for _ <- 1..(max - 1), do: char(1, 0)

    for o <- others, do: assert(:ok = Guilds.add_member(gid, o.id))
    assert Guilds.count(gid) == max
    assert {:error, "FORBIDDEN"} = Guilds.add_member(gid, char(1, 0).id)
    assert {:error, "FORBIDDEN"} = Guilds.add_member(gid, hd(others).id)

    {as, [m | _]} = Enum.split(others, Config.get(["guild", "maxAssistants"]))
    for a <- as, do: assert(:ok = Guilds.set_role(gid, a.id, "assistant"))
    assert {:error, "FORBIDDEN"} = Guilds.set_role(gid, m.id, "assistant")
    assert {:error, "INVALID_TARGET"} = Guilds.set_role(gid, c.id, "member")
    assert ["master" | _] = Enum.map(Guilds.members(gid), & &1.role)

    assert {:error, "INVALID_TARGET"} = Guilds.remove_member(c.id)
    assert :ok = Guilds.remove_member(m.id)
    assert Guilds.membership(m.id) == nil

    assert :ok = Guilds.disband(gid)
    assert Guilds.membership(c.id) == nil
    assert Guilds.get(gid) == nil
  end
end

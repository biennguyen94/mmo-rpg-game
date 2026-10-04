defmodule Mu.Game.GuildWarTest do
  @moduledoc "P4-6: luật guild war thuần (lời mời, một war / guild, điểm, hết giờ, đầu hàng)."
  use ExUnit.Case, async: true

  alias Mu.Game.{Config, GuildWar}

  defp war(a \\ :a, b \\ :b) do
    {:ok, st} = GuildWar.declare(GuildWar.new(), a, b, 0)
    {:ok, w, st} = GuildWar.accept(st, b, a, 1)
    {w, st}
  end

  test "tuyên chiến → nhận: hai guild là địch; lời mời hết hạn / không có → INVALID_TARGET" do
    assert {:error, "INVALID_TARGET"} = GuildWar.declare(GuildWar.new(), :a, :a, 0)
    {:ok, st} = GuildWar.declare(GuildWar.new(), :a, :b, 0)
    late = Config.get(["guildWar", "inviteSeconds"]) * 1000
    assert {:error, "INVALID_TARGET"} = GuildWar.accept(st, :b, :a, late)
    assert {:error, "INVALID_TARGET"} = GuildWar.accept(st, :a, :b, 1)
    {:ok, w, st} = GuildWar.accept(st, :b, :a, 1)

    assert {GuildWar.enemy(st, :a), GuildWar.enemy(st, :b), GuildWar.enemy(st, :c)} ==
             {:b, :a, nil}

    assert w.score == %{a: 0, b: 0}
    assert w.ends_at == 1 + Config.get(["guildWar", "durationMinutes"]) * 60_000
  end

  test "từ chối; mỗi guild một war; nhận war thì lời mời khác của hai guild mất" do
    {:ok, st} = GuildWar.declare(GuildWar.new(), :a, :b, 0)
    assert {:ok, st0} = GuildWar.decline(st, :b, :a, 1)
    assert {:error, "INVALID_TARGET"} = GuildWar.accept(st0, :b, :a, 2)

    {:ok, st} = GuildWar.declare(st, :c, :b, 0)
    {:ok, st} = GuildWar.declare(st, :a, :d, 0)
    {:ok, _, st} = GuildWar.accept(st, :b, :a, 1)
    assert {:error, "FORBIDDEN"} = GuildWar.declare(st, :c, :a, 2)
    assert {:error, "FORBIDDEN"} = GuildWar.declare(st, :b, :d, 2)
    refute GuildWar.requested?(st, :b, :c, 2)
    refute GuildWar.requested?(st, :d, :a, 2)
  end

  test "kill +1; đạt scoreToWin thì thắng; guild ngoài war → :none" do
    {_, st} = war()
    assert :none = GuildWar.kill(st, :a, :c)
    assert :none = GuildWar.kill(st, :c, :a)
    {:ok, w, st} = GuildWar.kill(st, :b, :a)
    assert w.score == %{a: 0, b: 1}
    goal = Config.get(["guildWar", "scoreToWin"])

    st =
      Enum.reduce(1..(goal - 1), st, fn _, st ->
        {:ok, _, st} = GuildWar.kill(st, :a, :b)
        st
      end)

    assert {:ended, w, :a, "score", st} = GuildWar.kill(st, :a, :b)
    assert w.score == %{a: goal, b: 1}
    refute GuildWar.at_war?(st, :a) or GuildWar.at_war?(st, :b)
  end

  test "hết giờ: điểm cao thắng, bằng hòa; đầu hàng → bên kia thắng" do
    {w, st} = war()
    {:ok, _, st} = GuildWar.kill(st, :b, :a)
    assert {[], ^st} = GuildWar.expire(st, w.ends_at - 1)
    assert {[{_, :b}], st2} = GuildWar.expire(st, w.ends_at)
    refute GuildWar.at_war?(st2, :a)

    {w, st} = war(:c, :d)
    assert {[{_, nil}], _} = GuildWar.expire(st, w.ends_at)
    assert {:ended, _, :d, "surrender", st} = GuildWar.surrender(st, :c)
    assert :none = GuildWar.surrender(st, :c)
  end
end

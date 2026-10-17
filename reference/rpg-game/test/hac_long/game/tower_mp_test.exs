defmodule HacLong.Game.TowerMpTest do
  @moduledoc "MP kỹ năng tháp nhân hệ số theo lớp (`RULES.tower_skills.mp_mult`): Kiếm Sĩ, Tiên Nữ rẻ hơn; kỹ năng lớp không đổi."
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine}

  defp hero(cls) do
    {:ok, p} = Engine.new_player("Mp", cls)
    %{p | level: 50}
  end

  test "kỹ năng tháp: Kiếm Sĩ ×0,5, Tiên Nữ ×0,6, Pháp Sư ×1; kỹ năng lớp giữ nguyên" do
    base = fn cls -> Data.class(cls).tower_skills |> List.last() end
    raw = fn p, k -> round(k.mp * (1 + Data.rules().combat.skill_mp_per_level * 49)) end

    for {cls, mult} <- [{"dk", 0.5}, {"elf", 0.6}, {"dw", 1}] do
      p = hero(cls)
      k = base.(cls)

      assert Engine.skill_mp(p, k) ==
               round(k.mp * (1 + Data.rules().combat.skill_mp_per_level * 49) * mult)

      first = hd(Data.class(cls).skills)
      assert Engine.skill_mp(p, first) == raw.(p, first)
    end
  end
end

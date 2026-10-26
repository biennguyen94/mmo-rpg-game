defmodule HacLong.Game.TowerMpTest do
  @moduledoc "MP kỹ năng nhân hệ số theo lớp (`RULES.tower_skills.mp_mult`): Kiếm Sĩ, Tiên Nữ rẻ hơn, cả kỹ năng lớp lẫn tháp."
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine}

  defp hero(cls) do
    {:ok, p} = Engine.new_player("Mp", cls)
    HacLong.Game.Mastery.maxed(%{p | level: 50})
  end

  test "mọi kỹ năng (lớp + tháp): Kiếm Sĩ ×0,5, Tiên Nữ ×0,6, Phù Thủy ×1" do
    cost = fn k, mult ->
      round(k.mp * (1 + Data.rules().combat.skill_mp_per_level * 49) * mult)
    end

    for {cls, mult} <- [{"dk", 0.5}, {"elf", 0.6}, {"dw", 1}] do
      p = hero(cls)
      tower = Data.class(cls).tower_skills |> List.last()
      first = hd(Data.class(cls).skills)

      assert Engine.skill_mp(p, tower) == cost.(tower, mult)
      assert Engine.skill_mp(p, first) == cost.(first, mult)
    end
  end
end

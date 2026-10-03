defmodule Mu.Game.Stats do
  @moduledoc """
  Chỉ số suy ra của nhân vật (`KB_GAME_DESIGN §1`, `§4.1`). Hàm thuần.

  M1 chỉ cần HP/MP tối đa (tạo nhân vật). Các chỉ số chiến đấu (`attackPower`, `defense`,
  `attackRate`...) thêm ở M3 cùng Engine.
  """

  alias Mu.Game.Data

  @doc "`hpBase + (level - 1) × hpPerLevel + vitality × hpPerVit` (làm tròn xuống)."
  def hp_max(class_id, level, vitality) do
    c = Data.class(class_id)
    floor(c["hpBase"] + (level - 1) * c["hpPerLevel"] + vitality * c["hpPerVit"])
  end

  @doc "`mpBase + (level - 1) × mpPerLevel + energy × mpPerEne` (làm tròn xuống)."
  def mp_max(class_id, level, energy) do
    c = Data.class(class_id)
    floor(c["mpBase"] + (level - 1) * c["mpPerLevel"] + energy * c["mpPerEne"])
  end

  @doc "Điểm đã nhận theo cấp: `(level - 1) × statPerLevel` (§1)."
  def earned_points(class_id, level), do: (level - 1) * Data.class(class_id)["statPerLevel"]
end

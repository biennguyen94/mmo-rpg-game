defmodule Mu.Game.Upgrade do
  @moduledoc """
  Ép jewel lên đồ (`KB_GAME_DESIGN §8` Upgrade, bảng `KB_CONFIG §5` = config `upgrade.levels`;
  P5-3, P5-4 (A)), **hàm thuần** (RNG truyền vào / trả ra).

  - Đồ ép được: type có trong `items.levelBonus` (vũ khí, khiên, giáp); nhẫn / jewel / potion thì
    `INVALID_TARGET`.
  - Bless / Soul: dòng bảng có `fromLevel` = cấp hiện tại; jewel phải nằm trong `requires` (sai loại
    → `INVALID_TARGET`); không còn dòng (đã +9) → `FORBIDDEN`. Thành công → `toLevel`; thất bại theo
    `onFailure`: `UNCHANGED` giữ cấp, `DECREASE` giảm 1 cấp, `DESTROY` mất đồ.
  - Life (`upgrade.life`; type trong `excludeTypes` — cánh — thì `INVALID_TARGET`): `option` + 1 với `successRate`, tối đa `maxOption` (đủ → `FORBIDDEN`),
    thất bại `onFailure`.

  Kết quả: `{:ok, %{ok: bool, level, option, destroyed: bool}, rng}` hoặc `{:error, code}`.
  """

  alias Mu.Game.{Config, Rng}

  @doc """
  Cấp + và option tối đa đồ `template` có thể đạt (theo `upgrade.levels` / `upgrade.life`):
  `{max_level, max_option}` — `{0, 0}` nếu không ép được (nhẫn, jewel, potion). Quản trị tặng đồ
  (`Mu.Admin.give_item/3`, DEC-188) dùng để chặn.
  """
  def limits(template) do
    life = Config.get(["upgrade", "life"])

    if Config.get(["items", "levelBonus"])[template["type"]] == nil do
      {0, 0}
    else
      max_level = Config.get(["upgrade", "levels"]) |> Enum.map(& &1["toLevel"]) |> Enum.max()
      no_option? = template["type"] in (life["excludeTypes"] || [])
      {max_level, if(no_option?, do: 0, else: life["maxOption"])}
    end
  end

  @doc "Đồ `template` (đang +`level`, option `option`) có ép được bằng jewel `jewel_id` không."
  def apply(rng, template, level, option, jewel_id) do
    life = Config.get(["upgrade", "life"])

    cond do
      Config.get(["items", "levelBonus"])[template["type"]] == nil ->
        {:error, "INVALID_TARGET"}

      # cánh không có option Life (P6-4 (3))
      jewel_id == life["jewel"] and template["type"] in (life["excludeTypes"] || []) ->
        {:error, "INVALID_TARGET"}

      jewel_id == life["jewel"] ->
        life(rng, life, level, option)

      true ->
        level(rng, level, option, jewel_id)
    end
  end

  defp level(rng, level, option, jewel_id) do
    rows = Config.get(["upgrade", "levels"])

    case Enum.find(rows, &(&1["fromLevel"] == level)) do
      nil ->
        if Enum.any?(rows, &(jewel_id in &1["requires"])),
          do: {:error, "FORBIDDEN"},
          else: {:error, "INVALID_TARGET"}

      row ->
        if jewel_id in row["requires"] do
          {ok?, rng} = Rng.chance(rng, row["successRate"])

          result =
            if ok?,
              do: %{ok: true, level: row["toLevel"], option: option, destroyed: false},
              else: failed(row["onFailure"], level, option, :level)

          {:ok, result, rng}
        else
          {:error, "INVALID_TARGET"}
        end
    end
  end

  defp life(rng, life, level, option) do
    if option >= life["maxOption"] do
      {:error, "FORBIDDEN"}
    else
      {ok?, rng} = Rng.chance(rng, life["successRate"])

      result =
        if ok?,
          do: %{ok: true, level: level, option: option + 1, destroyed: false},
          else: failed(life["onFailure"], level, option, :option)

      {:ok, result, rng}
    end
  end

  defp failed("UNCHANGED", level, option, _),
    do: %{ok: false, level: level, option: option, destroyed: false}

  defp failed("DECREASE", level, option, :level),
    do: %{ok: false, level: max(level - 1, 0), option: option, destroyed: false}

  defp failed("DECREASE", level, option, :option),
    do: %{ok: false, level: level, option: max(option - 1, 0), destroyed: false}

  defp failed("DESTROY", level, option, _),
    do: %{ok: false, level: level, option: option, destroyed: true}
end

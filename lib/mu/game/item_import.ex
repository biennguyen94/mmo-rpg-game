defmodule Mu.Game.ItemImport do
  @moduledoc """
  Kiểm tra + chuẩn hóa template item từ `data/items/*.json` (nguồn) thành
  `priv/game_data/items.json` (server đọc lúc biên dịch). Hàm thuần; `mix mu.items.import` gọi.

  Luật (`KB_ITEM_REFERENCE §3, §6`):
  - `templateId` duy nhất; `iconRef` có `group`+`index` hoặc `custom`;
  - bản ghi có `reference.adjusted` phải là `IMPLEMENTATION`;
  - `requirements` = `round_half_up(requirementsRaw × items.requirementScale)` (trừ `level`);
  - không dùng group 12 khi `features.wings = false`; class chỉ trong `DW, DK, ELF, MG`;
  - `slot` thuộc `KB_CONFIG §6` hoặc `null` (tiêu hao).

  Chuẩn hóa: `sellPrice = floor(buyPrice × economy.sellRatio)` (D6); `version`, `verified`,
  `source` lấy từ `reference` (D5; bản ghi tự tạo: `null`, `false`, `null`).
  """

  alias Mu.Game.Config

  @slots ~w(HELM ARMOR PANTS GLOVES BOOTS WEAPON SHIELD WING RING1 RING2)
  @classes ~w(DW DK ELF MG)
  @stats ~w(strength agility energy vitality)

  @doc "`{:ok, templates}` hoặc `{:error, [lỗi]}`."
  def build(%{"items" => items}) do
    errors =
      duplicate_ids(items) ++ Enum.flat_map(items, &check/1)

    if errors == [], do: {:ok, Enum.map(items, &normalize/1)}, else: {:error, errors}
  end

  defp duplicate_ids(items) do
    items
    |> Enum.frequencies_by(& &1["templateId"])
    |> Enum.filter(fn {_, n} -> n > 1 end)
    |> Enum.map(fn {id, _} -> "#{id}: templateId trùng" end)
  end

  defp check(t) do
    id = t["templateId"]
    ref = t["reference"]

    [
      is_binary(id) || "templateId thiếu",
      t["sourceType"] in ~w(REFERENCE IMPLEMENTATION CONFIG) || "#{id}: sourceType sai",
      icon_ok?(t["iconRef"]) || "#{id}: iconRef phải có group+index hoặc custom",
      t["slot"] in [nil | @slots] || "#{id}: slot #{inspect(t["slot"])} không thuộc KB_CONFIG §6",
      Enum.all?(t["classes"] || [], &(&1 in @classes)) || "#{id}: class ngoài scope",
      not (is_map(ref) and ref["adjusted"] != nil and t["sourceType"] != "IMPLEMENTATION") ||
        "#{id}: có reference.adjusted nhưng không phải IMPLEMENTATION",
      wings_ok?(t) || "#{id}: group 12 (wing) khi features.wings = false",
      requirements_ok?(t) || "#{id}: requirements khác round(requirementsRaw × requirementScale)",
      is_integer(t["buyPrice"]) || "#{id}: thiếu buyPrice",
      (t["stackable"] == true and is_integer(t["maxStack"])) or t["stackable"] == false ||
        "#{id}: stackable/maxStack sai"
    ]
    |> Enum.reject(&(&1 == true))
  end

  defp icon_ok?(%{"custom" => c}) when is_binary(c), do: true
  defp icon_ok?(%{"group" => g, "index" => i}) when is_integer(g) and is_integer(i), do: true
  defp icon_ok?(_), do: false

  defp wings_ok?(t) do
    Config.get(["features", "wings"]) or get_in(t, ["iconRef", "group"]) != 12
  end

  defp requirements_ok?(%{"reference" => %{"requirementsRaw" => raw}, "requirements" => req}) do
    scale = Config.get(["items", "requirementScale"])

    req["level"] == raw["level"] and
      Enum.all?(@stats, &(req[&1] == round_half_up(raw[&1] * scale)))
  end

  defp requirements_ok?(_), do: true

  @doc "Làm tròn half-up (0.5 → 1), như KB_ITEM_REFERENCE §3.2."
  def round_half_up(x), do: floor(x + 0.5)

  defp normalize(t) do
    ref = t["reference"]

    t
    |> Map.put("sellPrice", floor(t["buyPrice"] * Config.get(["economy", "sellRatio"])))
    |> Map.put("version", if(is_map(ref), do: ref["version"]))
    |> Map.put("verified", if(is_map(ref), do: ref["verified"] == true, else: false))
    |> Map.put("source", if(is_map(ref), do: ref["source"]))
  end
end

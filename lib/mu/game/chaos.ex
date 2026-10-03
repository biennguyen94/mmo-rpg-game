defmodule Mu.Game.Chaos do
  @moduledoc """
  Chaos Machine (P6-M3, P6-3) — **hàm thuần** (RNG truyền vào / trả ra). Công thức ở
  `priv/game_data/chaos.json`.

  Đầu vào là các món người chơi đặt vào máy (tối đa `chaos.maxItems`), mỗi món
  `%{id, template_id, quantity, item_level, option_level}`. Một công thức khớp khi **mọi** món
  đặt vào được dùng hết bởi các dòng `inputs`, đủ `count` mỗi dòng:
  - `{types, minLevel, count}`: `count` món (không xếp chồng) có type trong `types`, +`minLevel` trở lên;
  - `{templateId, count}`: `count` cái template đó (lấy từ stack; dư trong stack thì giữ lại).

  Tỉ lệ = `base + perLevel × (cấp − fromLevel) + perOption × option` của món đồ chính, tối đa
  `max`. Thành công → một món ngẫu nhiên trong `outputs`; thất bại → mất hết đầu vào (`LOSE_ALL`).
  """

  alias Mu.Game.{Config, Data, Rng}

  @doc """
  `{:ok, %{recipe, rate, zen, consume: [{item_id, số}]}}` hoặc `{:error, code}` — quá
  `chaos.maxItems` món / trùng món / không khớp công thức nào → `INVALID_TARGET`.
  """
  def match(items) do
    ids = Enum.map(items, & &1.id)

    cond do
      items == [] or length(items) > Config.get(["chaos", "maxItems"]) ->
        {:error, "INVALID_TARGET"}

      length(Enum.uniq(ids)) != length(ids) ->
        {:error, "INVALID_TARGET"}

      true ->
        Enum.find_value(Data.chaos_recipes(), {:error, "INVALID_TARGET"}, &try_recipe(&1, items))
    end
  end

  defp try_recipe(r, items) do
    result =
      Enum.reduce_while(r["inputs"], {items, [], nil}, fn input, {left, consume, main} ->
        case take(input, left) do
          {:ok, used, left} ->
            main = main || if(input["types"], do: elem(hd(used), 0))
            {:cont, {left, consume ++ Enum.map(used, fn {it, n} -> {it.id, n} end), main}}

          :error ->
            {:halt, :error}
        end
      end)

    case result do
      {[], consume, main} ->
        {:ok, %{recipe: r, rate: rate(r, main), zen: r["zen"], consume: consume}}

      _ ->
        nil
    end
  end

  # dòng đồ theo type: đúng `count` món, mỗi món một cái
  defp take(%{"types" => types, "minLevel" => min, "count" => n}, items) do
    {ok, rest} =
      Enum.split_with(items, fn it ->
        t = Data.item(it.template_id) || %{}
        t["type"] in types and it.item_level >= min and it.quantity == 1
      end)

    if length(ok) == n, do: {:ok, Enum.map(ok, &{&1, 1}), rest}, else: :error
  end

  # dòng template: một stack đủ `count` (lấy `count` cái)
  defp take(%{"templateId" => tid, "count" => n}, items) do
    {ok, rest} = Enum.split_with(items, &(&1.template_id == tid))

    case ok do
      [it] when it.quantity >= n -> {:ok, [{it, n}], rest}
      _ -> :error
    end
  end

  defp rate(%{"rate" => r}, main) do
    level = if main, do: main.item_level, else: 0
    option = if main, do: Map.get(main, :option_level, 0), else: 0
    p = r["base"] + r["perLevel"] * max(level - r["fromLevel"], 0) + r["perOption"] * option
    min(Float.round(p, 4), r["max"])
  end

  @doc "Quay kết quả: `{template_id | nil, rng}` (`nil` = thất bại)."
  def roll(rng, %{recipe: r, rate: rate}) do
    {ok?, rng} = Rng.chance(rng, rate)

    if ok? do
      {i, rng} = Rng.int(rng, 0, length(r["outputs"]) - 1)
      {Enum.at(r["outputs"], i), rng}
    else
      {nil, rng}
    end
  end
end

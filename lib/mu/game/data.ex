defmodule Mu.Game.Data do
  @moduledoc """
  Dữ liệu gameplay tĩnh, đọc lúc biên dịch từ `priv/game_data/*.json` (học từ
  `HacLong.Game.Data` của repo nền, tách file theo loại như KB_TECH_STACK §7).

  Mỗi bản ghi phải có `sourceType`, `version`, `verified` (`KB_00_RULES §2`); thiếu thì
  biên dịch lỗi. Khóa giữ nguyên dạng chuỗi như trong JSON.
  """

  @dir Path.expand("../../../priv/game_data", __DIR__)
  @classes_path Path.join(@dir, "classes.json")
  @external_resource @classes_path

  @required ~w(sourceType version verified)

  check = fn path, records ->
    for r <- records, key <- @required, not Map.has_key?(r, key) do
      raise "#{path}: bản ghi #{inspect(r["id"])} thiếu trường #{key} (KB_00_RULES §2)"
    end

    records
  end

  @classes @classes_path
           |> File.read!()
           |> Jason.decode!()
           |> Map.fetch!("classes")
           |> then(&check.(@classes_path, &1))
           |> Map.new(&{&1["id"], &1})

  @doc "Các class đang có dữ liệu (Phase 1: chỉ DK)."
  def classes, do: @classes

  @doc "Class theo id (`\"DK\"`), `nil` nếu không có."
  def class(id), do: Map.get(@classes, id)
end

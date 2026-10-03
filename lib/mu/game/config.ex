defmodule Mu.Game.Config do
  @moduledoc """
  Server CONFIG (`KB_CONFIG §1`), đọc lúc biên dịch từ `priv/game_data/config.json`.
  Sửa file đó rồi biên dịch lại là có hiệu lực.

      Mu.Game.Config.get(["server", "clientVersion"])  #=> "0.1.0"

  Khóa thiếu là lỗi lập trình nên `get/1` raise thay vì trả `nil` (không có số mặc định ẩn
  trong code: `CLAUDE.md` §4).
  """

  @path Path.expand("../../../priv/game_data/config.json", __DIR__)
  @external_resource @path

  @config @path |> File.read!() |> Jason.decode!()

  for key <- ~w(sourceType version verified source) do
    Map.has_key?(@config, key) || raise "#{@path}: thiếu trường #{key} (KB_00_RULES §2)"
  end

  @doc "Toàn bộ config (map khóa chuỗi)."
  def all, do: @config

  @doc "Giá trị tại đường dẫn `path` (danh sách khóa chuỗi). Raise nếu không có."
  def get(path) when is_list(path) do
    Enum.reduce(path, @config, fn key, acc ->
      case acc do
        %{^key => v} -> v
        _ -> raise ArgumentError, "config.json không có khóa #{Enum.join(path, ".")}"
      end
    end)
  end
end

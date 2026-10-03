defmodule Mix.Tasks.Mu.Items.Import do
  @shortdoc "Kiểm tra data/items/*.json và sinh priv/game_data/items.json"
  @moduledoc """
      mix mu.items.import          # ghi priv/game_data/items.json
      mix mu.items.import --check  # chỉ kiểm, lệch/lỗi thì exit 1 (CI)

  Luật kiểm tra và chuẩn hóa: `Mu.Game.ItemImport`. Đổi `items.requirementScale` thì sửa
  `data/items/*.json` theo rồi chạy lại.
  """
  use Mix.Task

  alias Mu.Game.ItemImport

  @impl true
  def run(args) do
    check? = "--check" in args
    root = File.cwd!()
    sources = Path.wildcard(Path.join(root, "data/items/*.json"))
    out = Path.join(root, "priv/game_data/items.json")

    items =
      Enum.flat_map(sources, &(&1 |> File.read!() |> Jason.decode!() |> Map.fetch!("items")))

    case ItemImport.build(%{"items" => items}) do
      {:error, errors} ->
        Enum.each(errors, &Mix.shell().error/1)
        exit({:shutdown, 1})

      {:ok, templates} ->
        json =
          Jason.encode_to_iodata!(
            %{
              "source" =>
                "Sinh bởi `mix mu.items.import` từ data/items/*.json — KHÔNG sửa tay. Xem Mu.Game.ItemImport.",
              "items" => templates
            },
            pretty: true
          )

        json = IO.iodata_to_binary([json, "\n"])

        cond do
          File.exists?(out) and File.read!(out) == json ->
            Mix.shell().info("items.json: không đổi (#{length(templates)} template)")

          check? ->
            Mix.shell().error("items.json lệch với data/items: chạy mix mu.items.import")
            exit({:shutdown, 1})

          true ->
            File.write!(out, json)
            Mix.shell().info("items.json: đã ghi #{length(templates)} template")
        end
    end
  end
end

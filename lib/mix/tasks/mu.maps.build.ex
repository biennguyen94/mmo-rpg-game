defmodule Mix.Tasks.Mu.Maps.Build do
  @shortdoc "Sinh priv/maps/<id>.collision.bin từ priv/maps/<id>.json"
  @moduledoc """
  Sinh file collision cho mọi map (`KB_TECHNICAL §8`, định dạng: `Mu.World.Collision`).

      mix mu.maps.build          # ghi file
      mix mu.maps.build --check  # chỉ kiểm, lệch thì exit 1 (dùng trong CI)

  Pipeline Tiled (`.tmj` → JSON) để sau Phase 1; hiện map JSON viết tay.
  """
  use Mix.Task

  alias Mu.World.Collision

  @impl true
  def run(args) do
    check? = "--check" in args
    dir = Path.join(File.cwd!(), "priv/maps")

    stale =
      for json <- Path.wildcard(Path.join(dir, "*.json")), reduce: [] do
        acc ->
          map = json |> File.read!() |> Jason.decode!()
          out = Path.join(dir, map["collision"])
          bin = Collision.from_map(map)

          cond do
            File.exists?(out) and File.read!(out) == bin ->
              Mix.shell().info("#{map["collision"]}: không đổi")
              acc

            check? ->
              Mix.shell().error("#{map["collision"]}: lệch với #{Path.basename(json)}")
              [out | acc]

            true ->
              File.write!(out, bin)
              Mix.shell().info("#{map["collision"]}: đã ghi #{byte_size(bin)} byte")
              acc
          end
      end

    if stale != [], do: exit({:shutdown, 1})
  end
end

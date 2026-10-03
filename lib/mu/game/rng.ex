defmodule Mu.Game.Rng do
  @moduledoc """
  Bộ sinh số ngẫu nhiên có trạng thái tường minh (truyền vào/trả ra), để Engine là hàm thuần
  và test lặp lại được với seed cố định. Học ý tưởng từ `HacLong.Game.Rng` của repo nền
  (ở đó là dãy số cố định); ở đây dùng `:rand` thuật toán `exsss` với seed.

      rng = Rng.new(42)
      {x, rng} = Rng.uniform(rng)        # 0.0 <= x < 1.0
      {n, rng} = Rng.int(rng, 8, 14)     # 8..14
  """

  @opaque t :: :rand.state()

  @doc "RNG từ seed (số nguyên). Không seed: lấy ngẫu nhiên từ hệ thống."
  def new(seed \\ :erlang.unique_integer() + System.os_time()) when is_integer(seed),
    do: :rand.seed_s(:exsss, seed)

  @doc "Số thực trong [0, 1)."
  def uniform(rng) do
    # :rand.uniform_s/1 trả số trong [0.0, 1.0)
    :rand.uniform_s(rng)
  end

  @doc "Số nguyên đều trong `min..max` (gồm hai đầu)."
  def int(rng, min, max) when min <= max do
    {n, rng} = :rand.uniform_s(max - min + 1, rng)
    {min + n - 1, rng}
  end

  @doc "`true` với xác suất `p`."
  def chance(rng, p) do
    {x, rng} = uniform(rng)
    {x < p, rng}
  end

  @doc "Chọn một phần tử theo trọng số: `entries` là `[{phần_tử, weight}]` (weight > 0)."
  def weighted(rng, entries) do
    total = entries |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    {n, rng} = int(rng, 1, total)

    {item, _} =
      Enum.reduce_while(entries, {nil, n}, fn {item, w}, {_, left} ->
        if left <= w, do: {:halt, {item, 0}}, else: {:cont, {nil, left - w}}
      end)

    {item, rng}
  end
end

defmodule Mu.Game.Commands do
  @moduledoc """
  Lệnh `cmd` từ client (`KB_TECHNICAL §5`): `{act, rid, ...}`. Module này kiểm tra phong bì
  lệnh và giới hạn tần suất theo nhóm `act` (`rateLimit.cmd` trong config, P8). Xử lý từng
  `act` thêm ở M2–M4; act chưa làm trả `FORBIDDEN`.
  """

  alias Mu.Game.Config

  @rid_max 64

  @doc "Các `act` hợp lệ theo §5 (gom từ các nhóm rate-limit)."
  def acts do
    Config.get(["rateLimit", "cmd", "categories"])
    |> Enum.flat_map(fn {_, c} -> c["acts"] end)
  end

  @doc "`{:ok, act, rid}` hoặc `{:error, rid_hoặc_nil, code}`."
  def envelope(%{"act" => act, "rid" => rid})
      when is_binary(act) and is_binary(rid) and byte_size(rid) in 1..@rid_max do
    if act in acts(), do: {:ok, act, rid}, else: {:error, rid, "FORBIDDEN"}
  end

  def envelope(%{"rid" => rid}) when is_binary(rid) and byte_size(rid) in 1..@rid_max,
    do: {:error, rid, "FORBIDDEN"}

  def envelope(_), do: {:error, nil, "FORBIDDEN"}

  @doc "Nhóm rate-limit của `act`: `{tên, limit, windowMs}`."
  def category(act) do
    Config.get(["rateLimit", "cmd", "categories"])
    |> Enum.find_value(fn {name, c} ->
      if act in c["acts"], do: {name, c["limit"], c["windowMs"]}
    end)
  end

  @doc "Đếm một lệnh `act` của tài khoản: `:ok` hoặc `{:error, \"RATE_LIMITED\", window_ms}`."
  def rate_limit(account_id, act) do
    {name, limit, window} = category(act)

    case Mu.RateLimit.hit({:cmd, account_id, name}, limit, window) do
      :ok -> :ok
      {:error, _secs} -> {:error, "RATE_LIMITED", window}
    end
  end

  @doc """
  Theo dõi chuỗi vi phạm rate-limit (hàm thuần). `streak` là `nil` hoặc
  `{lần_đầu_ms, lần_cuối_ms}`. Hai vi phạm cách nhau không quá `window_ms` thì cùng một
  chuỗi; chuỗi kéo dài ≥ `rateLimit.cmd.kickAfterMs` thì `{:kick, streak}`.
  """
  def violation(streak, now, window_ms) do
    streak =
      case streak do
        {first, last} when now - last <= window_ms -> {first, now}
        _ -> {now, now}
      end

    {first, _} = streak

    if now - first >= Config.get(["rateLimit", "cmd", "kickAfterMs"]),
      do: {:kick, streak},
      else: {:ok, streak}
  end
end

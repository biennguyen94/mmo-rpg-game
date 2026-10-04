defmodule Mu.Game.Duel do
  @moduledoc """
  Duel (`KB_GAME_DESIGN §13`, P4-4), **hàm thuần** trên trạng thái duel của một map (MapServer
  giữ trong RAM; hai người phải cùng map).

  - `requests`: `%{người_được_mời => %{người_mời => hạn ms}}` (hết hạn sau `duel.inviteSeconds`).
  - `active`: `%{character_id => %{opponent, ends_at, center}}` — mỗi duel có hai mục đối xứng;
    `center` là trung điểm hai người lúc bắt đầu (để biết ai "đi xa").
  - Một người chỉ ở một duel; đang duel thì không mời / nhận thêm.
  """

  alias Mu.Game.Config

  def new, do: %{requests: %{}, active: %{}}

  @doc "Đối thủ đang duel với `cid` (hoặc `nil`)."
  def opponent(d, cid), do: get_in(d, [:active, cid, :opponent])

  def in_duel?(d, cid), do: Map.has_key?(d.active, cid)

  @doc "`from` mời `to`: `{:ok, d}` hoặc `{:error, code}` (một trong hai đang duel)."
  def request(d, from, to, now) do
    cond do
      from == to ->
        {:error, "INVALID_TARGET"}

      in_duel?(d, from) or in_duel?(d, to) ->
        {:error, "FORBIDDEN"}

      true ->
        {:ok, put_in(d, [:requests, Access.key(to, %{}), from], now + seconds("inviteSeconds"))}
    end
  end

  @doc "`to` nhận lời mời của `from` → bắt đầu, hết giờ `now + duel.maxSeconds`."
  def accept(d, to, from, now, center) do
    with {:ok, d} <- take_request(d, to, from, now),
         false <- in_duel?(d, from) or in_duel?(d, to) do
      ends = now + seconds("maxSeconds")
      entry = fn opp -> %{opponent: opp, ends_at: ends, center: center} end
      {:ok, %{d | active: d.active |> Map.put(from, entry.(to)) |> Map.put(to, entry.(from))}}
    else
      true -> {:error, "FORBIDDEN"}
      error -> error
    end
  end

  @doc "`to` từ chối lời mời của `from`."
  def decline(d, to, from, now), do: take_request(d, to, from, now)

  @doc "Người mời hủy mọi lời mời đang chờ của mình: `{d, [người_được_mời]}`."
  def cancel_requests(d, from) do
    tos = for {to, froms} <- d.requests, Map.has_key?(froms, from), do: to
    requests = Map.new(d.requests, fn {to, froms} -> {to, Map.delete(froms, from)} end)
    {%{d | requests: requests}, tos}
  end

  @doc "Kết thúc duel của `cid` (và đối thủ): `{d, đối_thủ | nil}`."
  def finish(d, cid) do
    case opponent(d, cid) do
      nil -> {d, nil}
      opp -> {%{d | active: d.active |> Map.delete(cid) |> Map.delete(opp)}, opp}
    end
  end

  @doc "Duel hết giờ lúc `now`: danh sách cặp `{a, b}` (mỗi cặp một lần)."
  def expired(d, now) do
    for {a, %{opponent: b, ends_at: t}} <- d.active, t <= now, a < b, do: {a, b}
  end

  @doc """
  Cặp đã cách nhau quá `duel.maxDistance` ô (Chebyshev): `[{người_thua, người_thắng}]` — người
  xa `center` hơn thua. `pos.(cid)` trả `{x, y}`.
  """
  def too_far(d, pos) do
    max = Config.get(["duel", "maxDistance"])

    for {a, %{opponent: b, center: c}} <- d.active,
        a < b,
        {pa, pb} = {pos.(a), pos.(b)},
        cheb(pa, pb) > max,
        do: if(cheb(pa, c) >= cheb(pb, c), do: {a, b}, else: {b, a})
  end

  @doc "Bỏ lời mời hết hạn."
  def prune(d, now) do
    requests =
      for {to, froms} <- d.requests,
          live = Map.filter(froms, fn {_, t} -> t > now end),
          map_size(live) > 0,
          into: %{},
          do: {to, live}

    %{d | requests: requests}
  end

  defp take_request(d, to, from, now) do
    case get_in(d, [:requests, to, from]) do
      t when is_integer(t) and t > now ->
        {:ok, update_in(d, [:requests, to], &Map.delete(&1, from))}

      _ ->
        {:error, "INVALID_TARGET"}
    end
  end

  defp cheb({x1, y1}, {x2, y2}), do: max(abs(x1 - x2), abs(y1 - y2))
  defp seconds(key), do: Config.get(["duel", key]) * 1000
end

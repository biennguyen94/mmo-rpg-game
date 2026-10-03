defmodule Mu.Game.GuildWar do
  @moduledoc """
  Guild war (`KB_GAME_DESIGN §13` "hai guild khai chiến, kill không tính PK", P4-6), **hàm thuần**
  (thời gian `now` tính bằng ms do người gọi đưa vào). `Mu.Guild` giữ trạng thái này trong RAM —
  server khởi động lại thì mọi war bị hủy (P4-6 (4)).

  - Lời mời: master guild A tuyên chiến guild B → B có `guildWar.inviteSeconds` để nhận / từ chối.
  - Mỗi guild chỉ một war một lúc (đang war thì không tuyên chiến / nhận được).
  - Mỗi kill người guild địch +1 điểm; kết thúc khi một bên đạt `guildWar.scoreToWin`, hết
    `guildWar.durationMinutes` (điểm cao hơn thắng, bằng thì hòa), hoặc một bên đầu hàng / giải tán.

  Trạng thái:
  - `wars`: `%{guild_id => war}` — mỗi war có hai mục (một cho mỗi guild) trỏ cùng dữ liệu;
    `war = %{a, b, score: %{a => n, b => n}, ends_at}`.
  - `requests`: `%{guild bị mời => %{guild mời => hạn ms}}`.

  Kết thúc trả `{:ended, war, winner | nil, reason}` với `reason` ∈ `"score"`, `"time"`,
  `"surrender"`.
  """

  alias Mu.Game.Config

  def new, do: %{wars: %{}, requests: %{}}

  @doc "Guild địch của `gid` (đang war) hoặc `nil`."
  def enemy(st, gid) do
    case st.wars[gid] do
      %{a: ^gid, b: b} -> b
      %{a: a} -> a
      nil -> nil
    end
  end

  def at_war?(st, gid), do: Map.has_key?(st.wars, gid)

  @doc "Guild `from` tuyên chiến guild `to`: `{:ok, st}` hoặc `{:error, code}`."
  def declare(st, from, to, now) do
    cond do
      from == to -> {:error, "INVALID_TARGET"}
      at_war?(st, from) or at_war?(st, to) -> {:error, "FORBIDDEN"}
      true -> {:ok, put_in(st, [:requests, Access.key(to, %{}), from], now + invite_ms())}
    end
  end

  @doc "Guild `to` nhận lời của `from`: `{:ok, war, st}` hoặc `{:error, code}`."
  def accept(st, to, from, now) do
    with {:ok, st} <- take(st, to, from, now),
         false <- (at_war?(st, from) or at_war?(st, to)) && {:error, "FORBIDDEN"} do
      war = %{
        a: from,
        b: to,
        score: %{from => 0, to => 0},
        ends_at: now + Config.get(["guildWar", "durationMinutes"]) * 60_000
      }

      # lời mời khác liên quan hai guild này hết giá trị
      requests =
        for {t, by} <- Map.drop(st.requests, [from, to]),
            by = Map.drop(by, [from, to]),
            map_size(by) > 0,
            into: %{},
            do: {t, by}

      {:ok, war, %{st | wars: Map.merge(st.wars, %{from => war, to => war}), requests: requests}}
    end
  end

  @doc "Guild `to` từ chối lời của `from`."
  def decline(st, to, from, now), do: take(st, to, from, now)

  @doc """
  Thành viên guild `killer` hạ thành viên guild `victim`: `{:ok, war, st}` (cộng điểm),
  `{:ended, war, winner, "score", st}` hoặc `:none` (hai guild không war với nhau).
  """
  def kill(st, killer, victim) do
    case st.wars[killer] do
      %{a: a, b: b} = war when victim in [a, b] and victim != killer ->
        war = update_in(war.score[killer], &(&1 + 1))

        if war.score[killer] >= Config.get(["guildWar", "scoreToWin"]) do
          {:ended, war, killer, "score", drop(st, war)}
        else
          {:ok, war, %{st | wars: Map.merge(st.wars, %{a => war, b => war})}}
        end

      _ ->
        :none
    end
  end

  @doc "Guild `gid` đầu hàng (hoặc giải tán): `{:ended, war, winner, \"surrender\", st}` hoặc `:none`."
  def surrender(st, gid) do
    case st.wars[gid] do
      nil -> :none
      war -> {:ended, war, other(war, gid), "surrender", drop(st, war)}
    end
  end

  @doc """
  Hết giờ lúc `now`: `{[{war, winner | nil}], st}` (điểm cao hơn thắng, bằng thì hòa); lời mời
  quá hạn bị bỏ.
  """
  def expire(st, now) do
    ended =
      st.wars
      |> Map.values()
      |> Enum.uniq()
      |> Enum.filter(&(&1.ends_at <= now))

    st = Enum.reduce(ended, st, &drop(&2, &1))

    requests =
      for {t, by} <- st.requests,
          live = Map.filter(by, fn {_, until} -> until > now end),
          map_size(live) > 0,
          into: %{},
          do: {t, live}

    {Enum.map(ended, &{&1, leader(&1)}), %{st | requests: requests}}
  end

  @doc "Lời mời đang chờ của guild `to` từ `from` còn hạn không."
  def requested?(st, to, from, now) do
    case Map.fetch(st.requests[to] || %{}, from) do
      {:ok, until} -> until > now
      :error -> false
    end
  end

  def other(%{a: a, b: b}, gid), do: if(gid == a, do: b, else: a)

  # bên điểm cao hơn, bằng nhau → nil (hòa)
  defp leader(%{a: a, b: b, score: sc}) do
    cond do
      sc[a] > sc[b] -> a
      sc[b] > sc[a] -> b
      true -> nil
    end
  end

  defp take(st, to, from, now) do
    if requested?(st, to, from, now) do
      by = Map.delete(st.requests[to], from)

      requests =
        if map_size(by) == 0, do: Map.delete(st.requests, to), else: Map.put(st.requests, to, by)

      {:ok, %{st | requests: requests}}
    else
      {:error, "INVALID_TARGET"}
    end
  end

  defp drop(st, war), do: %{st | wars: Map.drop(st.wars, [war.a, war.b])}

  defp invite_ms, do: Config.get(["guildWar", "inviteSeconds"]) * 1000
end

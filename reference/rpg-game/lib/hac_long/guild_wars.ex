defmodule HacLong.GuildWars do
  @moduledoc """
  Chiến bang trên đấu trường (Phase 5, H5; `INTEGRATION_PLAN.md §13.6`). Số ở `RULES.guild_war`.

  - Bang chủ / phó bang tuyên chiến một bang khác (`declare/2`); bang kia phải có bang chủ / phó bang
    online, và một trong họ nhận (`answer/3`) trong `answer_s` giây. Lời tuyên chiến giữ trong bộ nhớ.
  - Trận chiến lưu ở bảng `guild_wars`, kéo dài `minutes` phút. Mỗi trận **đấu trường thường** mà
    người thách đấu thắng thành viên bang địch (`record/2`, gọi từ Session) là +1 điểm cho bang mình;
    thắng cùng một đối thủ quá `same_target_max` lần thì không tính thêm.
  - Hết giờ (`finish/1`) hoặc đầu hàng (`surrender/1`): bang nhiều điểm thắng (bằng điểm: hòa), báo cả
    server; bang thắng được quỹ +`win_fund`, thành viên có ≥ 1 điểm nhận `win_gold` vàng qua thư.
    Hai bang không chiến lại trong `rematch_hours` giờ.
  - Bang đang chiến hiện trong `HacLong.Guilds.brief/1` (`war`), để tên người bang địch trên bản đồ
    hiện màu đỏ.
  """
  use GenServer
  require Logger
  import Ecto.Query

  alias HacLong.{Chat, Guilds, Mailbox, Repo}
  alias HacLong.Game.{Data, Session}

  @rules Data.rules().guild_war

  def rules, do: @rules

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    # trận còn dở lúc khởi động lại: hẹn giờ kết thúc
    send(self(), :resume)
    {:ok, %{pending: %{}}}
  end

  # ---------- Đọc ----------

  @doc "Trận chiến đang diễn ra của bang `gid` (nil nếu không có)."
  def active(gid) when is_integer(gid) do
    Repo.one(
      from w in "guild_wars",
        where: is_nil(w.result) and (w.a_id == ^gid or w.b_id == ^gid),
        limit: 1,
        select: map(w, [:id, :a_id, :b_id, :a_points, :b_points, :scores, :pairs, :ends_at])
    )
  end

  def active(_), do: nil

  @doc "Tóm tắt trận chiến cho bang `gid`: `%{id, enemy: %{id, name, tag}, mine, theirs, ends_at}` hoặc nil."
  def brief(gid) do
    case active(gid) do
      nil ->
        nil

      w ->
        {enemy, mine, theirs} =
          if w.a_id == gid,
            do: {w.b_id, w.a_points, w.b_points},
            else: {w.a_id, w.b_points, w.a_points}

        e = Guilds.info_brief(enemy)

        %{
          id: w.id,
          enemy: e,
          mine: mine,
          theirs: theirs,
          ends_at: unix(w.ends_at)
        }
    end
  end

  @doc "Lời tuyên chiến đang chờ bang `gid` trả lời (nil nếu không có)."
  def pending(gid), do: GenServer.call(__MODULE__, {:pending, gid})

  @doc "Các trận đã xong gần nhất của bang `gid`."
  def history(gid, n \\ 10) do
    from(w in "guild_wars",
      where: not is_nil(w.result) and (w.a_id == ^gid or w.b_id == ^gid),
      order_by: [desc: w.id],
      limit: ^n,
      select: map(w, [:id, :a_id, :b_id, :a_points, :b_points, :result, :ends_at])
    )
    |> Repo.all()
    |> Enum.map(fn w ->
      enemy = if w.a_id == gid, do: w.b_id, else: w.a_id
      side = if w.a_id == gid, do: "a", else: "b"
      mine = if side == "a", do: w.a_points, else: w.b_points
      theirs = if side == "a", do: w.b_points, else: w.a_points

      out =
        cond do
          w.result == "draw" -> "draw"
          w.result == side -> "win"
          true -> "lose"
        end

      %{id: w.id, enemy: Guilds.info_brief(enemy), mine: mine, theirs: theirs, result: out}
    end)
  end

  # ---------- Tuyên chiến ----------

  @doc "Bang của `actor` tuyên chiến bang `target_gid`."
  def declare(actor, target_gid), do: GenServer.call(__MODULE__, {:declare, actor, target_gid})

  @doc "Bang chủ / phó bang của bang bị tuyên chiến nhận (`true`) hoặc từ chối."
  def answer(actor, accept?), do: GenServer.call(__MODULE__, {:answer, actor, accept?})

  @doc "Bang chủ / phó bang đầu hàng trận đang chiến."
  def surrender(actor) do
    with {:ok, m} <- staff(actor),
         %{} = w <- active(m.id) || {:error, "Bang không có trận chiến nào."} do
      winner = if w.a_id == m.id, do: "b", else: "a"
      finish(w.id, winner, actor)
      {:ok, "Đã đầu hàng."}
    end
  end

  @doc false
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def handle_call({:pending, gid}, _from, s), do: {:reply, s.pending[gid], s}
  def handle_call(:reset, _from, _s), do: {:reply, :ok, %{pending: %{}}}

  def handle_call({:declare, actor, target}, _from, s) do
    reply =
      with {:ok, m} <- staff(actor),
           %{} = t <-
             (is_integer(target) && Guilds.info_brief(target)) || {:error, "Không có bang này."},
           :ok <- can_fight(m.id, target),
           true <-
             not Map.has_key?(s.pending, target) ||
               {:error, "Bang này đang có lời tuyên chiến khác."},
           [_ | _] = staff_online <-
             online_staff(target) ||
               {:error, "Bang #{t.name} không có bang chủ / phó bang online."} do
        ref = make_ref()
        Process.send_after(self(), {:expire, target, ref}, @rules.answer_s * 1000)
        p = %{ref: ref, from: m.id, from_name: m.name, from_tag: m.tag, by: actor}

        for uid <- staff_online do
          send_to(
            uid,
            {:notice,
             "⚔ Bang [#{m.tag}] #{m.name} tuyên chiến bang bạn! Mở Bang hội để nhận hoặc từ chối (#{@rules.answer_s} giây)."}
          )

          Session.refresh_guild(uid)
        end

        {:ok, p, t}
      else
        [] -> {:error, "Bang này không có bang chủ / phó bang online."}
        err -> err
      end

    case reply do
      {:ok, p, t} ->
        {:reply, {:ok, "Đã tuyên chiến bang #{t.name}. Chờ họ trả lời."},
         put_in(s.pending[target], p)}

      err ->
        {:reply, err, s}
    end
  end

  def handle_call({:answer, actor, accept?}, _from, s) do
    with {:ok, m} <- staff(actor),
         %{} = p <- s.pending[m.id] || {:error, "Không có lời tuyên chiến nào."} do
      s = %{s | pending: Map.delete(s.pending, m.id)}

      if accept? do
        case can_fight(p.from, m.id) do
          :ok ->
            start(p.from, m.id)
            {:reply, {:ok, "Bắt đầu chiến bang!"}, s}

          err ->
            {:reply, err, s}
        end
      else
        Guilds.system(p.from, "Bang [#{m.tag}] #{m.name} từ chối lời tuyên chiến.")
        send_to(p.by, {:notice, "Bang #{m.name} từ chối lời tuyên chiến."})
        {:reply, {:ok, "Đã từ chối."}, s}
      end
    else
      err -> {:reply, err, s}
    end
  end

  @impl true
  def handle_info({:expire, gid, ref}, s) do
    case s.pending[gid] do
      %{ref: ^ref} = p ->
        send_to(p.by, {:notice, "Lời tuyên chiến đã hết hạn, bang kia không trả lời."})
        {:noreply, %{s | pending: Map.delete(s.pending, gid)}}

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:end, id}, s) do
    finish(id, nil, nil)
    {:noreply, s}
  end

  def handle_info(:resume, s) do
    now = DateTime.utc_now()

    try do
      for w <-
            Repo.all(
              from w in "guild_wars", where: is_nil(w.result), select: map(w, [:id, :ends_at])
            ) do
        Process.send_after(
          self(),
          {:end, w.id},
          max((unix(w.ends_at) - DateTime.to_unix(now)) * 1000, 0)
        )
      end
    rescue
      # database chưa sẵn sàng (test sandbox): bỏ qua
      _ -> :ok
    end

    {:noreply, s}
  end

  defp can_fight(a, b) do
    since = DateTime.add(DateTime.utc_now(), -@rules.rematch_hours * 3600, :second)

    cond do
      a == b ->
        {:error, "Không tự tuyên chiến bang mình được."}

      active(a) ->
        {:error, "Bang bạn đang có một trận chiến."}

      active(b) ->
        {:error, "Bang kia đang có một trận chiến."}

      Repo.exists?(
        from w in "guild_wars",
          where:
            ((w.a_id == ^a and w.b_id == ^b) or (w.a_id == ^b and w.b_id == ^a)) and
                w.ends_at > ^since
      ) ->
        {:error, "Hai bang vừa chiến, #{@rules.rematch_hours} giờ sau mới chiến lại được."}

      true ->
        :ok
    end
  end

  defp start(a, b) do
    ends =
      DateTime.utc_now()
      |> DateTime.add(@rules.minutes * 60, :second)
      |> DateTime.truncate(:second)

    {1, [%{id: id}]} =
      Repo.insert_all(
        "guild_wars",
        [
          %{
            a_id: a,
            b_id: b,
            ends_at: ends,
            inserted_at: DateTime.truncate(DateTime.utc_now(), :second)
          }
        ],
        returning: [:id]
      )

    Process.send_after(self(), {:end, id}, @rules.minutes * 60 * 1000)
    ga = Guilds.info_brief(a)
    gb = Guilds.info_brief(b)

    Chat.system(
      "⚔ Chiến bang: [#{ga.tag}] #{ga.name} đấu [#{gb.tag}] #{gb.name} trong #{@rules.minutes} phút! Thắng thành viên bang địch ở đấu trường để ghi điểm."
    )

    refresh(a)
    refresh(b)
    id
  end

  # ---------- Điểm ----------

  @doc """
  Người thách đấu `winner` vừa thắng `loser` ở đấu trường. Nếu bang hai người đang chiến nhau thì
  +1 điểm cho bang người thắng (tối đa `same_target_max` lần một cặp). Trả `{:ok, điểm_mới}` hoặc nil.
  """
  def record(winner, loser) do
    with %{id: gw} <- Guilds.member_of(winner),
         %{id: gl} <- Guilds.member_of(loser),
         %{} = w <- active(gw),
         true <- (w.a_id == gl or w.b_id == gl) and gw != gl,
         key = "#{winner}:#{loser}",
         n = Map.get(w.pairs, key, 0),
         true <- n < @rules.same_target_max do
      side = if w.a_id == gw, do: :a_points, else: :b_points
      scores = Map.update(w.scores, to_string(winner), 1, &(&1 + 1))

      {1, _} =
        Repo.update_all(from(x in "guild_wars", where: x.id == ^w.id and is_nil(x.result)),
          inc: [{side, 1}],
          set: [scores: scores, pairs: Map.put(w.pairs, key, n + 1)]
        )

      refresh(w.a_id)
      refresh(w.b_id)
      {:ok, Map.get(w, side) + 1}
    else
      _ -> nil
    end
  end

  # ---------- Kết thúc ----------

  @doc false
  def finish(id, forced \\ nil, surrender_by \\ nil) do
    w =
      Repo.one(
        from w in "guild_wars",
          where: w.id == ^id and is_nil(w.result),
          select: map(w, [:id, :a_id, :b_id, :a_points, :b_points, :scores])
      )

    if w do
      result =
        forced ||
          cond do
            w.a_points > w.b_points -> "a"
            w.b_points > w.a_points -> "b"
            true -> "draw"
          end

      {n, _} =
        Repo.update_all(from(x in "guild_wars", where: x.id == ^id and is_nil(x.result)),
          set: [
            result: result,
            surrender_id: surrender_by,
            ends_at: DateTime.truncate(DateTime.utc_now(), :second)
          ]
        )

      if n == 1, do: reward(w, result, surrender_by)
    end

    :ok
  end

  defp reward(w, result, surrender_by) do
    ga = Guilds.info_brief(w.a_id)
    gb = Guilds.info_brief(w.b_id)
    score = "#{w.a_points} – #{w.b_points}"

    case result do
      "draw" ->
        Chat.system("⚔ Chiến bang [#{ga.tag}] đấu [#{gb.tag}] kết thúc hòa #{score}.")

      side ->
        {win, lose, wid} = if side == "a", do: {ga, gb, w.a_id}, else: {gb, ga, w.b_id}
        how = if surrender_by, do: " (bang [#{lose.tag}] đầu hàng)", else: ""

        Chat.system(
          "🏆 Bang [#{win.tag}] #{win.name} thắng chiến bang trước [#{lose.tag}] #{lose.name} #{score}#{how}!"
        )

        Guilds.add_fund(wid, @rules.win_fund)
        Guilds.system(wid, "Bang thắng chiến bang: quỹ +#{@rules.win_fund}.")
        members = MapSet.new(Guilds.member_ids(wid))

        for {uid, pts} <- w.scores, pts >= 1, (id = String.to_integer(uid)) in members do
          Mailbox.send(id, %{
            subject: "Thưởng chiến bang",
            body: "Bang #{win.name} thắng chiến bang trước #{lose.name}. Bạn ghi #{pts} điểm.",
            gold: @rules.win_gold,
            xp: 0,
            items: %{}
          })
        end
    end

    refresh(w.a_id)
    refresh(w.b_id)
  rescue
    e -> Logger.error("Thưởng chiến bang #{w.id} lỗi: " <> Exception.message(e))
  end

  # ---------- Tiện ích ----------

  defp staff(actor) do
    case Guilds.member_of(actor) do
      %{role: r} = m when r in ~w(leader officer) -> {:ok, m}
      _ -> {:error, "Chỉ bang chủ hoặc phó bang làm được."}
    end
  end

  defp online_staff(gid) do
    Guilds.staff_ids(gid)
    |> Enum.filter(&(Registry.lookup(HacLong.Game.Registry, &1) != []))
  end

  # thành viên hai bang cập nhật `guild.war` (màu tên, bảng bang)
  defp refresh(gid), do: Enum.each(Guilds.member_ids(gid), &Session.refresh_guild/1)

  # bảng không có schema: thời điểm đọc ra là NaiveDateTime (UTC)
  defp unix(%NaiveDateTime{} = t), do: t |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
  defp unix(%DateTime{} = t), do: DateTime.to_unix(t)

  defp send_to(uid, msg), do: Phoenix.PubSub.broadcast(HacLong.PubSub, Session.topic(uid), msg)
end

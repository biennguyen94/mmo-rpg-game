defmodule HacLong.Slay do
  @moduledoc """
  Đồ sát (PK không cần đồng ý, thay PK cược vàng; `DECISIONS.md` P18).

  - `attack/2` (gọi từ kênh của người tấn công): cả hai online, cùng bản đồ chung, không ở vùng
    an toàn (`RULES.slay.safe_maps`), cùng từ cấp `RULES.slay.min_level`, không ai đang đánh.
    Hai bên vào trận ngay (`Session.slay_begin/2`), đối thủ hiện như quái là bản sao chỉ số.
  - Máu hai bên giữ ở đây. Luân phiên lượt, người tấn công đi trước. Mỗi lượt `RULES.slay.turn_s`
    giây; quá giờ thì server đánh thường thay (`Session.slay_auto/1`).
  - Ra đòn: Session chạy Engine ở chế độ `live` (đối thủ không tự đánh trả), rồi báo `acted/4`;
    đối thủ nhận `{:slay_sync, ...}` (máu mới, dòng nhật ký, tới lượt mình).
  - Hết máu hoặc bỏ chạy là thua: chết như thường (mất vàng theo `death_gold_loss`, về Nhà), số
    vàng mất chuyển cho người thắng. `settle/4` giữ hai Session (như giao dịch) và ghi hai nhân vật
    + một dòng `pk_matches` trong **một transaction** (nhật ký vàng lý do `SLAY`).

  Tiến trình này không bao giờ gọi đồng bộ vào Session (Session gọi vào đây), nên không khóa chéo.
  """
  use GenServer
  require Logger

  alias HacLong.{Repo, World}
  alias HacLong.Game.{Characters, Daily, Data, Engine, Session}
  alias HacLong.World.Maps

  @r Data.rules().slay

  def rules, do: @r

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: {:ok, %{fights: %{}, by_uid: %{}, next: 1}}

  # ---------- Bắt đầu ----------

  @doc "`a` đồ sát `b`. Trả `{:ok, fight}` hoặc `{:error, lý_do}`."
  def attack(a, b) do
    with true <- (is_integer(b) and b != a) || {:error, "Không đánh được người này."},
         true <- Session.online?(b) || {:error, "Người này không online."},
         pa = Session.get(a),
         pb = Session.get(b),
         :ok <- check(pa, pb),
         {:ok, f} <- start(a, b, pa, pb),
         :ok <- begin(b, f, a, pa, nil),
         :ok <- begin(a, f, b, pb, b) do
      {:ok, f}
    end
  end

  @doc "Điều kiện đồ sát (hàm thuần): người tấn công `pa`, người bị đánh `pb`."
  def check(pa, pb) do
    cond do
      pa == nil -> {:error, "Chưa có nhân vật."}
      pb == nil -> {:error, "Người này chưa có nhân vật."}
      pa.level < @r.min_level -> {:error, "Cần đạt cấp #{@r.min_level} mới được đồ sát."}
      pb.level < @r.min_level -> {:error, "#{pb.name} dưới cấp #{@r.min_level}, chưa đánh được."}
      pa.battle != nil -> {:error, "Bạn đang trong trận đấu."}
      pb.battle != nil -> {:error, "#{pb.name} đang trong trận đấu."}
      pa.hp <= 0 -> {:error, "Bạn cần hồi máu trước."}
      pb.hp <= 0 -> {:error, "#{pb.name} đang gục ngã."}
      pa.pos.map != pb.pos.map -> {:error, "Hãy đến cùng bản đồ với #{pb.name}."}
      not safe_ok?(pa.pos) -> {:error, "Đây là vùng an toàn, không được đánh nhau."}
      true -> :ok
    end
  end

  defp safe_ok?(pos), do: pos.map not in @r.safe_maps and World.shared?(pos)

  # Session `uid` vào trận với bản sao của `foe`; lỗi thì hủy trận (và trận đã mở của bên kia).
  defp begin(uid, f, foe, foe_p, undo) do
    case Session.slay_begin(uid, %{fight: public(f, uid), foe: opponent(foe_p, foe)}) do
      :ok ->
        :ok

      err ->
        abort(f.id)
        if undo, do: Session.slay_cancel(undo, f.id)
        err
    end
  end

  @doc "Bản sao chỉ số của `p` làm đối thủ: máu thật (không quy đổi cánh như đấu trường)."
  def opponent(p, uid) do
    max_hp = Engine.derived(p).maxHp

    HacLong.Arena.opponent(p, uid)
    |> Map.merge(%{maxHp: max_hp, hp: min(p.hp, max_hp), special: nil})
  end

  # ---------- API cho Session ----------

  def start(a, b, pa, pb), do: GenServer.call(__MODULE__, {:start, a, b, pa, pb})
  def abort(id), do: GenServer.call(__MODULE__, {:abort, id})

  @doc "Trận đồ sát của `uid`: `%{id, foe, turn, hp, foe_hp, until}` hoặc nil."
  def peek(uid), do: GenServer.call(__MODULE__, {:peek, uid})

  @doc "`uid` vừa ra đòn xong ở lượt của mình: máu mình và máu đối thủ sau lượt."
  def acted(uid, hp, foe_hp, auto? \\ false),
    do: GenServer.call(__MODULE__, {:acted, uid, hp, foe_hp, auto?})

  @doc "`uid` bỏ chạy: thua như gục ngã."
  def flee(uid), do: GenServer.call(__MODULE__, {:flee, uid})

  @doc false
  def reset, do: GenServer.call(__MODULE__, :reset)

  # ---------- GenServer ----------

  @impl true
  def handle_call({:start, a, b, pa, pb}, _from, s) do
    cond do
      Map.has_key?(s.by_uid, a) ->
        {:reply, {:error, "Bạn đang trong một trận đồ sát."}, s}

      Map.has_key?(s.by_uid, b) ->
        {:reply, {:error, "#{pb.name} đang trong một trận đồ sát."}, s}

      true ->
        f = %{
          id: s.next,
          a: a,
          b: b,
          names: %{a => pa.name, b => pb.name},
          hp: %{a => pa.hp, b => pb.hp},
          map: pa.pos.map,
          turn: a,
          turns: 0,
          misses: 0,
          until: nil,
          timer: nil
        }

        f = arm(f)

        s = %{
          s
          | fights: Map.put(s.fights, f.id, f),
            by_uid: s.by_uid |> Map.put(a, f.id) |> Map.put(b, f.id),
            next: s.next + 1
        }

        {:reply, {:ok, f}, s}
    end
  end

  def handle_call({:abort, id}, _from, s), do: {:reply, :ok, drop(s, id)}

  def handle_call({:peek, uid}, _from, s) do
    {:reply, with(%{} = f <- fight(s, uid), do: public(f, uid)), s}
  end

  def handle_call({:acted, uid, hp, foe_hp, auto?}, _from, s) do
    case fight(s, uid) do
      %{turn: ^uid} = f ->
        foe = foe(f, uid)
        dmg = max(0, f.hp[foe] - max(foe_hp, 0))
        healed = max(0, hp - f.hp[uid])
        f = %{f | hp: %{uid => hp, foe => max(foe_hp, 0)}, turns: f.turns + 1, misses: 0}

        if f.hp[foe] <= 0 do
          {:reply, {:ok, %{mine: false, until: nil}}, finish(s, f, uid, foe, :ko)}
        else
          cancel(f)
          f = arm(%{f | turn: foe})

          Session.slay_sync(foe, %{
            id: f.id,
            hp: f.hp[foe],
            foe_hp: hp,
            until: f.until,
            text: sync_text(f.names[uid], dmg, healed, auto?)
          })

          {:reply, {:ok, %{mine: false, until: f.until}}, put(s, f)}
        end

      nil ->
        {:reply, {:error, "Trận đồ sát đã kết thúc."}, s}

      _ ->
        {:reply, {:error, "Chưa tới lượt bạn."}, s}
    end
  end

  def handle_call({:flee, uid}, _from, s) do
    case fight(s, uid) do
      nil -> {:reply, {:error, "Trận đồ sát đã kết thúc."}, s}
      f -> {:reply, :ok, finish(s, f, foe(f, uid), uid, :fled)}
    end
  end

  def handle_call(:reset, _from, s) do
    Enum.each(s.fights, fn {_, f} -> cancel(f) end)
    {:reply, :ok, elem(init(:ok), 1)}
  end

  @impl true
  def handle_info({:turn_over, id, uid}, s) do
    case s.fights[id] do
      %{turn: ^uid} = f ->
        if f.misses >= @r.max_timeouts do
          # đánh thay mãi không được (Session không chạy): người này thua
          {:noreply, finish(s, f, foe(f, uid), uid, :fled)}
        else
          Task.start(fn -> auto(uid) end)
          {:noreply, put(s, arm(%{f | misses: f.misses + 1}))}
        end

      _ ->
        {:noreply, s}
    end
  end

  defp auto(uid) do
    Session.slay_auto(uid)
  catch
    :exit, _ -> :ok
  end

  # ---------- Kết thúc ----------

  defp finish(s, f, winner, loser, why) do
    cancel(f)
    Task.start(fn -> settle(f, winner, loser, why) end)
    drop(s, f.id)
  end

  @doc """
  Chốt trận `f`: `loser` chết như thường (mất vàng, về Nhà), số vàng mất chuyển cho `winner`.
  Giữ cả hai Session rồi ghi hai nhân vật + `pk_matches` trong một transaction.
  """
  def settle(f, winner, loser, why) do
    with {:ok, rw, pw} <- Session.hold(winner) do
      case Session.hold(loser) do
        {:ok, rl, pl} ->
          try do
            {pw2, pl2, lost} = outcome(f, pw, pl, winner, why)
            day = Date.from_iso8601!(Daily.today())

            Repo.transaction(fn ->
              {1, [%{id: id}]} =
                Repo.insert_all(
                  "pk_matches",
                  [
                    %{
                      a_id: f.a,
                      b_id: f.b,
                      a_name: f.names[f.a],
                      b_name: f.names[f.b],
                      wager: lost,
                      winner_id: winner,
                      rounds: f.turns,
                      day: day,
                      inserted_at: DateTime.truncate(DateTime.utc_now(), :second)
                    }
                  ],
                  returning: [:id]
                )

              Characters.save!(winner, pw2, "SLAY", "pk:#{id}")
              Characters.save!(loser, pl2, "SLAY", "pk:#{id}")
            end)

            if pl2.pos.map != pl.pos.map, do: World.leave(pl, loser)
            Session.release(winner, rw, pw2)
            Session.release(loser, rl, pl2)
            notice(winner, "🗡 Bạn hạ #{f.names[loser]}, nhận #{lost} vàng.")

            notice(
              loser,
              if(why == :fled,
                do: "💀 Bạn bỏ chạy khỏi #{f.names[winner]}: tính như gục ngã, mất #{lost} vàng.",
                else: "💀 Bạn bị #{f.names[winner]} hạ, mất #{lost} vàng."
              )
            )
          rescue
            e ->
              Logger.error("Đồ sát #{f.a}-#{f.b} lỗi: " <> Exception.message(e))
              Session.release(winner, rw, nil)
              Session.release(loser, rl, nil)
          end

        _ ->
          Session.release(winner, rw, nil)
      end
    end
  end

  @doc false
  def outcome(f, pw, pl, winner, why) do
    pl2 =
      if in_fight?(pl, f) do
        pl = %{pl | hp: 0}

        pl =
          if why == :fled,
            do: log(pl, "🏃 Bạn bỏ chạy: tính như gục ngã.", "bad"),
            else: log(pl, "#{f.names[winner]} hạ gục bạn.", "bad")

        {_, pl} = Engine.finish_lose(pl)
        %{pl | pos: Maps.home_spawn()}
      else
        pl
      end

    lost = max(0, pl.gold - pl2.gold)

    pw2 =
      if in_fight?(pw, f) do
        {_, pw} = Engine.finish_win(%{pw | hp: max(1, f.hp[winner])})
        pw = %{pw | gold: pw.gold + lost}
        pw = put_in(pw.battle.reward, %{pw.battle.reward | gold: lost})

        text =
          if why == :fled,
            do: "#{f.names[foe(f, winner)]} bỏ chạy. Bạn nhận #{lost} vàng.",
            else: "Bạn nhận #{lost} vàng của #{f.names[foe(f, winner)]}."

        log(pw, text, "win")
      else
        %{pw | gold: pw.gold + lost}
      end

    {pw2, pl2, lost}
  end

  defp in_fight?(p, f),
    do: match?(%{battle: %{over: false, encounter: %{slay: id}}} when id == f.id, p)

  defp log(p, text, kind),
    do: put_in(p.battle.log, Enum.take(p.battle.log ++ [%{text: text, kind: kind}], -60))

  # ---------- Tiện ích ----------

  defp sync_text(name, dmg, healed, auto?) do
    who = if auto?, do: "#{name} (hết giờ, tự đánh)", else: name

    cond do
      dmg > 0 -> "⚔ #{who} gây #{dmg} sát thương cho bạn."
      healed > 0 -> "#{who} hồi #{healed} máu."
      true -> "#{who} ra đòn nhưng không trúng."
    end
  end

  defp public(f, uid) do
    foe = foe(f, uid)

    %{
      id: f.id,
      foe: foe,
      mine: f.turn == uid,
      hp: f.hp[uid],
      foe_hp: f.hp[foe],
      until: f.until,
      map: f.map
    }
  end

  defp arm(f) do
    ms = @r.turn_s * 1000
    timer = Process.send_after(self(), {:turn_over, f.id, f.turn}, ms)
    %{f | timer: timer, until: System.system_time(:millisecond) + ms}
  end

  defp cancel(%{timer: nil}), do: :ok
  defp cancel(%{timer: t}), do: Process.cancel_timer(t)

  defp foe(%{a: a, b: b}, uid), do: if(uid == a, do: b, else: a)

  defp fight(s, uid), do: s.fights[s.by_uid[uid]]

  defp put(s, f), do: %{s | fights: Map.put(s.fights, f.id, f)}

  defp drop(s, id) do
    case s.fights[id] do
      nil ->
        s

      f ->
        cancel(f)
        %{s | fights: Map.delete(s.fights, id), by_uid: Map.drop(s.by_uid, [f.a, f.b])}
    end
  end

  defp notice(uid, text),
    do: Phoenix.PubSub.broadcast(HacLong.PubSub, Session.topic(uid), {:notice, text})
end

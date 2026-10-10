defmodule HacLong.DevilSquareBoard do
  @moduledoc """
  Bảng xếp hạng ngày của Quảng Trường Quỷ (Phase 18 M1, `RULES.devil_square.top`).

  - `record/4`: Session ghi điểm mỗi lượt vừa xong (giữ điểm cao nhất của mỗi người trong ngày, giờ Việt Nam).
  - `top/2`: bảng của một ngày (mặc định hôm nay), điểm cao trước.
  - Lúc 0h05 mỗi ngày: gửi thư thưởng `top` cho 3 người cao nhất **hôm trước** (`HacLong.Mailbox`), rồi bỏ bảng cũ.

  Giữ trong bộ nhớ (không thêm bảng DB): khởi động lại server giữa ngày thì mất bảng hôm đó (điểm cao nhất của
  từng người vẫn còn ở `daily.ds_best`). `config :hac_long, :devil_square_board, auto: false` (test) thì không hẹn giờ.
  """
  use GenServer

  alias HacLong.Game.{Daily, Data}
  alias HacLong.Mailbox

  @top Data.rules().devil_square.top

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def record(date, user_id, name, score),
    do: GenServer.cast(__MODULE__, {:record, date, user_id, name, score})

  @doc "`[%{user_id, name, score}]` của ngày `date`, cao trước."
  def top(date \\ Daily.today(), n \\ 10), do: GenServer.call(__MODULE__, {:top, date, n})

  @doc "Gửi thưởng ngày `date` ngay (quản trị / test). Trả về danh sách người được thưởng."
  def payout(date), do: GenServer.call(__MODULE__, {:payout, date})

  @impl true
  def init(:ok) do
    if Application.get_env(:hac_long, :devil_square_board, [])[:auto] != false, do: schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:record, date, uid, name, score}, s) do
    day = Map.get(s, date, %{})

    day =
      case day[uid] do
        %{score: old} when old >= score -> day
        _ -> Map.put(day, uid, %{user_id: uid, name: name, score: score})
      end

    {:noreply, Map.put(s, date, day)}
  end

  @impl true
  def handle_call({:top, date, n}, _from, s), do: {:reply, ranked(s, date, n), s}

  def handle_call({:payout, date}, _from, s) do
    {:reply, pay(s, date), Map.delete(s, date)}
  end

  @impl true
  def handle_info(:midnight, s) do
    # vừa qua 0h (giờ Việt Nam): thưởng ngày hôm trước
    yesterday = Daily.today(DateTime.add(DateTime.utc_now(), -3600, :second))
    pay(s, yesterday)
    schedule()
    {:noreply, Map.take(s, [Daily.today()])}
  end

  defp ranked(s, date, n) do
    s |> Map.get(date, %{}) |> Map.values() |> Enum.sort_by(&(-&1.score)) |> Enum.take(n)
  end

  defp pay(s, date) do
    winners = s |> ranked(date, length(@top)) |> Enum.filter(&(&1.score > 0))

    for {w, {prize, i}} <- Enum.zip(winners, Enum.with_index(@top, 1)) do
      Mailbox.send(w.user_id, %{
        subject: "Quảng Trường Quỷ: hạng #{i} ngày #{date}",
        body: "Bạn đứng hạng #{i} Quảng Trường Quỷ ngày #{date} với #{w.score} điểm.",
        gold: prize.gold,
        items: prize.items
      })

      Map.put(w, :rank, i)
    end
  end

  defp schedule do
    # 0h05 giờ Việt Nam tiếp theo
    ms = (Daily.seconds_left() + 300) * 1000
    Process.send_after(self(), :midnight, ms)
  end
end

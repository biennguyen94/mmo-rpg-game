defmodule HacLong.Bots.Bot do
  @moduledoc """
  Một người chơi AI (Phase 16). Gắn vào `Session` của tài khoản bot như một tab đang mở (nên có mặt trên
  bản đồ, ai cũng thấy trong danh sách Quanh đây, xem được hồ sơ, thách đấu được), rồi cứ mỗi nhịp hỏi
  `HacLong.Bots.Brain` lệnh tiếp theo và gửi qua `Session.command/2` như client.

  Thỉnh thoảng nói một câu trong kênh thế giới; lời mời cược đấu thì từ chối sau vài giây.
  """
  use GenServer, restart: :transient
  require Logger

  alias HacLong.{Chat, PkBet}
  alias HacLong.Bots.Brain
  alias HacLong.Game.Session
  alias HacLong.World.{Maps, MapServer}

  @lines [
    "Có ai đi tổ đội không?",
    "Quái ở đây rơi đồ ổn đấy.",
    "Sắp lên cấp rồi!",
    "Bình máu giờ đắt quá…",
    "Ai biết chỗ luyện cấp nhanh không?",
    "Hôm nay may mắn ghê.",
    "Đợi Golden Invasion thôi.",
    "Chào mọi người!",
    "Vừa hạ được một con khó nhằn.",
    "Bản đồ phụ vui phết."
  ]
  # trung bình khoảng 4 phút một câu (mỗi nhịp ~0,6 giây)
  @chat_chance 1 / 400

  def start_link({uid, _name, _cls} = arg),
    do:
      GenServer.start_link(__MODULE__, arg, name: {:via, Registry, {HacLong.Bots.Registry, uid}})

  @impl true
  def init({uid, name, cls}) do
    Process.send_after(self(), :start, 1000 + :rand.uniform(4000))
    {:ok, %{uid: uid, name: name, cls: cls, tries: 0}}
  end

  @impl true
  def handle_info(:start, s) do
    Session.attach(s.uid, self())
    Phoenix.PubSub.subscribe(HacLong.PubSub, Session.topic(s.uid))
    send(self(), :tick)
    {:noreply, s}
  catch
    # Session chưa mở được (vd. nạp nhân vật lỗi): thử lại sau, không làm sập cả nhóm bot
    kind, reason ->
      Logger.warning("bot #{s.uid} chưa vào được: #{inspect(kind)} #{inspect(reason)}")
      Process.send_after(self(), :start, 30_000)
      {:noreply, s}
  end

  def handle_info(:tick, s) do
    s = tick(s)
    {:noreply, s}
  catch
    kind, reason ->
      Logger.warning("bot #{s.uid}: #{inspect(kind)} #{inspect(reason)}")
      Process.send_after(self(), :tick, 3000)
      {:noreply, s}
  end

  # lời mời cược đấu: từ chối sau vài giây
  def handle_info({:pk_invite, %{} = _inv}, s) do
    Process.send_after(self(), :decline_pk, 2000 + :rand.uniform(3000))
    {:noreply, s}
  end

  def handle_info(:decline_pk, s) do
    PkBet.decline(s.uid)
    {:noreply, s}
  end

  # các tin khác phát cho người chơi (thông báo, cập nhật nhân vật…): bỏ qua
  def handle_info(_msg, s), do: {:noreply, s}

  defp tick(s) do
    p = Session.get(s.uid)
    snap = p && snapshot(p)
    name = if s.tries > 0, do: "#{s.name} #{s.tries}", else: s.name
    cmd = Brain.decide(p, snap, %{name: name, cls: s.cls, seed: s.uid})

    s =
      case cmd && Session.command(s.uid, cmd) do
        {%{ok: false}, nil} -> %{s | tries: s.tries + 1}
        _ -> s
      end

    if p && !p.battle && :rand.uniform() < @chat_chance, do: say(s, p)
    Process.send_after(self(), :tick, delay(p, cmd))
    s
  end

  defp snapshot(%{pos: %{map: id}}) do
    m = Maps.get(id)
    if m && not m.private and id != "tower", do: MapServer.snapshot(id)
  end

  defp snapshot(_), do: nil

  # trong trận (kể cả đang chờ lượt đồ sát) thì hỏi lại nhanh
  defp delay(%{battle: %{}}, _), do: 700 + :rand.uniform(700)
  defp delay(_p, nil), do: 2000 + :rand.uniform(2000)
  defp delay(_p, %{"act" => "move"}), do: 280 + :rand.uniform(220)
  defp delay(_p, _), do: 600 + :rand.uniform(600)

  defp say(s, p) do
    Chat.post(%{uid: s.uid, name: p.name, map: p.pos.map}, Enum.random(@lines))
  end
end

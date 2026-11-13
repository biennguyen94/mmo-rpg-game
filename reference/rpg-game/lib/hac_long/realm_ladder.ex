defmodule HacLong.RealmLadder do
  @moduledoc """
  Thang vùng co giãn theo server (DECISIONS "Thang vùng co giãn theo server"; số ở `RULES.realms.ladder`).

  Mỗi vùng chuyển sinh r (1..10) có mức hiệu lực `k_hl(r)` tính từ phân bố số lần chuyển sinh của người chơi đang hoạt
  động (`compute/3`, hàm thuần): server mới thì bằng thang gốc (k_hl = r); server lâu năm, người chơi đa số quá chuyển
  sinh 10, thì cả thang dời lên theo phân vị, mọi vùng đều có nhóm người phù hợp.

  - Quái vùng chuyển sinh: `adjust/3` (gọi lúc vào trận ở `HacLong.World`) dời mức bản đồ `ke` (đã có trong dữ liệu quái,
    `rich`) thêm `k_hl − r`, tính lại máu / thủ / công / kinh nghiệm / rơi đồ / ngọc theo đường cong hai đoạn (`curve/3`:
    tới mức 10 như cũ, sau mức 10 dốc riêng `*_after`). Người đánh chuyển sinh thấp hơn mức bản đồ: công quái chỉ tính tới
    CS người đánh + `underdog_margin`.
  - Tính lại mỗi ngày lúc `recompute_at` (giờ Việt Nam) hoặc khi quản trị bấm (`recompute/0`); quản trị đóng băng
    (`freeze/1`) hoặc đặt tay (`set/1`). Thang đang dùng lưu ở dòng `admin_log` op `realm_ladder` mới nhất (khởi động lại
    vẫn giữ), đọc nhanh qua `:persistent_term` (`k/1`, `ks/0`).
  - `config :hac_long, :realm_ladder, auto: false` (test): không tự hẹn giờ, không đọc / ghi database lúc khởi động.
  """
  use GenServer
  require Logger
  import Ecto.Query

  alias HacLong.{Chat, Repo}
  alias HacLong.Game.Data

  @key {__MODULE__, :ks}
  @topic "realm_ladder"

  def topic, do: @topic
  @tz_offset_s 7 * 3600

  def rules, do: Data.rules().realms
  def ladder_rules, do: rules().ladder
  def max_realm, do: length(ladder_rules().percentiles)
  def base, do: Enum.to_list(1..max_realm())

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Mức hiệu lực các vùng 1..10 (danh sách)."
  def ks, do: :persistent_term.get(@key, base())

  @doc "Mức hiệu lực vùng `r` (r ngoài thang: chính r)."
  def k(r) when is_integer(r) and r >= 1, do: Enum.at(ks(), r - 1) || r
  def k(r), do: r

  @doc "Trạng thái cho quản trị / client: `%{ks, base, targets, sample, at, frozen, overrides}`."
  def status,
    do:
      call(:status, %{
        ks: ks(),
        base: base(),
        targets: [],
        sample: 0,
        at: nil,
        frozen: false,
        overrides: %{}
      })

  @doc "Tính lại ngay từ người chơi đang hoạt động (quản trị). Trả trạng thái."
  def recompute, do: GenServer.call(__MODULE__, :recompute, 30_000)

  @doc "Đóng băng (true: giữ nguyên thang, lịch hằng ngày bỏ qua) / mở băng."
  def freeze(on?), do: GenServer.call(__MODULE__, {:freeze, on?})

  @doc "Đặt tay: `%{vùng => mức}` (nil / \"\" bỏ đặt tay vùng đó); vùng có đặt tay không theo phân vị."
  def set(overrides), do: GenServer.call(__MODULE__, {:set, overrides})

  @doc false
  # test: đặt thẳng thang (không database)
  def put(ks) when is_list(ks), do: GenServer.call(__MODULE__, {:put, ks})

  defp call(msg, default) do
    case GenServer.whereis(__MODULE__) do
      nil -> default
      pid -> GenServer.call(pid, msg)
    end
  catch
    :exit, _ -> default
  end

  # ---------- hàm thuần ----------

  @doc """
  Thang mới (hàm thuần). `sample`: số lần chuyển sinh mỗi người trong mẫu; `prev`: thang đang dùng; `overrides`:
  `%{vùng => mức}` đặt tay. Mẫu ít hơn `min_sample` người: giữ `prev` (lần đầu: thang gốc). Trả `{ks, targets}`.
  """
  def compute(sample, prev, overrides \\ %{}, r \\ ladder_rules()) do
    {auto, targets} = auto(sample, prev, r)
    {apply_overrides(auto, overrides), targets}
  end

  @doc "Thang tự động (không đặt tay) từ mẫu và thang tự động lần trước (hàm thuần)."
  def auto(sample, prev, r \\ ladder_rules()) do
    n = max_realm_of(r)

    if length(sample) < r.min_sample do
      {prev, []}
    else
      sorted = Enum.sort(sample)
      targets = Enum.map(r.percentiles, &percentile(sorted, &1))

      ks =
        1..n
        |> Enum.reduce({[], 0}, fn i, {acc, before} ->
          old = Enum.at(prev, i - 1) || i

          want = Enum.max([i, Enum.at(targets, i - 1), before + 1])

          k =
            want
            |> min(old + r.max_step)
            |> max(old - r.max_step)
            |> max(i)
            |> max(before + 1)

          {[k | acc], k}
        end)
        |> elem(0)
        |> Enum.reverse()

      {ks, targets}
    end
  end

  @doc "Đặt tay đè lên thang tự động (vùng đặt tay: số quản trị, không dưới mức gốc)."
  def apply_overrides(auto, overrides) do
    auto
    |> Enum.with_index(1)
    |> Enum.map(fn {k, i} ->
      case Map.get(overrides, i) do
        v when is_integer(v) -> max(i, v)
        _ -> k
      end
    end)
  end

  defp max_realm_of(r), do: length(r.percentiles)

  @doc "Phân vị `p` (0..1) của danh sách đã sắp xếp (lấy giá trị ở vị trí làm tròn lên, như bảng xếp hạng)."
  def percentile([], _p), do: 0

  def percentile(sorted, p) do
    i = (Float.ceil(p * length(sorted)) |> trunc()) - 1
    Enum.at(sorted, i |> max(0) |> min(length(sorted) - 1))
  end

  @doc """
  Hệ số theo mức `ke` (hàm thuần), đường cong hai đoạn: tới mức 10 `1 + per × ke` như vùng cũ, sau 10 dốc riêng `after`.
  `kind`: :hp (máu, thủ), :atk, :xp.
  """
  def curve(ke, kind, r \\ rules()) do
    {per, aft} =
      case kind do
        :hp -> {r.mult_per_realm, r.ladder.hp_after}
        :atk -> {r.atk_mult_per_realm, r.ladder.atk_after}
        :xp -> {r.xp_mult_per_realm, r.ladder.xp_after}
      end

    cap = r.ladder |> Map.get(:curve_knee, 10)
    1 + per * min(ke, cap) + aft * max(0, ke - cap)
  end

  @doc """
  Quái vùng chuyển sinh `spec` (dữ liệu `realms.json`) ở vùng `realm` đánh với người `cs` lần chuyển sinh (hàm thuần trên
  `ks`): dời mức thêm `k_hl − realm`, tính lại hệ số; người đánh thấp hơn mức bản đồ thì công tính tới `cs + margin`.
  Thang gốc và người không tụt hậu: trả đúng `spec` cũ.
  """
  def adjust(spec, realm, cs, ks \\ ks(), r \\ rules())

  def adjust(%{rich: ke0} = spec, realm, cs, ks, r) when is_integer(realm) and is_number(ke0) do
    delta = (Enum.at(ks, realm - 1) || realm) - realm
    ke = ke0 + delta
    lord = spec[:lord] == true
    lk = if lord, do: realm + delta, else: ke
    bm = if lord, do: r.boss_mult, else: 1

    # công chúa tể nhân riêng (`lord_atk_mult`, DECISIONS "Quái vùng chuyển sinh: bớt máu, đánh đau hơn")
    ba = if lord, do: r.lord_atk_mult, else: 1
    margin = r.ladder.underdog_margin
    atk_k = if is_integer(cs) and cs + margin < lk, do: max(cs + margin, realm * 1.0), else: lk

    if delta == 0 and atk_k == lk do
      spec
    else
      Map.merge(spec, %{
        level: spec.level + 10 * delta,
        mult: Float.round(curve(lk, :hp, r) * bm, 3),
        atk_mult: Float.round(curve(atk_k, :atk, r) * ba, 3),
        xp_mult: Float.round(curve(lk, :xp, r) * bm, 3),
        rich: if(lord, do: spec.rich + delta, else: ke),
        jewel_chance:
          min(
            r.ladder.jewel_max,
            (r.jewel_base + r.jewel_per_realm * lk) * if(lord, do: 5, else: 1)
          )
          |> Float.round(4),
        ladder: realm + delta
      })
    end
  end

  def adjust(spec, _realm, _cs, _ks, _r), do: spec

  # ---------- GenServer ----------

  defp auto?, do: Application.get_env(:hac_long, :realm_ladder, [])[:auto] != false

  @impl true
  def init(:ok) do
    # auto: thang tự động (không đặt tay); ks = auto + đặt tay
    s = %{
      ks: base(),
      auto: base(),
      targets: [],
      sample: 0,
      at: nil,
      frozen: false,
      overrides: %{},
      timer: nil
    }

    s = if auto?(), do: load(s), else: s
    :persistent_term.put(@key, s.ks)
    {:ok, schedule(s)}
  end

  @impl true
  def handle_call(:status, _from, s), do: {:reply, public(s), s}

  def handle_call(:recompute, _from, s) do
    s = do_recompute(s, true)
    {:reply, public(s), s}
  end

  def handle_call({:freeze, on?}, _from, s) do
    s = save(%{s | frozen: on? == true})
    {:reply, public(s), s}
  end

  def handle_call({:set, ov}, _from, s) do
    ov =
      for {k, v} <- ov || %{},
          i = to_int(k),
          is_integer(i) and i in 1..max_realm(),
          into: s.overrides,
          do: {i, to_int(v)}

    ov = ov |> Enum.reject(fn {_, v} -> v == nil end) |> Map.new()
    s = %{s | overrides: ov}
    s = do_recompute(s, true)
    {:reply, public(s), s}
  end

  def handle_call({:put, ks}, _from, s) do
    :persistent_term.put(@key, ks)
    broadcast(ks)
    {:reply, :ok, %{s | ks: ks, auto: ks, overrides: %{}}}
  end

  @impl true
  def handle_info(:daily, s) do
    s = if s.frozen, do: s, else: do_recompute(s, false)
    {:noreply, schedule(%{s | timer: nil})}
  end

  # ---------- nội bộ ----------

  defp do_recompute(s, force?) do
    sample = sample()
    {auto, targets} = auto(sample, s.auto)
    auto = if s.frozen and not force?, do: s.auto, else: auto
    ks = apply_overrides(auto, s.overrides)
    changed = ks != s.ks

    s =
      save(%{
        s
        | ks: ks,
          auto: auto,
          targets: targets,
          sample: length(sample),
          at: DateTime.utc_now()
      })

    :persistent_term.put(@key, ks)
    broadcast(ks)

    if changed,
      do:
        Chat.system(
          "🗺 Thang vùng chuyển sinh cập nhật theo người chơi: " <>
            Enum.map_join(Enum.with_index(ks, 1), ", ", fn {k, i} -> "vùng #{i} ≈ CS #{k}" end) <>
            "."
        )

    s
  rescue
    e ->
      Logger.error("Thang vùng: tính lại lỗi: " <> Exception.message(e))
      s
  end

  # mỗi tài khoản một nhân vật (nhiều chuyển sinh nhất), chơi trong `sample_days` ngày, cấp ≥ min_level, không bot / quản trị
  defp sample do
    r = ladder_rules()
    since = DateTime.add(DateTime.utc_now(), -r.sample_days * 86_400, :second)

    from(c in HacLong.Game.Character,
      join: u in HacLong.Accounts.User,
      on: u.id == c.user_id,
      where:
        u.role not in ["bot", "admin", "mod"] and c.level >= ^r.min_level and
          c.updated_at >= ^since,
      group_by: fragment("coalesce(?, ?)", u.account_id, u.id),
      select: max(c.rebirths)
    )
    |> Repo.all()
    |> Enum.map(&(&1 || 0))
  end

  defp save(s) do
    if auto?() do
      HacLong.Admin.log!(
        "system",
        "realm_ladder",
        nil,
        %{
          "ks" => s.ks,
          "auto" => s.auto,
          "targets" => s.targets,
          "sample" => s.sample,
          "frozen" => s.frozen,
          "overrides" => Map.new(s.overrides, fn {k, v} -> {to_string(k), v} end)
        },
        "ok"
      )
    end

    s
  rescue
    _ -> s
  end

  defp load(s) do
    case HacLong.Admin.recent_op("realm_ladder", 1) do
      [%{params: p, at: at}] ->
        ks = p["ks"]

        if is_list(ks) and length(ks) == max_realm() and Enum.all?(ks, &is_integer/1),
          do: %{
            s
            | ks: ks,
              auto:
                if(is_list(p["auto"]) and length(p["auto"]) == max_realm(),
                  do: p["auto"],
                  else: ks
                ),
              targets: p["targets"] || [],
              sample: p["sample"] || 0,
              frozen: p["frozen"] == true,
              overrides: Map.new(p["overrides"] || %{}, fn {k, v} -> {to_int(k), v} end),
              at: at
          },
          else: s

      _ ->
        s
    end
  rescue
    _ -> s
  end

  defp schedule(s) do
    if auto?() do
      [h, m] = ladder_rules().recompute_at |> String.split(":") |> Enum.map(&String.to_integer/1)
      day = 86_400_000
      local = rem(System.system_time(:millisecond) + @tz_offset_s * 1000, day)
      delay = rem((h * 3600 + m * 60) * 1000 - local + day, day)

      %{
        s
        | timer:
            Process.send_after(self(), :daily, if(delay < 1000, do: delay + day, else: delay))
      }
    else
      s
    end
  end

  defp broadcast(ks),
    do: Phoenix.PubSub.broadcast(HacLong.PubSub, @topic, {:realm_ladder, %{ks: ks}})

  defp public(s),
    do: %{
      ks: s.ks,
      base: base(),
      targets: s.targets,
      sample: s.sample,
      at: s.at,
      frozen: s.frozen,
      overrides: Map.new(s.overrides, fn {k, v} -> {to_string(k), v} end)
    }

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v) and v != "", do: String.to_integer(v)
  defp to_int(_), do: nil
end

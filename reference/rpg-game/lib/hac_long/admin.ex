defmodule HacLong.Admin do
  @moduledoc """
  Lệnh quản trị trên nhân vật (FEATURE_CATALOG K1) và nhật ký quản trị `admin_log` (K2).

  Mọi lệnh sửa nhân vật chạy trong `HacLong.Game.Session` của người đó (`Session.admin/3`), nên
  không đè lên lệnh người chơi đang gửi, và được lưu với lý do `ADMIN` vào nhật ký vàng / đồ
  hiếm (`ref` = mã dòng `admin_log`). Người chơi không online thì Session tự mở, ghi xong tự tắt.

  Lệnh (`op`, tham số):

  | op | tham số | việc |
  |---|---|---|
  | `give_xp` | `xp` (1..1e9) | cộng kinh nghiệm, lên cấp như đánh quái |
  | `set_level` | `level` (1..cấp tối đa) | đặt cấp, xp về 0; điểm tiềm năng ± 3 × số cấp đổi |
  | `add_gold` | `amount` (âm được, không dưới 0) | cộng/trừ vàng |
  | `give_item` | `id`, `count` (1..9999), `up` (0..11), `wopt` (cánh: `hp` / `mp` / `ignore_def`) | tặng đồ thường, cả đồ không bán/không rơi (`relic`, `dragonshield`); có `up` hoặc là cánh thì mỗi món là bản riêng trong túi đồ hiếm |
  | `give_gear` | `base`, `rarity` (1..3), `bonus` (`%{str, agi, vit, ene}`), `up`, `exc` (dòng Excellent), `luck`, `skill` (true; Kỹ năng chỉ vũ khí) | tặng đồ chỉ số ngẫu nhiên |
  | `add_points` | `n` (âm được) | cộng/trừ điểm tiềm năng |
  | `add_stats` | `str`, `agi`, `vit`, `ene` | cộng/trừ thẳng vào chỉ số (không dưới 1) |
  | `heal` | | hồi đầy máu |
  """

  import Ecto.Query
  alias HacLong.Repo
  alias HacLong.Game.{Data, Engine, Gear, Session}

  @char_ops ~w(give_xp set_level add_gold give_item give_gear add_points add_stats heal)
  @max_xp 1_000_000_000
  @max_gold 1_000_000_000_000
  @max_count 9_999
  @max_stat 100_000

  def char_ops, do: @char_ops

  @doc """
  Chạy lệnh `op` lên nhân vật của tài khoản `target_id`, do `admin` (`%{id, username}`) ra lệnh.
  Ghi `admin_log` (cả khi lỗi). Trả về `{:ok, thông_báo}` hoặc `{:error, lý_do}`.
  """
  def run(admin, op, target_id, params) when op in @char_ops and is_integer(target_id) do
    case build(op, params) do
      {:ok, fun} ->
        id = log!(admin, op, target_id, params, nil)
        result = Session.admin(target_id, fun, "admin:#{id}")
        set_result(id, result)
        result

      {:error, msg} = err ->
        log!(admin, op, target_id, params, "lỗi: " <> msg)
        err
    end
  end

  def run(_admin, _op, _target, _params), do: {:error, "Lệnh quản trị không hợp lệ."}

  @doc """
  Chạy lệnh từ dòng lệnh server (`bin/hac_long rpc`), người ra lệnh ghi là `console`:

      bin/hac_long rpc 'HacLong.Admin.console("Tên nhân vật", "set_level", %{"level" => 50}) |> IO.inspect()'

  `name`: tên nhân vật hoặc tên đăng nhập.
  """
  def console(name, op, params \\ %{}) do
    case HacLong.Moderation.find_user(name) do
      nil -> {:error, "Không tìm thấy \"#{name}\"."}
      u -> run(%{id: 0, username: "console"}, op, u.id, params)
    end
  end

  # ---------- Từng lệnh (hàm thuần trên nhân vật) ----------

  @doc false
  def build("give_xp", %{"xp" => xp}) when is_integer(xp) and xp in 1..@max_xp do
    {:ok,
     fn p ->
       {levels, p} = Engine.gain_xp(p, xp)
       {:ok, p, "+#{xp} kinh nghiệm#{if levels > 0, do: ", lên cấp #{p.level}", else: ""}."}
     end}
  end

  def build("set_level", %{"level" => lv}) when is_integer(lv) do
    if lv in 1..Engine.max_level() do
      {:ok,
       fn p ->
         points = max(0, p.points + (lv - p.level) * Engine.points_per_level(p.cls))
         p = %{p | level: lv, xp: 0, points: points}
         {:ok, %{p | hp: Engine.derived(p).maxHp}, "Đã đặt cấp #{lv}."}
       end}
    else
      {:error, "Cấp phải từ 1 tới #{Engine.max_level()}."}
    end
  end

  def build("add_gold", %{"amount" => n}) when is_integer(n) and abs(n) <= @max_gold and n != 0 do
    {:ok,
     fn p ->
       gold = max(0, p.gold + n)
       {:ok, %{p | gold: gold}, "Vàng: #{p.gold} → #{gold}."}
     end}
  end

  def build("give_item", %{"id" => id} = a) do
    count = a["count"] || 1
    up = a["up"] || 0
    it = is_binary(id) && Data.item(id)
    # Phase 15e: dòng phụ cho sẵn của cánh (`hp` / `mp` / `ignore_def`)
    wopt = a["wopt"]

    cond do
      !it ->
        {:error, "Không có món đồ \"#{id}\"."}

      wopt != nil and not (it.slot == "wing" and Gear.wopt_value(it[:tier], wopt) > 0) ->
        {:error, "Dòng cánh không hợp lệ (cánh bậc có dòng: hp, mp, ignore_def)."}

      not (is_integer(count) and count in 1..@max_count) ->
        {:error, "Số lượng phải từ 1 tới #{@max_count}."}

      not (is_integer(up) and up in 0..Engine.max_upgrade()) ->
        {:error, "Cấp nâng phải từ 0 tới #{Engine.max_upgrade()}."}

      (up > 0 or it.slot == "wing") and it.slot not in Engine.equip_slots() ->
        {:error, "#{it.name} không nâng cấp được."}

      # đồ đã nâng cấp và cánh là từng món riêng (`Gear.plain/1`), nằm trong túi đồ hiếm
      up > 0 or it.slot == "wing" ->
        {:ok,
         fn p ->
           if length(Gear.bag(p)) + count > Gear.max_bag() do
             {:error, "Túi đồ hiếm không đủ chỗ cho #{count} món (tối đa #{Gear.max_bag()})."}
           else
             gs = for _ <- 1..count, do: Gear.plain(id)
             gs = if wopt, do: Enum.map(gs, &Map.put(&1, :wopt, wopt)), else: gs
             p = Map.put(p, :gear, (Map.get(p, :gear) || []) ++ gs)
             p = Enum.reduce(gs, p, &put_upgrade(&2, &1.uid, up))
             {:ok, p, "Đã tặng #{it.name}#{if up > 0, do: " +#{up}", else: ""} ×#{count}."}
           end
         end}

      true ->
        {:ok,
         fn p ->
           p = Engine.add_item(p, id, count)
           {:ok, p, "Đã tặng #{it.name} ×#{count}."}
         end}
    end
  end

  def build("give_gear", %{"base" => base} = a) do
    rarity = a["rarity"] || 3
    up = a["up"] || 0
    it = is_binary(base) && Data.item(base)
    bonus = a["bonus"]
    # Phase 15c: dòng Excellent cho sẵn (`exc`: danh sách id dòng hợp loại đồ)
    exc = a["exc"] || []
    # Phase 15d: May mắn (mọi món) / Kỹ năng (chỉ vũ khí)
    luck = a["luck"] == true
    skill = a["skill"] == true

    cond do
      !it or it.slot not in Engine.gear_slots() ->
        {:error, "\"#{base}\" không phải vũ khí / giáp / khiên (cánh: dùng give_item)."}

      rarity not in 1..3 ->
        {:error, "Độ hiếm phải là 1, 2 hoặc 3."}

      not (is_integer(up) and up in 0..Engine.max_upgrade()) ->
        {:error, "Cấp nâng phải từ 0 tới #{Engine.max_upgrade()}."}

      bonus != nil and not valid_stats?(bonus, 0) ->
        {:error, "Chỉ số cộng thêm không hợp lệ (str, agi, vit, ene: 0..#{@max_stat})."}

      not (is_list(exc) and Enum.all?(exc, &(is_binary(&1) and Gear.exc_value(it.slot, &1) > 0))) ->
        {:error, "Dòng Excellent không hợp lệ cho loại đồ này."}

      skill and it.slot != "weapon" ->
        {:error, "Chỉ vũ khí mới có dòng Kỹ năng."}

      true ->
        {:ok,
         fn p ->
           if length(Gear.bag(p)) >= Gear.max_bag() do
             {:error, "Túi đồ hiếm đã đầy (#{Gear.max_bag()} món)."}
           else
             g = Gear.new(base, rarity, gear_bonus(bonus, rarity, p.level))
             g = if exc == [], do: g, else: Map.put(g, :exc, Enum.uniq(exc))
             g = if luck, do: Map.put(g, :luck, true), else: g
             g = if skill, do: Map.put(g, :skill, true), else: g
             {p, :kept} = Gear.add(p, g)
             p = if up > 0, do: put_upgrade(p, g.uid, up), else: p
             {:ok, p, "Đã tặng #{Gear.resolve(g).name}#{if up > 0, do: " +#{up}", else: ""}."}
           end
         end}
    end
  end

  def build("add_points", %{"n" => n}) when is_integer(n) and abs(n) <= @max_stat and n != 0 do
    {:ok,
     fn p ->
       points = max(0, p.points + n)
       {:ok, %{p | points: points}, "Điểm tiềm năng: #{p.points} → #{points}."}
     end}
  end

  def build("add_stats", a) when is_map(a) do
    deltas = Map.take(a, ~w(str agi vit ene))

    if deltas != %{} and Enum.all?(deltas, fn {_, v} -> is_integer(v) and abs(v) <= @max_stat end) do
      {:ok,
       fn p ->
         stats =
           Enum.reduce(deltas, p.stats, fn {k, v}, st ->
             Map.update!(st, String.to_existing_atom(k), &max(1, &1 + v))
           end)

         text = Enum.map_join(stats, ", ", fn {k, v} -> "#{k} #{v}" end)
         {:ok, %{p | stats: stats}, "Chỉ số: #{text}."}
       end}
    else
      {:error, "Cần ít nhất một trong str, agi, vit, ene (số nguyên)."}
    end
  end

  def build("heal", _a),
    do:
      {:ok,
       fn p ->
         {:ok, Map.merge(p, %{hp: Engine.derived(p).maxHp, mp: Engine.derived(p).maxMp}),
          "Đã hồi đầy máu và MP."}
       end}

  def build(_op, _a), do: {:error, "Tham số không hợp lệ."}

  defp put_upgrade(p, _id, 0), do: p

  defp put_upgrade(p, id, up),
    do: Map.put(p, :upgrades, Map.put(Map.get(p, :upgrades) || %{}, id, up))

  defp valid_stats?(m, min) when is_map(m) and map_size(m) > 0 do
    Enum.all?(m, fn {k, v} ->
      k in ~w(str agi vit ene) and is_integer(v) and v in min..@max_stat
    end)
  end

  defp valid_stats?(_, _), do: false

  # Không cho sẵn chỉ số: lấy `rarity` dòng đầu (str, agi, vit, ene) với mức cao nhất mà đồ rơi ở
  # cấp đó có thể có (như `Gear.roll/3`).
  defp gear_bonus(nil, rarity, level) do
    top = 1 + floor(level / 6)
    Gear.stats() |> Enum.take(rarity) |> Map.new(&{&1, top})
  end

  defp gear_bonus(bonus, _rarity, _level) do
    for {k, v} <- bonus, v > 0, into: %{}, do: {String.to_existing_atom(k), v}
  end

  # ---------- Nhật ký quản trị ----------

  @doc """
  Ghi một dòng `admin_log`. `admin`: `%{id, username}`; `result`: nil (chưa xong, cập nhật sau
  bằng `set_result/2`) hoặc chuỗi kết quả. Trả về mã dòng.
  """
  def log!(admin, op, target_id, params, result) do
    params = params |> Map.drop(["op"]) |> Map.new(fn {k, v} -> {to_string(k), v} end)

    {1, [%{id: id}]} =
      Repo.insert_all(
        "admin_log",
        [
          %{
            admin_id: admin.id,
            admin_name: admin.username,
            op: String.slice(to_string(op), 0, 32),
            target_id: target_id,
            params: params,
            result: result && String.slice(result, 0, 200)
          }
        ],
        returning: [:id]
      )

    id
  end

  @doc "Ghi kết quả (`{:ok, thông_báo}` / `{:error, lý_do}` / `:ok` / chuỗi) vào dòng `admin_log`."
  def set_result(id, result) do
    text =
      case result do
        {:ok, msg} when is_binary(msg) -> msg
        {:ok, data} -> "ok " <> inspect(data, limit: 5)
        :ok -> "ok"
        {:error, msg} when is_binary(msg) -> "lỗi: " <> msg
        other -> inspect(other, limit: 5)
      end

    Repo.update_all(from(l in "admin_log", where: l.id == ^id),
      set: [result: String.slice(text, 0, 200)]
    )

    :ok
  end

  @doc "Các dòng `admin_log` mới nhất (lọc theo người bị tác động nếu có `target_id`)."
  def recent(limit \\ 50, target_id \\ nil) do
    q =
      from l in "admin_log",
        order_by: [desc: l.id],
        limit: ^limit,
        select: %{
          id: l.id,
          admin: l.admin_name,
          op: l.op,
          target_id: l.target_id,
          params: l.params,
          result: l.result,
          at: l.inserted_at
        }

    q = if target_id, do: where(q, [l], l.target_id == ^target_id), else: q
    Repo.all(q)
  end
end

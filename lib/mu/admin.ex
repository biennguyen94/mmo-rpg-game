defmodule Mu.Admin do
  @moduledoc """
  Lệnh quản trị tặng EXP / đặt cấp (DEC-187). Gọi trên server đang chạy:

      bin/mu rpc 'IO.inspect(Mu.Admin.give_exp("TenNhanVat", 5000, "đền bù bảo trì"))'
      bin/mu rpc 'IO.inspect(Mu.Admin.set_level("TenNhanVat", 20, "ticket 12"))'
      bin/mu rpc 'IO.inspect(Mu.Admin.log("TenNhanVat"))'

  EXP đi qua `Session.admin_exp/3` → `Engine.add_exp/2`, đúng luật hạ quái: lên cấp liên tiếp,
  `+statPerLevel` điểm tự do mỗi cấp, hồi đầy HP / MP, không vượt `maxLevel` (ở cấp tối đa EXP
  về 0). Nhân vật đang online thấy ngay; offline thì ghi DB. `set_level` chỉ **nâng** cấp
  (không hạ — điểm đã cộng không gỡ được). Mỗi lần thành công ghi một dòng `admin_log`.
  """
  import Ecto.Query

  alias Mu.Repo
  alias Mu.Game.{Character, Data, Items, Session, Upgrade}

  @doc "Tặng `amount` EXP. `{:ok, %{level_before, level, experience, exp, online}}` hoặc `{:error, lý_do}`."
  def give_exp(name, amount, reason \\ ""), do: run("GIVE_EXP", name, amount, reason)

  @doc "Nâng nhân vật lên đúng cấp `level` (EXP trong cấp mới = 0)."
  def set_level(name, level, reason \\ ""), do: run("SET_LEVEL", name, {:level, level}, reason)

  @doc """
  Tặng đồ vào túi (DEC-188). `opts`: `quantity` (mặc định 1), `level` (+N), `option` (dòng Life),
  `reason`. +N / option không vượt mức ép được của món đó (`Upgrade.limits/1`; nhẫn, jewel,
  potion = 0; cánh không có option); có +N / option thì `quantity` phải là 1.
  `{:ok, %{zen}}` hoặc `{:error, :unknown_item | :bad_level | :bad_option | :bad_quantity | "INVENTORY_FULL"}`.
  """
  def give_item(name, tid, opts \\ []) do
    q = Keyword.get(opts, :quantity, 1)
    lv = Keyword.get(opts, :level, 0)
    op = Keyword.get(opts, :option, 0)
    t = Data.item(tid)
    {max_lv, max_op} = if t, do: Upgrade.limits(t), else: {0, 0}

    cond do
      t == nil ->
        {:error, :unknown_item}

      not (is_integer(lv) and lv in 0..max_lv) ->
        {:error, :bad_level}

      not (is_integer(op) and op in 0..max_op) ->
        {:error, :bad_option}

      not (is_integer(q) and q >= 1 and (q == 1 or lv + op == 0)) ->
        {:error, :bad_quantity}

      true ->
        attrs = %{item_level: lv, option_level: op}
        detail = %{item: tid, quantity: q, level: lv, option: op}

        with_char("GIVE_ITEM", name, Keyword.get(opts, :reason, ""), detail, fn c ->
          Session.admin_items(c.account_id, c.id, fn ->
            Items.admin_grant(c.id, tid, q, attrs, "admin")
          end)
        end)
    end
  end

  @doc "Cộng Zen (số âm = trừ), audit Zen `ADMIN`. `{:ok, %{zen: số_dư}}`."
  def add_zen(name, amount, reason \\ "")

  def add_zen(name, amount, reason) when is_integer(amount) and amount != 0 do
    with_char("ADD_ZEN", name, reason, %{zen: amount}, fn c ->
      Session.admin_items(c.account_id, c.id, fn -> Items.admin_zen(c.id, amount, reason) end)
    end)
  end

  def add_zen(_, _, _), do: {:error, :bad_amount}

  @doc """
  Cộng thẳng chỉ số (DEC-188), vd `%{energy: 500, vitality: 200, free_stat_points: 10}` — khóa:
  `strength agility vitality energy free_stat_points`, giá trị nguyên ≥ 0. Hồi đầy HP / MP theo
  chỉ số mới. `{:ok, %{strength, agility, vitality, energy, free_stat_points}}`.
  """
  def add_stats(name, stats, reason \\ "") do
    keys = [:strength, :agility, :vitality, :energy, :free_stat_points]

    if is_map(stats) and stats != %{} and
         Enum.all?(stats, fn {k, v} -> k in keys and is_integer(v) and v >= 0 end) do
      with_char("ADD_STATS", name, reason, stats, fn c ->
        with {:ok, ch} <-
               Session.admin_character(c.account_id, c.id, fn ch ->
                 {:ok, Enum.reduce(stats, ch, fn {k, v}, ch -> Map.update!(ch, k, &(&1 + v)) end)}
               end),
             do: {:ok, Map.take(ch, keys)}
      end)
    else
      {:error, :bad_stats}
    end
  end

  @doc "Các thao tác gần nhất (mới trước), lọc theo tên nhân vật nếu có."
  def log(name \\ nil, limit \\ 20) do
    q = from(l in "admin_log", order_by: [desc: l.id], limit: ^limit)

    q =
      if name,
        do: where(q, [l], fragment("lower(?)", l.character_name) == ^String.downcase(name)),
        else: q

    Repo.all(
      from l in q,
        select: %{
          at: l.at,
          action: l.action,
          name: l.character_name,
          detail: l.detail,
          reason: l.reason
        }
    )
  end

  defp run(action, name, amount, reason) do
    with_char(action, name, reason, nil, fn c -> Session.admin_exp(c.account_id, c.id, amount) end)
  end

  # Tìm nhân vật theo tên, chạy `fun`, thành công thì ghi `admin_log` (`detail` nil = kết quả).
  defp with_char(action, name, reason, detail, fun) when is_binary(name) and is_binary(reason) do
    case Repo.one(
           from c in Character,
             where: fragment("lower(?)", c.name) == ^String.downcase(name),
             select: %{id: c.id, account_id: c.account_id, name: c.name}
         ) do
      nil ->
        {:error, :no_character}

      c ->
        with {:ok, r} <- fun.(c) do
          {:ok, id} = Ecto.UUID.dump(c.id)

          Repo.insert_all("admin_log", [
            %{
              action: action,
              character_id: id,
              character_name: c.name,
              detail: detail || Map.delete(r, :online),
              reason: reason
            }
          ])

          {:ok, r}
        end
    end
  end

  defp with_char(_, _, _, _, _), do: {:error, :bad_args}
end

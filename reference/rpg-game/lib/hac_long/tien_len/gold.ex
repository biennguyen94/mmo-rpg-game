defmodule HacLong.TienLen.Gold do
  @moduledoc """
  Tiền của bàn Tiến Lên là **vàng Hắc Long** (Phase 17, thay `TienLen.Economy` của repo gốc;
  `DECISIONS.md` P17). Cùng giao diện `HacLong.TienLen.RoomServer` cần: `balances/1`,
  `settle/3`, `spend/5`.

  Vàng nằm trong nhân vật do `HacLong.Game.Session` giữ, nên mọi thay đổi đi qua Session:
  giữ (`Session.hold/1`, theo thứ tự id để hai lần trả cùng lúc không khóa chéo) → tính →
  ghi các nhân vật + khóa trả trong **một transaction** (nhật ký vàng lý do `TIENLEN` /
  `TIENLEN_THROW`) → nhả Session với nhân vật mới. Lỗi ở bất kỳ bước nào thì không ai mất gì.

  Thiếu vàng (T25, C9, E5): người nợ trả tối đa số đang có, chia theo tỉ lệ cho các chủ nợ.
  """
  require Logger
  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Game.{Characters, Session}

  @doc "Vàng hiện có của các người chơi (id số nguyên): `%{id => vàng}`."
  def balances(ids) do
    for id <- Enum.uniq(ids), is_integer(id), p = get(id), p != nil, into: %{}, do: {id, p.gold}
  end

  defp get(id) do
    Session.get(id)
  catch
    :exit, _ -> nil
  end

  @doc "Đã trả cho khóa `key` chưa."
  def settled?(key), do: Repo.exists?(from s in "tienlen_settlements", where: s.key == ^key)

  @doc """
  Trả các khoản nợ `debts` (`%{from, to, amount, reason}`, id người chơi) đúng một lần cho
  `key`. Trả `{:ok, khoản_đã_trả}`, `{:ok, :already_applied}` hoặc `{:error, lý_do}`.
  """
  def settle(key, debts, ref \\ nil) do
    debts =
      Enum.filter(debts, fn d ->
        is_integer(d.from) and is_integer(d.to) and d.from != d.to and is_integer(d.amount) and
          d.amount > 0
      end)

    cond do
      debts == [] -> {:ok, []}
      settled?(key) -> {:ok, :already_applied}
      true -> settle_held(key, debts, ref)
    end
  end

  defp settle_held(key, debts, ref) do
    ids = debts |> Enum.flat_map(&[&1.from, &1.to]) |> Enum.uniq() |> Enum.sort()

    with {:ok, held} <- hold_all(ids) do
      players = Map.new(held, fn {id, _ref, p} -> {id, p} end)

      try do
        paid = pay(debts, Map.new(players, fn {id, p} -> {id, p.gold} end))

        new =
          Enum.reduce(paid, players, fn d, acc ->
            acc
            |> update_in([d.from, :gold], &(&1 - d.amount))
            |> update_in([d.to, :gold], &(&1 + d.amount))
          end)

        changed = for {id, p} <- new, p.gold != players[id].gold, into: %{}, do: {id, p}

        result =
          Repo.transaction(fn ->
            now = DateTime.truncate(DateTime.utc_now(), :second)

            case Repo.insert_all("tienlen_settlements", [%{key: key, inserted_at: now}],
                   on_conflict: :nothing
                 ) do
              {1, _} ->
                Enum.each(changed, fn {id, p} ->
                  Characters.save!(id, p, "TIENLEN", short(ref || key))
                end)

                paid

              {0, _} ->
                Repo.rollback(:already_applied)
            end
          end)

        case result do
          {:ok, paid} ->
            release_all(held, changed)
            {:ok, paid}

          {:error, :already_applied} ->
            release_all(held, %{})
            {:ok, :already_applied}
        end
      rescue
        e ->
          Logger.error("Tiến Lên: trả vàng #{key} lỗi: " <> Exception.message(e))
          release_all(held, %{})
          {:error, :settle_failed}
      end
    end
  end

  @doc """
  `user_id` tiêu `amount` vàng (ném đồ trong bàn, T26). `{:ok, vàng_còn}` hoặc
  `{:error, :insufficient_coins}`.
  """
  def spend(user_id, amount, _reason, ref \\ nil, _also \\ fn -> :ok end)

  def spend(user_id, amount, _reason, ref, _also)
      when is_integer(user_id) and is_integer(amount) and amount > 0 do
    with {:ok, [{^user_id, href, p}] = held} <- hold_all([user_id]) do
      if p.gold < amount do
        release_all(held, %{})
        {:error, :insufficient_coins}
      else
        p2 = %{p | gold: p.gold - amount}

        try do
          Characters.save!(user_id, p2, "TIENLEN_THROW", short(ref))
          Session.release(user_id, href, p2)
          {:ok, p2.gold}
        rescue
          e ->
            Logger.error("Tiến Lên: trả tiền ném đồ lỗi: " <> Exception.message(e))
            release_all(held, %{})
            {:error, :spend_failed}
        end
      end
    end
  end

  def spend(_user_id, _amount, _reason, _ref, _also), do: {:error, :invalid_amount}

  # ---------- tiện ích ----------

  # giữ lần lượt theo id; một người không giữ được thì nhả những người đã giữ
  defp hold_all(ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case safe_hold(id) do
        {:ok, ref, p} when p != nil ->
          {:cont, {:ok, acc ++ [{id, ref, p}]}}

        {:ok, ref, nil} ->
          Session.release(id, ref, nil)
          release_all(acc, %{})
          {:halt, {:error, :no_character}}

        _ ->
          release_all(acc, %{})
          {:halt, {:error, :busy}}
      end
    end)
  end

  defp safe_hold(id) do
    Session.hold(id)
  catch
    :exit, _ -> {:error, :busy}
  end

  defp release_all(held, changed) do
    Enum.each(held, fn {id, ref, _p} -> Session.release(id, ref, Map.get(changed, id)) end)
  end

  defp short(nil), do: nil
  defp short(ref), do: String.slice(to_string(ref), 0, 64)

  # Người nợ trả tối đa số vàng đang có, chia theo tỉ lệ cho các chủ nợ (giữ thứ tự khoản nợ).
  # Viết lại từ `TienLen.Economy.pay/2` của repo gốc.
  @doc false
  def pay(debts, balances) do
    debts
    |> Enum.with_index()
    |> Enum.filter(fn {d, _i} ->
      Map.has_key?(balances, d.from) and Map.has_key?(balances, d.to)
    end)
    |> Enum.group_by(fn {d, _i} -> d.from end)
    |> Enum.flat_map(fn {debtor, owed} ->
      total = owed |> Enum.map(fn {d, _i} -> d.amount end) |> Enum.sum()
      available = min(total, max(balances[debtor], 0))
      shares = Enum.map(owed, fn {d, _i} -> div(d.amount * available, total) end)

      {paid, _left} =
        owed
        |> Enum.zip(shares)
        |> Enum.map_reduce(available - Enum.sum(shares), fn {{d, i}, share}, left ->
          extra = min(left, d.amount - share)
          {{%{d | amount: share + extra}, i}, left - extra}
        end)

      paid
    end)
    |> Enum.sort_by(fn {_d, i} -> i end)
    |> Enum.map(fn {d, _i} -> d end)
    |> Enum.filter(&(&1.amount > 0))
  end
end

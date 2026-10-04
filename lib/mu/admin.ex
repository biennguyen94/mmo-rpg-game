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
  alias Mu.Game.{Character, Session}

  @doc "Tặng `amount` EXP. `{:ok, %{level_before, level, experience, exp, online}}` hoặc `{:error, lý_do}`."
  def give_exp(name, amount, reason \\ ""), do: run("GIVE_EXP", name, amount, reason)

  @doc "Nâng nhân vật lên đúng cấp `level` (EXP trong cấp mới = 0)."
  def set_level(name, level, reason \\ ""), do: run("SET_LEVEL", name, {:level, level}, reason)

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

  defp run(action, name, amount, reason) when is_binary(name) and is_binary(reason) do
    case Repo.one(
           from c in Character,
             where: fragment("lower(?)", c.name) == ^String.downcase(name),
             select: %{id: c.id, account_id: c.account_id, name: c.name}
         ) do
      nil ->
        {:error, :no_character}

      c ->
        with {:ok, r} <- Session.admin_exp(c.account_id, c.id, amount) do
          {:ok, id} = Ecto.UUID.dump(c.id)

          Repo.insert_all("admin_log", [
            %{
              action: action,
              character_id: id,
              character_name: c.name,
              detail: Map.delete(r, :online),
              reason: reason
            }
          ])

          {:ok, r}
        end
    end
  end

  defp run(_, _, _, _), do: {:error, :bad_args}
end

defmodule Mu.Game.ZenAudit do
  @moduledoc """
  Bảng `zen_audit_log` (P5-M3, P5-6; migration `20261007000000_create_zen_audit_log.exs`): mỗi lần
  Zen của nhân vật đổi một dòng, ghi **trong cùng transaction** với thay đổi đó (người gọi đang
  ở trong `Repo.transaction`). Lý do (`reason`):

  - `MONSTER` — Zen rơi từ quái, gộp theo lần lưu nhân vật (`Characters.save/2`);
  - `BUY`, `SELL` (`ref` = NPC), `MAIL` (`ref` = id thư), `GUILD_CREATE` (`ref` = id guild),
    `TRADE` (P5-M4), `START` (Zen lúc tạo nhân vật), `BASELINE` (lúc chạy migration),
    `ADMIN` (script quản trị / test).
  """
  use Ecto.Schema

  alias Mu.Repo

  schema "zen_audit_log" do
    field :character_id, :binary_id
    field :delta, :integer
    field :balance, :integer
    field :reason, :string
    field :ref, :string
    field :at, :utc_datetime_usec, read_after_writes: true
  end

  @doc """
  Đặt Zen của nhân vật `cid` thành `zen` (script quản trị / test), ghi `ADMIN` với `ref` — một
  transaction, khóa row nhân vật. Không dùng trong luồng game.
  """
  def admin_set(cid, zen, ref) do
    import Ecto.Query

    Repo.transaction(fn ->
      old =
        Repo.one!(
          from(c in Mu.Game.Character, where: c.id == ^cid, lock: "FOR UPDATE", select: c.zen)
        )

      Repo.update_all(from(c in Mu.Game.Character, where: c.id == ^cid), set: [zen: zen])
      log(cid, zen - old, zen, "ADMIN", ref)
    end)
  end

  @doc "Ghi một dòng (bỏ qua `delta` 0)."
  def log(cid, delta, balance, reason, ref \\ nil)
  def log(_cid, 0, _balance, _reason, _ref), do: :ok

  def log(cid, delta, balance, reason, ref) do
    Repo.insert!(%__MODULE__{
      character_id: cid,
      delta: delta,
      balance: balance,
      reason: reason,
      ref: ref
    })

    :ok
  end
end

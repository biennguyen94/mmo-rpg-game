defmodule Mu.AuditTest do
  @moduledoc """
  P5-M3: `zen_audit_log` ghi mọi đổi Zen (mua, bán, thư, guild, Zen quái lúc lưu, tạo nhân vật,
  ADMIN) và `Mu.Audit` bắt được dupe / lệch: item không chỗ, đổi chủ không audit, Zen sửa tay;
  thao tác song song trên cùng món chỉ một lần thành công.
  """
  use Mu.DataCase, async: false

  import Ecto.Query

  alias Mu.Audit
  alias Mu.Game.{Character, Characters, Items, ItemLocation, Rng, ZenAudit}
  alias Mu.Repo

  defp checks(r), do: Enum.map(r.problems, & &1.check)
  defp logs(cid), do: Repo.all(from z in ZenAudit, where: z.character_id == ^cid, order_by: z.id)
  defp zen(cid), do: Repo.get!(Character, cid).zen

  defp char_with_zen(zen) do
    {_, c} = create_character()
    {:ok, _} = ZenAudit.admin_set(c.id, zen, "test")
    Repo.get!(Character, c.id)
  end

  test "mua / bán / Zen quái / tạo guild đều ghi zen_audit_log; tổng delta = Zen; audit sạch" do
    c = char_with_zen(20_000)
    {:ok, _} = Items.buy(c.id, "hp_potion_small", 2, 100, "lorencia_potion_merchant")
    pot = Enum.find(Items.load(c.id), &(&1.template_id == "hp_potion_small"))
    {:ok, _} = Items.sell(c.id, pot.id, 1, 50, "lorencia_potion_merchant")

    c = Repo.get!(Character, c.id)
    {:ok, _} = Characters.save(c, %{c | zen: c.zen + 37})

    c = Repo.update!(Ecto.Changeset.change(Repo.get!(Character, c.id), level: 20))

    {:ok, %{guild_id: gid}, _} =
      Mu.Guilds.create(c.id, "Z#{rem(System.unique_integer([:positive]), 99_999)}")

    rows = logs(c.id)
    assert Enum.map(rows, & &1.reason) == ~w(ADMIN BUY SELL MONSTER GUILD_CREATE)
    assert Enum.map(rows, & &1.delta) == [20_000, -200, 50, 37, -10_000]
    assert List.last(rows).ref == gid
    assert List.last(rows).balance == zen(c.id)
    assert Enum.sum(Enum.map(rows, & &1.delta)) == zen(c.id)

    r = Audit.run()
    assert r.problems == []
    assert r.supply.total >= zen(c.id)
    assert Enum.any?(r.supply.by_day, &(&1.reason == "BUY" and &1.spent <= -200))
  end

  test "bắt được: Zen sửa tay, item mất chỗ (orphan), đổi chủ không qua audit" do
    c = char_with_zen(500)
    {_, other} = create_character()
    {:ok, _} = Items.buy(c.id, "hp_potion_small", 1, 100, "lorencia_potion_merchant")
    [pot] = Enum.filter(Items.load(c.id), &(&1.template_id == "hp_potion_small"))
    assert Audit.run().problems == []

    # Zen sửa thẳng DB
    Repo.update_all(from(x in Character, where: x.id == ^c.id), set: [zen: 9_999])
    # món chuyển sang nhân vật khác không qua Items (không audit)
    Repo.update_all(from(l in ItemLocation, where: l.item_id == ^pot.id),
      set: [character_id: other.id]
    )

    r = Audit.run()
    assert "zen_mismatch" in checks(r)
    assert Enum.any?(r.problems, &(&1.check == "owner_mismatch" and &1.id == pot.id))

    Repo.delete_all(from(l in ItemLocation, where: l.item_id == ^pot.id))
    assert Enum.any?(Audit.run().problems, &(&1.check == "orphan" and &1.id == pot.id))
  end

  test "cố dupe: bán song song cùng một stack / ép song song bằng 1 jewel — chỉ một lần thành công" do
    c = char_with_zen(0)

    {:ok, _} =
      Items.pickup(c.id, %{serial: Mu.Ulid.generate(), template_id: "sword_t0"}, "test")

    sword = Enum.find(Items.load(c.id), &(&1.template_id == "sword_t0"))

    sells =
      1..6
      |> Task.async_stream(fn _ -> Items.sell(c.id, sword.id, nil, 500, "npc") end)
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(sells, &match?({:ok, _}, &1)) == 1
    assert zen(c.id) == 500
    assert Enum.sum(Enum.map(logs(c.id), & &1.delta)) == 500

    {:ok, _} =
      Items.pickup(c.id, %{serial: Mu.Ulid.generate(), template_id: "sword_t0"}, "test")

    {:ok, _} =
      Items.pickup(c.id, %{serial: Mu.Ulid.generate(), template_id: "jewel_bless"}, "test")

    items = Items.load(c.id)
    s2 = Enum.find(items, &(&1.template_id == "sword_t0"))
    j = Enum.find(items, &(&1.template_id == "jewel_bless"))

    ups =
      1..6
      |> Task.async_stream(fn i -> Items.upgrade(c.id, s2.id, j.id, Rng.new(i)) end)
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(ups, &match?({:ok, _}, &1)) == 1
    assert Repo.get!(Mu.Game.Item, s2.id).item_level == 1
    assert Audit.run().problems == []
  end
end

defmodule HacLong.Game.DollTest do
  # DECISIONS "Hình nhân vật Dungeon Crawl đủ lớp": ngoại hình theo đồ đang mặc (Engine.look, doll.json)
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine, Gear}

  @dir "priv/static/assets/doll"

  defp wear(p, ids) do
    Enum.reduce(ids, p, fn id, p ->
      {p, _} = Gear.add(p, %{Gear.new(id) | uid: "#" <> id})
      put_in(p, [:equip, String.to_atom(Data.item(id).slot)], "#" <> id)
    end)
  end

  defp set_ids(name), do: for({k, v} <- Data.items(), v[:set] == name, do: k)

  test "mọi hình trong bảng gán có file ảnh" do
    d = Data.doll()

    paths =
      Enum.flat_map(d["classes"], fn {_, c} -> Map.values(c) end) ++
        Enum.flat_map(d["sets"], fn {_, s} -> s |> Map.delete("open") |> Map.values() end) ++
        Map.values(d["weapons"]) ++ Map.values(d["shields"]) ++ Map.values(d["basic_armor"])

    missing = for p <- paths, is_binary(p), not File.exists?(Path.join(@dir, p <> ".png")), do: p
    assert missing == []
  end

  test "mọi bộ giáp, vũ khí, khiên trong game đều có hình" do
    d = Data.doll()

    for {id, it} <- Data.items(), it[:slot] in ~w(helm armor pants gloves boots), it[:set] do
      assert get_in(d, ["sets", it.set, it.slot]), "#{id} #{it.name}"
    end

    for {id, it} <- Data.items(),
        it[:slot] in ~w(weapon shield),
        String.starts_with?(id, "item_") do
      assert d[if(it.slot == "weapon", do: "weapons", else: "shields")][id], "#{id} #{it.name}"
    end
  end

  test "mặc đủ bộ: mũ, giáp, quần, găng, giày, áo choàng theo bộ; mũ kín ẩn tóc" do
    {:ok, p} = Engine.new_player("A", "dk")
    l = p |> wear(set_ids("Hắc Long") ++ ["item_0_17", "item_6_11"]) |> Engine.look()
    s = Data.doll()["sets"]["Hắc Long"]

    assert {l.helm, l.armor, l.pants, l.gloves, l.boots, l.cloak} ==
             {s["helm"], s["armor"], s["pants"], s["gloves"], s["boots"], s["cloak"]}

    assert l.hair == nil
    assert l.weapon == Data.doll()["weapons"]["item_0_17"]
    assert l.shield == Data.doll()["shields"]["item_6_11"]
  end

  test "mũ hở (lông vũ, băng đô) vẫn thấy tóc; bộ cấp thấp không có áo choàng; Đấu Sĩ có râu" do
    {:ok, e} = Engine.new_player("E", "elf")
    l = Engine.look(e)
    assert l.helm != nil and l.hair == Data.doll()["classes"]["elf"]["hair"]
    assert l.cloak == nil
    {:ok, m} = Engine.new_player("M", "mg")
    assert Engine.look(m).beard != nil
  end
end

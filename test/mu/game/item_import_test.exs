defmodule Mu.Game.ItemImportTest do
  @moduledoc "Test bắt buộc KB_ITEM_REFERENCE §6 (trừ đối chiếu items_raw.json: chưa có file, E6)."
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mu.Game.{Data, ItemImport}

  @source Path.expand("../../../data/items/phase1.json", __DIR__)
          |> File.read!()
          |> Jason.decode!()

  test "items.json sinh từ data/items khớp (mix mu.items.import --check)" do
    assert capture_io(fn -> Mix.Tasks.Mu.Items.Import.run(["--check"]) end) =~
             "không đổi (43 template)"
  end

  test "10 template Phase 1 + 12 P2-M2 + 21 P2-M4, templateId duy nhất, có nguồn gốc (KB_00_RULES §2)" do
    ids =
      ~w(hp_potion_small mp_potion_small sword_t0 shield_t0 helm_t0 armor_t0 pants_t0 gloves_t0 boots_t0 ring_hp_t0) ++
        ~w(staff_t0 bow_t0) ++
        for(
          set <- ~w(pad vine),
          part <- ~w(helm armor pants gloves boots),
          do: "#{set}_#{part}_t0"
        ) ++
        ~w(sword_t1 staff_t1 bow_t1 shield_t1 hp_potion_medium mp_potion_medium) ++
        for(
          set <- ~w(bronze bone silk),
          part <- ~w(helm armor pants gloves boots),
          do: "#{set}_#{part}_t1"
        )

    assert Enum.sort(Map.keys(Data.items())) == Enum.sort(ids)

    for {_, t} <- Data.items(), k <- ~w(sourceType version verified source) do
      assert Map.has_key?(t, k), "#{t["templateId"]} thiếu #{k}"
    end

    assert Data.item("sword_t0")["version"] == "s5+"
    assert Data.item("ring_hp_t0")["version"] == nil
  end

  test "iconRef có file hoặc iconPlaceholder; ring dùng custom" do
    for {_, t} <- Data.items() do
      assert match?(%{"group" => _, "index" => _}, t["iconRef"]) or t["iconPlaceholder"] == true
    end

    assert Data.item("ring_hp_t0")["iconRef"] == %{"custom" => "ring_hp_t0"}
  end

  test "P2-5: mọi vũ khí có weaponType; cung hai tay, tầm đánh theo loại" do
    for {_, t} <- Data.items(), t["slot"] == "WEAPON" do
      assert t["weaponType"] in ~w(sword axe mace spear bow crossbow staff), t["templateId"]
    end

    assert {Data.item("staff_t0")["weaponType"], Data.item("bow_t0")["weaponType"]} ==
             {"staff", "bow"}

    assert Mu.Game.Inventory.two_handed?(Data.item("bow_t0"))
    refute Mu.Game.Inventory.two_handed?(Data.item("sword_t0"))

    assert {:error, [msg]} =
             Mu.Game.ItemImport.build(%{
               "items" => [Map.delete(Data.item("sword_t0"), "weaponType")]
             })

    assert msg =~ "weaponType"
  end

  test "requirements = round(requirementsRaw × 0.35), reference.adjusted ⇒ IMPLEMENTATION" do
    for {_, t} <- Data.items(), raw = get_in(t, ["reference", "requirementsRaw"]) do
      assert t["sourceType"] == "IMPLEMENTATION"
      assert t["requirements"]["strength"] == ItemImport.round_half_up(raw["strength"] * 0.35)
    end

    assert Data.item("armor_t0")["requirements"]["strength"] == 28
    assert Data.item("sword_t0")["requirements"]["strength"] == 21
    assert ItemImport.round_half_up(70 * 0.35) == 25
  end

  test "sellPrice = buyPrice × sellRatio (D6): HP potion 100 → 50 (KB_CONFIG §4)" do
    assert Data.item("hp_potion_small")["sellPrice"] == 50
    assert Data.item("sword_t0")["sellPrice"] == 500
  end

  test "không dùng group 12 khi wings tắt" do
    refute Enum.any?(Map.values(Data.items()), &(get_in(&1, ["iconRef", "group"]) == 12))
  end

  test "dữ liệu sai bị từ chối" do
    potion = Enum.find(@source["items"], &(&1["templateId"] == "hp_potion_small"))
    sword = Enum.find(@source["items"], &(&1["templateId"] == "sword_t0"))
    assert {:error, errs} = ItemImport.build(%{"items" => [potion, potion]})
    assert Enum.any?(errs, &(&1 =~ "trùng"))

    bad = put_in(sword, ["requirements", "strength"], 60)
    assert {:error, [e]} = ItemImport.build(%{"items" => [bad]})
    assert e =~ "requirements"

    assert {:error, _} =
             ItemImport.build(%{"items" => [Map.put(sword, "sourceType", "REFERENCE")]})

    assert {:error, _} = ItemImport.build(%{"items" => [Map.put(sword, "slot", "HAT")]})

    assert {:error, _} =
             ItemImport.build(%{
               "items" => [Map.put(sword, "iconRef", %{"group" => 12, "index" => 1})]
             })

    assert {:error, _} = ItemImport.build(%{"items" => [Map.put(sword, "iconRef", %{})]})
  end

  @tag :skip
  test "template có reference khớp dòng gốc trong priv/reference/items_raw.json (chờ file: OPEN_QUESTIONS E6)"
end

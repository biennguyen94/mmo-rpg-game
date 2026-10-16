defmodule HacLong.AdminMaxTest do
  @moduledoc "Công thức nhân vật tối đa trong docs/ADMIN_GUIDE.md §6: mọi lệnh hợp lệ, mặc được đủ 11 ô (Pháp Sư 10)."
  use ExUnit.Case, async: true

  alias HacLong.Admin
  alias HacLong.Game.{Commands, Gear}

  @exc_w ~w(atk_pct crit heal_kill mp_kill atk_lvl ar_pct)
  @exc_a ~w(hp_pct dmg_red gold_pct mp_pct reflect def_rate)
  @set %{
    "dk" => {"item_0_26", "item_6_18", ~w(item_7_33 item_8_33 item_9_33 item_10_33 item_11_33)},
    "dw" => {"item_5_11", "item_6_18", ~w(item_7_30 item_8_30 item_9_30 item_10_30 item_11_30)},
    "elf" => {"item_4_24", nil, ~w(item_7_31 item_8_31 item_9_31 item_10_31 item_11_31)},
    "mg" => {"item_0_28", nil, ~w(item_8_29 item_9_29 item_10_29 item_11_29)}
  }

  defp op(p, name, params) do
    {:ok, f} = Admin.build(name, params)
    assert {:ok, p, _msg} = f.(p)
    p
  end

  for cls <- ~w(dk dw elf mg) do
    test "nhân vật #{cls} tối đa" do
      cls = unquote(cls)
      {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Max#{cls}", "cls" => cls})
      {weapon, shield, set} = @set[cls]
      full = %{"opt" => 4, "luck" => true, "up" => 11}

      p =
        p
        |> op("set_level", %{"level" => 50})
        |> op("add_stats", %{"str" => 300, "agi" => 300, "vit" => 200, "ene" => 300})
        |> op("give_gear", Map.merge(full, %{"base" => weapon, "skill" => true, "exc" => @exc_w}))

      p =
        if shield,
          do: op(p, "give_gear", Map.merge(full, %{"base" => shield, "exc" => @exc_a})),
          else: p

      p =
        Enum.reduce(
          set,
          p,
          &op(&2, "give_gear", Map.merge(full, %{"base" => &1, "exc" => @exc_a}))
        )

      p =
        p
        |> op("give_gear", Map.merge(full, %{"base" => "item_13_24", "exc" => @exc_a}))
        |> op("give_gear", Map.merge(full, %{"base" => "item_13_24", "exc" => @exc_a}))
        |> op("give_gear", Map.merge(full, %{"base" => "item_13_27", "exc" => @exc_w}))
        |> op("give_gear", Map.merge(full, %{"base" => "wing_#{cls}_3", "wopt" => "ignore_def"}))

      wing = Enum.find(Gear.list(p), &(&1.base == "wing_#{cls}_3"))
      assert wing.opt == 4 and wing.luck and wing.wopt == "ignore_def"

      p =
        Enum.reduce(Gear.list(p), p, fn g, p ->
          {r, p} = Commands.run(p, %{"act" => "equip", "id" => g.uid})
          assert r.ok, "#{g.base}: #{r[:msg]}"
          p
        end)

      worn = p.equip |> Map.values() |> Enum.count(& &1)
      assert worn == if(shield, do: 11, else: 10) - if(cls == "mg", do: 1, else: 0)
    end
  end
end

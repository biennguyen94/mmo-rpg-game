defmodule HacLong.Game.ExcLinesTest do
  @moduledoc "Mỗi dòng Excellent (vũ khí, giáp) đều có tác dụng thật: cộng chỉ số, hoặc vào tổng dòng mà trận / thưởng đọc."
  use ExUnit.Case, async: true

  alias HacLong.Game.{Commands, Data, Engine, Gear}

  @r Data.rules().admin_max_build
  @base %{"weapon" => "item_0_26", "armor" => "item_8_33"}

  defp hero(slot, exc) do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Dong", "cls" => "dk"})
    g = Gear.new(@base[slot], 0) |> Map.put(:exc, exc)
    # đủ sức mặc (thiếu điều kiện thì đồ không có tác dụng)
    p = %{p | level: 50, gear: [g], stats: %{p.stats | str: 500, agi: 300}}
    Map.update!(p, :equip, &Map.put(&1, String.to_existing_atom(slot), g.uid))
  end

  # dòng → chỉ số `Engine.derived` thay đổi (dòng không có chỉ số riêng thì kiểm ở tổng dòng)
  @stat %{
    "atk_pct" => :atk,
    "atk_lvl" => :atk,
    "crit" => :crit,
    "ar_pct" => :ar,
    "hp_pct" => :maxHp,
    "mp_pct" => :maxMp,
    "def_rate" => :dodge,
    "dmg_red" => :excAbsorb,
    "reflect" => :excReflect
  }

  for {slot, lines} <- [{"weapon", @r.exc_weapon}, {"armor", @r.exc_armor}], id <- lines do
    @slot slot
    @id id
    test "dòng Excellent #{id} (#{slot}) có tác dụng" do
      plain = hero(@slot, [])
      with_line = hero(@slot, [@id])
      key = String.to_existing_atom(@id)
      assert Gear.exc_stats(with_line)[key] > 0
      assert Gear.exc_stats(plain)[key] == 0

      if f = @stat[@id] do
        assert Engine.derived(with_line)[f] > Engine.derived(plain)[f],
               "#{@id} không đổi #{f}"
      end
    end
  end
end

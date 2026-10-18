defmodule HacLong.Game.Crafting do
  @moduledoc """
  Nghề: nấu ăn (Bác Đầu Bếp) và rèn đồ (Thợ Rèn). Hàm thuần, như `Engine`.

  - **Nấu ăn** (`cook/2`): công thức `npc: "cook"` trong `RECIPES`, một số cần cấp nghề
    (`level`). Món ăn (`slot: "food"`) ăn ngoài trận (`eat/2`) thì có tác dụng trong một số
    trận (`food.battles`): cộng phần trăm máu/tấn công/phòng thủ/kinh nghiệm/vàng
    (`food_bonus/2`). Mỗi lúc chỉ một món; ăn món khác thì thay món cũ.
  - **Pha đồ uống** (`brew/2`, Bà Lang): công thức `npc: "herbalist"`, dùng chung cấp nghề Nấu ăn.
    Đồ uống là món `slot: "food"` có `drink: true`, nằm ô riêng (`p.drink`) nên **cộng dồn** với món ăn;
    uống món khác thì thay đồ uống cũ.
  - **Rèn đồ** (`smith/2`): chọn vũ khí, giáp hoặc khiên; tốn quặng và vàng, ra một món đồ
    ngẫu nhiên hợp cấp. Cấp nghề rèn càng cao càng dễ ra đồ nhiều dòng cộng thêm (+12).
  - Mỗi lần nấu/rèn được 1 kinh nghiệm nghề; cấp nghề 1–5 (`level/1`).

  Trạng thái trong nhân vật: `crafting: %{cook: số, smith: số}`, `food` / `drink`: `%{id, left} | nil`.
  """

  alias HacLong.Game.{Data, Engine, Gear}

  # số ở `RULES.crafting` (`priv/game_data/rules.json`)
  @rules Data.rules().crafting
  @levels @rules.levels
  @names %{cook: "Nấu ăn", smith: "Rèn đồ"}
  # nguyên liệu mỗi lần rèn theo loại đồ; vàng = cấp nhân vật × 15
  @smith_costs @rules.smith_costs

  def levels, do: @levels
  def max_level, do: length(@levels)
  def smith_costs, do: @smith_costs
  def smith_gold(p), do: p.level * @rules.smith_gold_per_level

  def xp(p, skill), do: Map.get(Map.get(p, :crafting) || %{}, skill, 0)
  def level(xp) when is_integer(xp), do: Enum.count(@levels, &(xp >= &1))
  def level(p, skill), do: level(xp(p, skill))

  @doc "Tỉ lệ số dòng cộng thêm khi rèn ở cấp nghề `lv` (B-15): 3 dòng 6% mỗi cấp, 2 dòng 50%, còn lại 1 dòng."
  def smith_weights(lv) do
    epic = @rules.smith_epic_per_level * lv
    [{3, epic}, {2, @rules.smith_rare}, {1, 100 - @rules.smith_rare - epic}]
  end

  defp gain(p, skill) do
    before = level(p, skill)
    all = Map.get(p, :crafting) || %{cook: 0, smith: 0}
    p = Map.put(p, :crafting, Map.put(all, skill, xp(p, skill) + 1))
    now = level(p, skill)

    note =
      if now > before, do: " Nghề #{@names[skill]} lên cấp #{now}!", else: ""

    {p, note}
  end

  defp has_all?(p, needs), do: Enum.all?(needs, fn {id, n} -> Map.get(p.inv, id, 0) >= n end)

  defp take_all(p, needs) do
    inv =
      Enum.reduce(needs, p.inv, fn {id, n}, inv ->
        if inv[id] > n, do: Map.put(inv, id, inv[id] - n), else: Map.delete(inv, id)
      end)

    %{p | inv: inv}
  end

  # ---------- Nấu ăn ----------

  def cook(p, id), do: make(p, id, "cook", &"Nấu được #{&1}.#{&2}")

  @doc "Pha đồ uống ở Bà Lang (công thức `npc: \"herbalist\"`), dùng chung cấp nghề Nấu ăn."
  def brew(p, id), do: make(p, id, "herbalist", &"Pha được #{&1}.#{&2}")

  defp make(p, id, npc, done) do
    r = Data.recipe(id)

    cond do
      r == nil or r.npc != npc ->
        {%{ok: false, msg: "Không có món này."}, p}

      level(p, :cook) < (r[:level] || 1) ->
        {%{ok: false, msg: "Cần nghề Nấu ăn cấp #{r.level}."}, p}

      not has_all?(p, r.needs) ->
        {%{ok: false, msg: "Chưa đủ nguyên liệu."}, p}

      true ->
        p = p |> take_all(r.needs) |> Engine.add_item(r.out)
        {p, note} = gain(p, :cook)
        {%{ok: true, msg: done.(Data.item(r.out).name, note)}, p}
    end
  end

  @doc "Ăn / uống món `id` (ngoài trận): có tác dụng trong `food.battles` trận tới (đồ uống vào ô `drink`)."
  def eat(p, id) do
    it = Data.item(id)
    drink = it != nil and it[:drink] == true

    cond do
      p.battle ->
        {%{
           ok: false,
           msg: if(drink, do: "Không uống được trong trận.", else: "Không ăn được trong trận.")
         }, p}

      it == nil or it.slot != "food" or Map.get(p.inv, id, 0) <= 0 ->
        {%{ok: false, msg: "Không có món này."}, p}

      true ->
        p =
          take_all(p, %{id => 1})
          |> Map.put(if(drink, do: :drink, else: :food), %{id: id, left: it.food.battles})

        msg = if drink, do: "Uống #{it.name}: #{it.desc}", else: "Ăn #{it.name}: #{it.desc}"
        {%{ok: true, msg: msg}, p}
    end
  end

  @doc "Phần trăm cộng thêm của món đang ăn + đồ đang uống cho chỉ số `key` (hp, atk, def, xp, gold)."
  def food_bonus(p, key), do: buff(Map.get(p, :food), key) + buff(Map.get(p, :drink), key)

  defp buff(%{id: id, left: left}, key) when left > 0 do
    case Data.item(id) do
      %{food: %{buff: b}} -> Map.get(b, key, 0)
      _ -> 0
    end
  end

  defp buff(_, _key), do: 0

  @doc "Hết một trận: món ăn và đồ uống bớt một trận tác dụng."
  def tick(p), do: p |> tick(:food) |> tick(:drink)

  defp tick(p, key) do
    case Map.get(p, key) do
      %{left: left} = f when left > 1 -> Map.put(p, key, %{f | left: left - 1})
      %{} -> Map.put(p, key, nil)
      nil -> p
    end
  end

  # ---------- Rèn đồ ----------

  def smith(p, slot) do
    cost = @smith_costs[slot]
    gold = smith_gold(p)

    cond do
      cost == nil ->
        {%{ok: false, msg: "Không rèn được loại này."}, p}

      p.battle ->
        {%{ok: false, msg: "Đang trong trận."}, p}

      not has_all?(p, cost) ->
        {%{ok: false, msg: "Chưa đủ quặng."}, p}

      p.gold < gold ->
        {%{ok: false, msg: "Cần #{gold} vàng."}, p}

      length(Gear.bag(p)) >= Gear.max_bag() ->
        {%{ok: false, msg: "Túi trang bị đầy (#{Gear.max_bag()} món). Bán bớt đã."}, p}

      true ->
        g =
          Gear.roll(
            max(p.level, Data.rules().chests.min_level),
            smith_weights(level(p, :smith)),
            # Phase 15b: rèn "giáp" ra một món bất kỳ của bộ giáp, đúng lớp người rèn
            if(slot == "armor", do: "set", else: slot),
            p.cls
          )

        p = %{take_all(p, cost) | gold: p.gold - gold}
        {p, :kept} = Gear.add(p, g)
        {p, note} = gain(p, :smith)

        {%{
           ok: true,
           msg: "Rèn được #{Gear.label(g)}!#{note}",
           gear: g.uid
         }, p}
    end
  end
end

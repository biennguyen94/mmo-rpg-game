defmodule HacLong.Game.Data do
  @moduledoc """
  Dữ liệu game, đọc lúc biên dịch từ mọi file `priv/game_data/*.json` (sửa file để thêm
  quái, vùng đất, vật phẩm, đổi số luật chơi; biên dịch lại là có hiệu lực). Mỗi file là một
  object gồm một vài khóa lớn bên dưới; các file được ghép lại, hai file trùng khóa là lỗi biên
  dịch. Tham chiếu sai (id món đồ, quái, lớp...) cũng là lỗi biên dịch (`HacLong.Game.DataCheck`).
  Client nhận cùng dữ liệu này qua `window.GAME_DATA` (xem `HacLongWeb.PageController`).

  | File | Khóa |
  |---|---|
  | `classes.json` | `CLASSES` |
  | `zones.json` | `ZONES`, `BOSS_DROPS` |
  | `items.json` | `ITEMS` |
  | `shop.json` | `SHOP` |
  | `recipes.json` | `RECIPES` |
  | `quests.json` | `QUESTS` |
  | `pets.json` | `PETS` |
  | `furniture.json` | `FURNITURE` |
  | `events.json` | `EVENTS` |
  | `upgrade.json` | `UPGRADE`, `JEWELS` |
  | `chaos.json` | `CHAOS` |
  | `rules.json` | `RULES` (số luật chơi: chiến đấu, EXP, rơi đồ, giá, rương, rèn, tháp, thú, bang, chợ, từ cấm...) |

  - `CLASSES`: lớp nhân vật với chỉ số gốc (`base`), điểm mỗi cấp (`points`), công thức chỉ số
    (`derived`) và các kỹ năng (`skills`, mở ở cấp `level`; `effect` là kiểu tác dụng, số của nó ở
    `RULES.skill_effects`).
  - `ZONES`: vùng đất theo thứ tự mở khóa; mỗi vùng có quái thường và một trùm.
    Quái chỉ khai báo `level`, `mult` (hệ số sức mạnh, mặc định 1) và `special`
    (đòn đặc biệt của trùm, dùng mỗi `every` lượt với sát thương ×`mult`, có thể kèm hiệu ứng
    `effect`), `on_hit` (hiệu ứng gây ra với xác suất `chance` mỗi đòn trúng);
    chỉ số còn lại tính trong `HacLong.Game.Engine.make_monster/2`.
  - `ITEMS`: `slot` là weapon | armor | shield | potion; `drop: true` là đồ chỉ rơi từ trùm.
  - `BOSS_DROPS`: đồ trùm rơi ra lần đầu bị hạ. `SHOP`: những món cửa hàng bán.
  - `ITEMS` có `slot: "material"`: nguyên liệu (thu thập trên bản đồ), `sprite` là hình của nó.
  - `RECIPES`: công thức pha chế ở NPC `npc`: `needs` (nguyên liệu → số lượng) ra một `out`.
  - `ITEMS` vũ khí/giáp/khiên có `doll`: lớp hình (trong `priv/static/assets/doll`) vẽ lên
    nhân vật khi mặc món đó; `CLASSES` có `hair` (lớp tóc).
  - `PETS`: thú cưng bán ở Người Nuôi Thú; `bonus` là phần trăm cộng thêm (`hp`, `atk`, `def`,
    `gold` từ quái, `xp`).
  - `FURNITURE`: đồ trang trí nhà bán ở Thợ Mộc; `comfort` là điểm tiện nghi.
  - `ITEMS` có `slot: "wing"`: cánh (ô trang bị thứ tư) của lớp `cls`, cấp `tier`; `dmg` / `absorb`
    là phần sát thương gây thêm / giảm khi nhận.
  - `UPGRADE`: các bước ép bằng ngọc từ +6 (`steps`: `level`, `jewel`, `rate`, `fail` =
    nil | `down` (tụt một cấp) | `destroy` (vỡ đồ)); từ `double_from` mỗi cấp tính gấp đôi; ép thành
    công từ `announce_from` thì báo cả server. +1 → +5 vẫn dùng quặng như cũ (`Engine.upgrade_cost/2`).
  - `JEWELS`: tỉ lệ rơi ngọc (`weights` theo loại; quái cấp ≥ `monster_level`, trùm, tháp, rương).
  - `CHAOS`: công thức Máy Hỗn Nguyên (`HacLong.Game.Chaos`).
  - `QUESTS`: nhiệm vụ nhận ở Trưởng Làng. `type`: `kill` (hạ `count` con `target`),
    `collect` (nộp `count` nguyên liệu `target`), `boss` (hạ trùm `target`). Nhận được khi
    vùng `zone` đã mở và đã xong các nhiệm vụ trong `requires`.

  Khóa của các trường được chuyển thành atom; id (lớp, vật phẩm, trùm) giữ nguyên là chuỗi
  vì chúng đến từ client và được lưu trong database.
  """

  @dir Path.expand("../../../priv/game_data", __DIR__)
  @files @dir |> Path.join("*.json") |> Path.wildcard() |> Enum.sort()
  for f <- @files, do: @external_resource(f)

  @doc false
  # thêm / bớt file trong thư mục cũng biên dịch lại (`@external_resource` chỉ theo dõi file đã có)
  def __mix_recompile__?,
    do: @dir |> Path.join("*.json") |> Path.wildcard() |> Enum.sort() != @files

  atomize = fn atomize, v ->
    cond do
      is_map(v) -> Map.new(v, fn {k, x} -> {String.to_atom(k), atomize.(atomize, x)} end)
      is_list(v) -> Enum.map(v, &atomize.(atomize, &1))
      true -> v
    end
  end

  # mỗi file là một object các khóa lớn (`CLASSES`, `ZONES`...); hai file cùng khóa là lỗi
  raw =
    Enum.reduce(@files, %{}, fn f, acc ->
      part = f |> File.read!() |> Jason.decode!()

      case Enum.filter(Map.keys(part), &Map.has_key?(acc, &1)) do
        [] ->
          Map.merge(acc, part)

        dup ->
          raise CompileError,
            description: "#{Path.basename(f)}: khóa #{inspect(dup)} đã có ở file khác"
      end
    end)

  by_id = fn m -> Map.new(m, fn {id, x} -> {id, atomize.(atomize, x)} end) end

  @classes by_id.(raw["CLASSES"])
  @zones atomize.(atomize, raw["ZONES"])
  @items by_id.(raw["ITEMS"])
  @boss_drops raw["BOSS_DROPS"]
  @pets atomize.(atomize, raw["PETS"])
  @furniture atomize.(atomize, raw["FURNITURE"])
  @events atomize.(atomize, raw["EVENTS"])
  @shop raw["SHOP"]
  @recipes atomize.(atomize, raw["RECIPES"])
           |> Enum.map(
             &Map.update!(&1, :needs, fn n ->
               Map.new(n, fn {k, v} -> {Atom.to_string(k), v} end)
             end)
           )
  @quests atomize.(atomize, raw["QUESTS"])
          |> Enum.map(fn q ->
            Map.update!(q, :reward, fn r ->
              Map.update!(r, :items, fn i ->
                Map.new(i, fn {k, v} -> {Atom.to_string(k), v} end)
              end)
            end)
          end)

  strs = fn m -> Map.new(m, fn {k, v} -> {Atom.to_string(k), v} end) end

  @upgrade atomize.(atomize, raw["UPGRADE"])
  @upgrade_steps Map.new(@upgrade.steps, &{&1.level, &1})
  @jewels atomize.(atomize, raw["JEWELS"])
          |> Map.update!(:weights, strs)
          |> Map.update!(:chest_chance, strs)
  @chaos atomize.(atomize, raw["CHAOS"]) |> Enum.map(&Map.update!(&1, :items, strs))

  # RULES: số luật chơi (chiến đấu, kinh tế, rơi đồ...). Khóa thành atom; danh sách id món đồ
  # (`start_items`, `smith_costs`) giữ khóa chuỗi như `inv`.
  @rules atomize.(atomize, raw["RULES"])
         |> update_in([:character, :start_items], strs)
         |> update_in([:tutorial, :reward, :items], strs)
         |> update_in(
           [:crafting, :smith_costs],
           &Map.new(&1, fn {k, v} -> {Atom.to_string(k), strs.(v)} end)
         )
  @raw_rules raw["RULES"]

  @check %{
    classes: @classes,
    zones: @zones,
    items: @items,
    boss_drops: @boss_drops,
    shop: @shop,
    recipes: @recipes,
    quests: @quests,
    pets: @pets,
    furniture: @furniture,
    events: @events,
    upgrade: @upgrade,
    jewels: @jewels,
    chaos: @chaos,
    rules: @rules
  }
  HacLong.Game.DataCheck.run!(@check)

  @doc false
  # cho `HacLong.World.Maps` kiểm bản đồ lúc biên dịch
  def check_input, do: @check

  @doc """
  Số luật chơi (`RULES` trong `priv/game_data/rules.json`). Các module đọc lúc biên dịch
  (`@x Data.rules().nhóm.khóa`), nên sửa số xong phải biên dịch lại như mọi dữ liệu khác.
  """
  def rules, do: @rules
  @doc "`RULES` nguyên dạng JSON (khóa chuỗi), gửi cho client."
  def raw_rules, do: @raw_rules

  @doc "Bình máu hợp cấp `level` (`RULES.loot.potions`: mốc cấp cao nhất không quá `level`)."
  def potion_for(level),
    do:
      (Enum.find(@rules.loot.potions, &(level >= &1.level)) || List.last(@rules.loot.potions)).id

  def upgrade, do: @upgrade
  @doc "Bước ép lên cấp `level` bằng ngọc (nil nếu là bước dùng quặng)."
  def upgrade_step(level), do: Map.get(@upgrade_steps, level)
  def jewels, do: @jewels
  def chaos, do: @chaos
  def chaos(id), do: Enum.find(@chaos, &(&1.id == id))

  def classes, do: @classes
  def class(id), do: Map.get(@classes, id)
  def zones, do: @zones
  def zone(i) when is_integer(i) and i >= 0, do: Enum.at(@zones, i)
  def zone(_), do: nil
  def zone_count, do: length(@zones)

  @monsters Enum.flat_map(@zones, fn z -> [z.boss | z.monsters] end) |> Map.new(&{&1.id, &1})
  @doc "Quái (hoặc trùm vùng) theo id."
  def monster(id), do: Map.get(@monsters, id)
  def items, do: @items
  def item(id), do: Map.get(@items, id)
  def boss_drop(boss_id), do: Map.get(@boss_drops, boss_id)
  def shop, do: @shop
  def recipes, do: @recipes
  def recipe(id), do: Enum.find(@recipes, &(&1.id == id))
  def pets, do: @pets
  def pet(id), do: Enum.find(@pets, &(&1.id == id))
  def events, do: @events
  def event(id), do: Enum.find(@events, &(&1.id == id))
  def furniture, do: @furniture
  def furniture(id), do: Enum.find(@furniture, &(&1.id == id))
  def quests, do: @quests
  def quest(id), do: Enum.find(@quests, &(&1.id == id))
end

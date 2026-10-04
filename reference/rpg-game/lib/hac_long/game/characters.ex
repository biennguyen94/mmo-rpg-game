defmodule HacLong.Game.Characters do
  @moduledoc """
  Đọc/ghi nhân vật trong PostgreSQL và chuyển qua lại giữa dòng trong bảng
  và map trạng thái mà `HacLong.Game.Engine` dùng.
  """

  import Ecto.Query
  alias HacLong.Repo
  alias HacLong.Game.{Character, Names}
  alias HacLong.World
  alias HacLong.World.Maps

  @save_version 1

  def load(user_id) do
    case Repo.get_by(Character, user_id: user_id) do
      nil -> nil
      c -> to_player(c)
    end
  end

  @doc """
  Ghi đè toàn bộ trạng thái nhân vật (tạo mới nếu chưa có).

  Cùng transaction đó ghi nhật ký vàng (`gold_log`, khi vàng đổi) và đồ hiếm (`gear_log`, đồ
  chỉ số ngẫu nhiên vào/ra). `reason`/`ref` cho biết vì sao đổi (vd. `"SELL"`, `"TRADE"`);
  bỏ trống thì lấy lý do `Session` đặt cho lệnh đang chạy (`put_reason/2`), không có thì `"OTHER"`.
  """
  def save!(user_id, player, reason \\ nil, ref \\ nil) do
    attrs =
      player
      |> Map.merge(%{
        map_id: player.pos.map,
        x: player.pos.x,
        y: player.pos.y,
        name_key: Names.key(player.name)
      })
      |> Map.take(Character.fields())

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      old = locked_row(user_id)

      Repo.insert!(
        struct(
          Character,
          Map.merge(attrs, %{user_id: user_id, inserted_at: now, updated_at: now})
        ),
        on_conflict: {:replace, Character.fields() ++ [:updated_at]},
        conflict_target: :user_id
      )

      log!(user_id, old, %{gold: player.gold, gear: player[:gear] || []}, reason, ref)
    end)

    :ok
  end

  @doc """
  Lý do (và mã tham chiếu) cho các lần lưu nhân vật tiếp theo trong tiến trình này, tới khi
  đặt lại. `Session` gọi trước mỗi lệnh.
  """
  def put_reason(reason, ref \\ nil) do
    Process.put(:hl_save_reason, {reason, ref})
    :ok
  end

  @doc "Tên đã có người khác dùng chưa (không phân biệt hoa thường)."
  def name_taken?(name) do
    Repo.exists?(from c in Character, where: c.name_key == ^Names.key(name))
  end

  def delete!(user_id) do
    Repo.transaction(fn ->
      old = locked_row(user_id)
      Repo.delete_all(from c in Character, where: c.user_id == ^user_id)
      if old, do: log!(user_id, old, %{gold: 0, gear: []}, "DELETE", nil)
    end)

    :ok
  end

  # ---------- Nhật ký vàng / đồ hiếm ----------

  defp locked_row(user_id) do
    Repo.one(
      from c in Character,
        where: c.user_id == ^user_id,
        select: %{gold: c.gold, gear: c.gear},
        lock: "FOR UPDATE"
    )
  end

  defp log!(user_id, old, new, reason, ref) do
    {reason, ref} = reason_ref(reason, ref)
    old = old || %{gold: 0, gear: []}
    delta = new.gold - old.gold

    if delta != 0 do
      Repo.insert_all("gold_log", [
        %{user_id: user_id, delta: delta, balance: new.gold, reason: reason, ref: ref}
      ])
    end

    before = Map.new(old.gear || [], &{&1["uid"], {&1["base"], &1["rarity"]}})
    now = Map.new(new.gear, &{&1.uid, {&1.base, &1.rarity}})

    rows =
      for {uid, {base, rarity}} <- Map.drop(now, Map.keys(before)) do
        %{user_id: user_id, uid: uid, base: base, rarity: rarity, action: "in"}
      end ++
        for {uid, {base, rarity}} <- Map.drop(before, Map.keys(now)) do
          %{user_id: user_id, uid: uid, base: base, rarity: rarity, action: "out"}
        end

    if rows != [] do
      Repo.insert_all("gear_log", Enum.map(rows, &Map.merge(&1, %{reason: reason, ref: ref})))
    end

    :ok
  end

  defp reason_ref(nil, ref) do
    case Process.get(:hl_save_reason) do
      {reason, ref2} -> reason_ref(reason, ref || ref2)
      nil -> reason_ref("OTHER", ref)
    end
  end

  defp reason_ref(reason, ref) do
    ref = if ref == nil, do: nil, else: ref |> to_string() |> String.slice(0, 64)
    {String.slice(reason, 0, 32), ref}
  end

  # Cột kiểu map được Postgres trả về với khóa chuỗi; đổi lại thành atom như engine dùng.
  # Cấp nâng theo loại đồ thường (dữ liệu trước Đợt 3) được tách thành bản riêng từng món.
  defp to_player(%Character{} = c), do: c |> to_map() |> HacLong.Game.Engine.split_upgrades()

  defp to_map(c) do
    %{
      version: @save_version,
      name: c.name,
      cls: c.cls,
      level: c.level,
      xp: c.xp,
      gold: c.gold,
      hp: c.hp,
      points: c.points,
      stats: Map.new(~w(str agi vit ene)a, &{&1, Map.fetch!(c.stats, Atom.to_string(&1))}),
      mp: c.mp || 0,
      equip: Map.new(~w(weapon armor shield wing)a, &{&1, Map.get(c.equip, Atom.to_string(&1))}),
      inv: c.inv,
      bosses: c.bosses,
      kills: c.kills,
      deaths: c.deaths,
      victory: c.victory,
      battle: c.battle && atomize(c.battle),
      pos: pos(c),
      waystones: Enum.filter(c.waystones || [], &(&1 in Maps.waystone_ids())),
      quests: quests(c.quests),
      victory_at: c.victory_at,
      daily: daily(c.daily),
      tower: tower(c.tower),
      tower_best: c.tower_best || 0,
      tutorial: c.tutorial,
      upgrades:
        Map.filter(c.upgrades || %{}, fn {id, _} ->
          HacLong.Game.Data.item(id) || HacLong.Game.Gear.instance?(id)
        end),
      fish_caught: c.fish_caught || 0,
      achievements: c.achievements || [],
      title: c.title,
      gear: HacLong.Game.Gear.load(c.gear),
      bestiary: c.bestiary || %{},
      rebirths: c.rebirths || 0,
      chest_day: c.chest_day,
      pets: Enum.filter(c.pets || [], &HacLong.Game.Pets.data/1),
      pet: if(c.pet && HacLong.Game.Pets.data(c.pet), do: c.pet),
      pet_xp: c.pet_xp || %{},
      daily_done: c.daily_done || 0,
      boss_top: c.boss_top || 0,
      food: food(c.food),
      crafting: %{
        cook: (c.crafting || %{})["cook"] || 0,
        smith: (c.crafting || %{})["smith"] || 0
      },
      festival: c.festival || 0,
      furniture:
        Map.filter(c.furniture || %{}, fn {id, _} -> HacLong.Game.Data.furniture(id) end),
      decor:
        for d <- c.decor || [], HacLong.Game.Data.furniture(d["id"]) do
          %{id: d["id"], x: d["x"], y: d["y"]}
        end,
      storage: HacLong.Game.Storage.load(c.storage)
    }
  end

  # món ăn đang có tác dụng (bỏ nếu món không còn trong dữ liệu)
  defp food(%{"id" => id, "left" => left}) when is_integer(left) and left > 0 do
    if HacLong.Game.Data.item(id), do: %{id: id, left: left}
  end

  defp food(_), do: nil

  # Bỏ nhiệm vụ không còn trong dữ liệu game (đổi tên, xóa bớt).
  defp quests(%{"active" => active, "done" => done}) do
    known = MapSet.new(Enum.map(HacLong.Game.Data.quests(), & &1.id))

    %{
      active: Map.filter(active, fn {id, _} -> id in known end),
      done: Enum.filter(done, &(&1 in known))
    }
  end

  defp quests(_), do: HacLong.Game.Quests.empty()

  defp daily(%{"date" => date, "tasks" => tasks}) do
    %{
      date: date,
      tasks:
        Enum.map(tasks, fn t ->
          %{
            kind: t["kind"],
            target: t["target"],
            zone: t["zone"],
            count: t["count"],
            progress: t["progress"],
            claimed: t["claimed"],
            name: t["name"],
            reward: %{gold: t["reward"]["gold"], xp: t["reward"]["xp"]}
          }
        end)
    }
  end

  defp daily(_), do: nil

  # Trong tháp thì giữ vị trí (tầng tháp không có trong priv/maps nên valid_pos không biết).
  defp pos(%Character{map_id: "tower", tower: %{}, x: x, y: y}), do: %{map: "tower", x: x, y: y}

  defp pos(%Character{map_id: "tower"}), do: HacLong.World.Maps.home_spawn()

  defp pos(c), do: World.valid_pos(%{map: c.map_id, x: c.x, y: c.y})

  defp tower(%{"floor" => floor} = t) do
    %{
      floor: floor,
      tiles: t["tiles"],
      stairs: t["stairs"],
      exit: t["exit"],
      monsters:
        Enum.map(t["monsters"], fn m ->
          %{
            id: m["id"],
            kind: m["kind"],
            name: m["name"],
            level: m["level"],
            x: m["x"],
            y: m["y"],
            elite: m["elite"]
          }
        end)
    }
  end

  defp tower(_), do: nil

  # Tên các trường có trong trận đấu (trận, quái, nhật ký, phần thưởng).
  @battle_keys Map.new(
                 ~w(zone monster turn skillCd cds effects player turns power on_hit effect chance
                    log over result reward encounter map mid world world_boss tower elite
                    id name level boss final special maxHp atk def crit dodge xp gold hp
                    every mult text kind items levels gear night shared joined pvp look hair weapon armor
                    shield pet deaths)a,
                 &{Atom.to_string(&1), &1}
               )

  defp atomize(m) when is_map(m),
    do: Map.new(m, fn {k, v} -> {Map.fetch!(@battle_keys, k), atomize(v)} end)

  defp atomize(l) when is_list(l), do: Enum.map(l, &atomize/1)
  defp atomize(v), do: v
end

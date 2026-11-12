defmodule HacLongWeb.PageController do
  use HacLongWeb, :controller

  alias HacLong.Game.{Achievements, Data, Engine}
  alias HacLong.World.Maps

  @doc """
  Trả về `priv/static/index.html` kèm dữ liệu game (`window.GAME_DATA`) để giao diện
  vẽ danh sách vùng đất, cửa hàng, lớp nhân vật... Dữ liệu chỉ có một nguồn là
  thư mục `priv/game_data/` trên server (`HacLong.Game.Data`).
  """
  def index(conn, _params) do
    data = Jason.encode!(client_data(), escape: :html_safe)
    version = HacLongWeb.ClientVersion.current()

    html =
      Application.app_dir(:hac_long, "priv/static/index.html")
      |> File.read!()
      |> String.replace(
        "<!--GAME_DATA-->",
        "<script>window.GAME_DATA = #{data}; window.CLIENT_VERSION = \"#{version}\"; window.HAC_FIRST = #{hac_first()};</script>"
      )
      # js/…, css/… kèm `?v=phiên_bản`: deploy bản mới thì trình duyệt tải file mới, không dùng bản
      # cũ còn trong cache (Plug.Static không đặt max-age nên trình duyệt có thể tự giữ file khá lâu)
      |> String.replace(~r/(src|href)="((?:js|css)\/[^"?]+)"/, "\\1=\"\\2?v=#{version}\"")

    # không cache trang chủ: sau khi cập nhật server, tải lại là có ngay mã phiên bản mới
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  # người đầu tiên của server thuần phục Hắc Long (màn đăng nhập ghi tên, DECISIONS "… Hắc Long"); lỗi database thì null
  defp hac_first do
    HacLong.Game.DragonEgg.pets()
    |> Enum.flat_map(&HacLong.RarePets.list/1)
    |> Enum.min_by(& &1.at, DateTime, fn -> nil end)
    |> then(&Jason.encode!(&1 && &1.name, escape: :html_safe))
  rescue
    _ -> "null"
  end

  defp item_icons(file \\ "item_icons.json") do
    path = Application.app_dir(:hac_long, "priv/static/assets/" <> file)

    with {:ok, bin} <- File.read(path), {:ok, map} <- Jason.decode(bin) do
      map
    else
      _ -> %{}
    end
  end

  defp client_data do
    %{
      CLASSES: Data.classes(),
      ZONES: Data.zones(),
      # quái bản đồ phụ (sổ tay quái vật)
      SIDE_MONSTERS: Data.side_monsters(),
      ITEMS:
        Map.new(Data.items(), fn {id, it} ->
          {id, Map.merge(it, %{id: id, sell: Engine.sell_price(id)})}
        end),
      # bộ hình đồ đổi theo cấp +N (`mix hac_long.icons`), đọc mỗi lần tải trang nên không cần build lại
      ITEM_ICONS: item_icons(),
      # Phase 7 (B-33): bộ hình đồ Pixel CC0 (scripts/pixel_icons.py), có trong git
      PIXEL_ICONS: item_icons("pixel_icons.json"),
      SHOP: Data.shop(),
      RECIPES: Data.recipes(),
      QUESTS: Data.quests(),
      PETS: Data.pets(),
      ACHIEVEMENTS: Achievements.client_data(),
      UPGRADE: Data.upgrade(),
      CHAOS: Data.chaos(),
      RULES: %{
        maxLevel: Engine.max_level(),
        gearBag: HacLong.Game.Gear.max_bag(),
        # Phase 15e: dòng phụ cánh theo bậc (số để ghi trong ô chọn ở tab Quản trị)
        wingOptions: Data.rules().wing_options.by_tier,
        # câu hỏi bảo mật lúc đăng ký / quên mật khẩu (DECISIONS "Câu hỏi bảo mật")
        account: Map.take(Data.rules().account, [:security_questions, :answer_min, :answer_max]),
        # Phase 15c: thưởng đủ bộ giáp (số để hiện chữ)
        setBonus: Map.take(Data.rules().set_bonus, [:min_tier, :def_pct, :atk_pct, :hp_per_tier]),
        # Phase 15g: chữ đồ Bộ Thần trong tooltip
        ancient: Map.take(Data.rules().ancient, [:piece_def_pct, :bonus]),
        # B-16: các dòng Excellent (ô chọn dòng khi quản trị tặng đồ)
        excOptions: Data.rules().excellent.options,
        # Phase 15d: chữ dòng May mắn / Kỹ năng trong tooltip
        luckSkill:
          Map.take(Data.rules().luck_skill, [
            :luck_crit,
            :luck_upgrade,
            :luck_max_rate,
            :skill_dmg
          ]),
        rebirthPoints: Engine.rebirth_points(),
        rebirthHpPct: Engine.rebirth_hp_mult(1) - 1,
        rebirthXpPct: Data.rules().character.rebirth_xp_pct,
        maxRebirths: Engine.max_rebirths(),
        endlessPoints: Data.rules().character.endless_points,
        botStuckMin: Data.rules().bots.play.stuck_min,
        # Động Bí Ẩn: tỉ lệ đêm mở (ghi trong thẻ quản trị)
        secret: secret_info(),
        # Quản trị → Dựng nhân vật tối đa (docs/ADMIN_GUIDE.md §6)
        adminMaxBuild: Data.rules().admin_max_build,
        # ⚡ Đánh nhanh theo combo (DECISIONS "Đánh nhanh theo combo")
        quick: Map.take(Data.rules().quick, [:max_steps, :tick_ms]),
        # kỹ năng quái theo hệ, kháng hệ nhẫn / dây chuyền (DECISIONS "Quái dùng kỹ năng theo hệ")
        monsterSkills:
          Map.drop(Data.rules().monster_skills, [:_doc, :sourceType, :version, :verified]),
        guildCost: HacLong.Guilds.create_cost(),
        guildMinDonate: HacLong.Guilds.min_donate(),
        tameKills: HacLong.Game.Pets.tame_kills(),
        petMaxLevel: HacLong.Game.Pets.max_level(),
        # nhóm thú cưng (DECISIONS "Thú cưng 3 nhóm, chỉ cộng chỉ số")
        petGroups: Map.new(~w(war guard luck all), &{&1, HacLong.Game.Pets.group_name(&1)}),
        # Long Vương (DECISIONS "Long Vương"): cơ hội mỗi lần thả câu ở Biển Long Vương, mồi gấp bao nhiêu
        school:
          Map.take(HacLong.Game.Data.rules().fishing.school, [
            :every,
            :stay,
            :gold_chance,
            :long_khi
          ]),
        dragon:
          Map.take(HacLong.Game.Fishing.dragon(), [
            :pet,
            :chance,
            :bait,
            :bait_mult,
            :every,
            :stay,
            :long_khi_max,
            :long_khi_div
          ]),
        # Đồi Sáo Diều, Chim Lạc, Hắc Long (DECISIONS cùng tên)
        sky:
          HacLong.Game.Kite.rules()
          |> Map.drop([:_doc, :sourceType, :version, :verified])
          |> Map.update!(:egg, &Map.delete(&1, :_doc)),
        craftLevels: HacLong.Game.Crafting.levels(),
        smithCosts: HacLong.Game.Crafting.smith_costs(),
        friendsMax: HacLong.Friends.max(),
        upgradeBonusPct: Data.rules().upgrade.bonus_pct,
        life: Data.rules().upgrade.life,
        warMinutes: Data.rules().guild_war.minutes,
        warFund: Data.rules().guild_war.win_fund,
        warGold: Data.rules().guild_war.win_gold,
        # đồ sát: số giây mỗi lượt, cấp tối thiểu, bản đồ an toàn
        slay: %{
          turnS: Data.rules().slay.turn_s,
          minLevel: Data.rules().slay.min_level,
          safe: Data.rules().slay.safe_maps,
          redMult: Data.rules().slay.red_gold_mult,
          reachByWing: Data.rules().slay.reach_by_wing
        },
        # Công Thành Chiến: Vương Miện (quái bản đồ sự kiện) để bản đồ vẽ quầng sáng, mũi tên mép khung
        castleSiege: %{
          crownKind: Data.rules().castle_siege.crown.kind,
          crownAt: Data.rules().castle_siege.crown.at
        },
        # % sát thương / hấp thụ cánh cộng thêm theo [bậc][cấp ép 0..11] (Engine.wing_up/3), trần hấp thụ
        wingUp:
          Map.new([:dmg, :absorb], fn k ->
            {k,
             for(t <- 1..3, do: for(l <- 0..Engine.max_upgrade(), do: Engine.wing_up(k, t, l)))}
          end),
        wingAbsorbMax: Data.rules().wing_upgrade.absorb.max,
        # tự đánh: lựa chọn và mặc định cho bảng cài đặt
        auto:
          Map.take(Data.rules().auto, [
            :hp_pct,
            :mp_pct,
            :range_options,
            :range_default,
            :skills,
            :keep,
            :keep_default,
            :keep_opt_min
          ]),
        # giải thích chỉ số ở tab Nhân vật (bấm vào từng dòng): số lấy từ RULES, client không giữ số riêng
        combatHelp: %{
          crit: Data.rules().combat.crit,
          critMult: Data.rules().combat.crit_mult,
          dodge: Map.delete(Data.rules().combat.dodge, :_doc_max_total),
          spread: Data.rules().combat.damage_spread,
          softFloor: Data.rules().combat.soft_floor,
          hit: Data.rules().combat.hit,
          monsterCrit: Data.rules().monster.crit,
          monsterCritMult: Data.rules().combat.monster_crit_mult,
          slayFirst: Data.rules().slay.first_strike_mult,
          arenaFirst: Data.rules().arena[:first_strike_mult] || 1,
          pvp:
            Map.take(Data.rules().pvp, [
              :dmg_mult,
              :crit_rate_mult,
              :dodge_mult,
              :stun_mult,
              :stun_immune,
              :potion_mult,
              :potion_cd,
              :potion_max,
              :potion_cap_pct,
              :mana_cd,
              :mana_max,
              :mana_cap_pct,
              :heal_mult
            ])
        },
        # Phase 12: MP kỹ năng theo cấp, giá bình theo cấp
        skillMpPerLevel: Data.rules().combat.skill_mp_per_level,
        # Phase 3 (B-29): nguyên tố, kỹ năng tháp
        elements: Map.drop(Data.rules().elements, [:_doc, :sourceType, :version, :verified]),
        towerSkills: Map.take(Data.rules().tower_skills, [:loadout, :stun_boss_resist, :mp_mult]),
        # cầm 2 vũ khí 1 tay (B-42): lớp được cầm, hệ số công tay trái
        dualWield: Map.take(Data.rules().dual_wield, [:classes, :mult, :staff_pair_only]),
        # tác dụng kỹ năng lớp (mô tả kỹ năng theo cấp thông thạo ở client)
        skillEffects: Data.rules().skill_effects,
        # thông thạo kỹ năng (Menu → Kỹ năng): cấp tối đa, vật phẩm đột phá, MP cấp thấp
        skillMastery:
          Map.take(Data.rules().skill_mastery, [
            :max,
            :item,
            :alt_item,
            :mp_low,
            :mult_min,
            :level_gap,
            :effect_low
          ]),
        potionPricePerLevel: Data.rules().shop.potion_price_per_level,
        # Phase 15a: giá dịch chuyển bằng bảng chọn bản đồ
        travel: %{
          base: Data.rules().travel.base,
          perLevel: Data.rules().travel.per_level,
          free: Data.rules().travel.free
        },
        smithEpicPerLevel: Data.rules().crafting.smith_epic_per_level,
        smithRare: Data.rules().crafting.smith_rare,
        tameBonus: Data.rules().pets.tame_bonus,
        tamePrice: Data.rules().pets.tame_price,
        tamePricePerLevel: Data.rules().pets.tame_price_per_level,
        petXpCoef: Data.rules().pets.xp_coef,
        # chỉ số thú cưng cộng thêm mỗi cấp (DECISIONS "Thú cưng 3 nhóm, chỉ cộng chỉ số")
        petPerLevel: Data.rules().pets.bonus_per_level,
        petFeedXp: Data.rules().pets.feed_xp
      },
      WORLD: Maps.client_data(),
      # Phase 14: Thư viện (bản đồ, quái, vật phẩm)
      LIBRARY: HacLong.Library.get()
    }
  end

  # Động Bí Ẩn: tỉ lệ đêm mở (thẻ quản trị) và khoảng cấp quái (bản đồ bị ẩn khỏi Thư viện nên client không tự tính được)
  defp secret_info do
    r = HacLong.World.Secret.rules()

    lv =
      for sp <- (HacLong.World.Maps.get(r.map) || %{spawns: []}).spawns,
          spec = Data.side_monster(sp.monster),
          do: spec.level

    %{
      open_chance: r.open_chance,
      min: Enum.min(lv, fn -> nil end),
      max: Enum.max(lv, fn -> nil end)
    }
  end
end

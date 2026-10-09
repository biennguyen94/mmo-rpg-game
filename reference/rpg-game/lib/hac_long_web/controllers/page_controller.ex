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
        "<script>window.GAME_DATA = #{data}; window.CLIENT_VERSION = \"#{version}\";</script>"
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

  defp item_icons do
    path = Application.app_dir(:hac_long, "priv/static/assets/item_icons.json")

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
      ITEMS:
        Map.new(Data.items(), fn {id, it} ->
          {id, Map.merge(it, %{id: id, sell: Engine.sell_price(id)})}
        end),
      # bộ hình đồ đổi theo cấp +N (`mix hac_long.icons`), đọc mỗi lần tải trang nên không cần build lại
      ITEM_ICONS: item_icons(),
      SHOP: Data.shop(),
      RECIPES: Data.recipes(),
      QUESTS: Data.quests(),
      PETS: Data.pets(),
      FURNITURE: Data.furniture(),
      ACHIEVEMENTS: Achievements.client_data(),
      UPGRADE: Data.upgrade(),
      CHAOS: Data.chaos(),
      RULES: %{
        maxLevel: Engine.max_level(),
        gearBag: HacLong.Game.Gear.max_bag(),
        rebirthPoints: Engine.rebirth_points(),
        maxRebirths: Engine.max_rebirths(),
        guildCost: HacLong.Guilds.create_cost(),
        guildMinDonate: HacLong.Guilds.min_donate(),
        tameKills: HacLong.Game.Pets.tame_kills(),
        petMaxLevel: HacLong.Game.Pets.max_level(),
        petSkillLevel: HacLong.Game.Pets.skill_level(),
        craftLevels: HacLong.Game.Crafting.levels(),
        smithCosts: HacLong.Game.Crafting.smith_costs(),
        friendsMax: HacLong.Friends.max(),
        upgradeBonusPct: Data.rules().upgrade.bonus_pct,
        life: Data.rules().upgrade.life,
        pkMin: Data.rules().pk.min,
        warMinutes: Data.rules().guild_war.minutes,
        warFund: Data.rules().guild_war.win_fund,
        warGold: Data.rules().guild_war.win_gold,
        pkMax: Data.rules().pk.max,
        pkInvite: Data.rules().pk.invite_s,
        wingPerLevel: Data.rules().combat.wing_per_level,
        # Phase 12: MP kỹ năng theo cấp, giá bình theo cấp
        skillMpPerLevel: Data.rules().combat.skill_mp_per_level,
        potionPricePerLevel: Data.rules().shop.potion_price_per_level,
        smithEpicPerLevel: Data.rules().crafting.smith_epic_per_level,
        smithRare: Data.rules().crafting.smith_rare,
        tameBonus: Data.rules().pets.tame_bonus,
        tamePrice: Data.rules().pets.tame_price,
        tamePricePerLevel: Data.rules().pets.tame_price_per_level,
        petXpCoef: Data.rules().pets.xp_coef
      },
      WORLD: Maps.client_data()
    }
  end
end

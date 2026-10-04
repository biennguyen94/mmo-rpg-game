defmodule HacLongWeb.PageController do
  use HacLongWeb, :controller

  alias HacLong.Game.{Achievements, Data, Engine}
  alias HacLong.World.Maps

  @doc """
  Trả về `priv/static/index.html` kèm dữ liệu game (`window.GAME_DATA`) để giao diện
  vẽ danh sách vùng đất, cửa hàng, lớp nhân vật... Dữ liệu chỉ có một nguồn là
  `priv/game_data.json` trên server.
  """
  def index(conn, _params) do
    data = Jason.encode!(client_data(), escape: :html_safe)

    html =
      Application.app_dir(:hac_long, "priv/static/index.html")
      |> File.read!()
      |> String.replace(
        "<!--GAME_DATA-->",
        "<script>window.GAME_DATA = #{data}; window.CLIENT_VERSION = \"#{HacLongWeb.ClientVersion.current()}\";</script>"
      )

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
        friendsMax: HacLong.Friends.max()
      },
      WORLD: Maps.client_data()
    }
  end
end

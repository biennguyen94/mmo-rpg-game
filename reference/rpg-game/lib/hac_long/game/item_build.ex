defmodule HacLong.Game.ItemBuild do
  @moduledoc """
  Phase 15b: dựng danh sách đồ Hắc Long từ nháp Item.txt (`HacLong.Game.ItemTxt.to_item/1`) theo
  bảng chọn `ITEM_PICK` (`priv/game_data/item_pick.json`). Hàm thuần; giải thích từng khóa ở
  `docs/ITEMS_PHASE15B.md`.

  Nguyên tắc: **Item.txt cho tên gốc, hình (`ref`), tỉ lệ đòn thấp ~ cao, tỉ lệ phòng thủ giữa các
  món trong bộ, yêu cầu chỉ số; độ mạnh theo đường cong của Hắc Long** (bậc → cấp, công / thủ / giá
  trong `ITEM_PICK`), để đổi đồ không làm lệch cân bằng.

  - Vũ khí `mode: "raw"` (mặc định `stats.weapon_mode`): công = trung bình `DmgMin ~ DmgMax` của file
    (đã chọn món sao cho khớp đường cong); `mode: "staff"`: công = `stats.staff_atk[bậc]`, khoảng
    thấp ~ cao theo tỉ lệ của file (gậy MU có sát thương vật lý rất thấp, sức mạnh nằm ở phép).
  - Bộ giáp (mũ, giáp, quần, găng, giày cùng số thứ tự trong nhóm 7–11): tổng thủ của bộ =
    `stats.set_def[bậc] × stats.set_def_mult`, chia cho từng món theo tỉ lệ `Def` trong file (tối thiểu 1).
  - Khiên: thủ = `stats.shield_def[bậc]`.
  - Yêu cầu chỉ số = số trong file × `req_mult` (làm tròn); vũ khí / bộ giáp bậc trong `no_req_tiers`
    (đồ khởi đầu) không đòi chỉ số.
  - Giá = `prices.<loại>[bậc]`, món trong bộ nhân `prices.piece_weight`.
  - Lớp: các lớp có món đó trong danh sách chọn (`"mg": "dk"` = dùng chung danh sách của DK);
    lớp trong `no_helm` không có mũ.
  """

  @pieces [{"helm", 7}, {"armor", 8}, {"pants", 9}, {"gloves", 10}, {"boots", 11}]

  @doc """
  `drafts`: `%{"nhóm/số" => nháp}` (khóa chuỗi, như `items_from_txt.json`); `pick`: `ITEM_PICK` (khóa chuỗi).
  Trả `{:ok, đồ, cảnh_báo}`; mỗi món là map khóa chuỗi, sắp theo loại rồi bậc.
  """
  def build(drafts, pick) do
    {weapons, w1} = weapons(drafts, pick)
    {shields, w2} = shields(drafts, pick)
    {sets, w3} = sets(drafts, pick)
    {:ok, weapons ++ shields ++ sets, w1 ++ w2 ++ w3}
  end

  # ---------- vũ khí ----------
  defp weapons(drafts, pick) do
    lists = resolve(pick["weapons"])

    rows =
      for {cls, list} <- lists, {entry, tier} <- Enum.with_index(list, 1), do: {entry, tier, cls}

    rows
    |> Enum.group_by(fn {e, tier, _} -> {e["ref"], tier} end)
    |> Enum.map(fn {{ref, tier}, grp} ->
      {e, _, _} = hd(grp)
      classes = grp |> Enum.map(&elem(&1, 2)) |> Enum.uniq() |> Enum.sort()

      with_draft(drafts, ref, fn d ->
        {mn, mx} = {d["atkMin"] || 0, d["atkMax"] || 0}
        mode = e["mode"] || get_in(pick, ["stats", "weapon_mode"]) || "raw"

        {atk, lo, hi} =
          case mode do
            "staff" ->
              atk = at(pick, ["stats", "staff_atk"], tier)
              avg = max((mn + mx) / 2, 1)
              {atk, max(round(atk * mn / avg), 1), max(round(atk * mx / avg), 1)}

            _ ->
              {round((mn + mx) / 2), mn, mx}
          end

        base(d, e, pick, "weapon", tier, classes)
        |> Map.merge(%{"atk" => atk, "atkMin" => lo, "atkMax" => hi})
        |> Map.put("price", at(pick, ["prices", "weapon"], tier))
      end)
    end)
    |> split()
  end

  # ---------- khiên ----------
  defp shields(drafts, pick) do
    classes = pick["sets"] |> resolve() |> Map.keys() |> Enum.sort()

    (pick["shields"] || [])
    |> Enum.with_index(1)
    |> Enum.map(fn {e, tier} ->
      with_draft(drafts, e["ref"], fn d ->
        base(d, e, pick, "shield", tier, classes)
        |> Map.put("def", at(pick, ["stats", "shield_def"], tier))
        |> Map.put("price", at(pick, ["prices", "shield"], tier))
      end)
    end)
    |> split()
  end

  # ---------- bộ giáp ----------
  defp sets(drafts, pick) do
    lists = resolve(pick["sets"])
    no_helm = pick["no_helm"] || []
    names = pick["pieces"] || %{}
    mult = get_in(pick, ["stats", "set_def_mult"]) || 1.0

    rows =
      for {cls, list} <- lists, {entry, tier} <- Enum.with_index(list, 1), do: {entry, tier, cls}

    rows
    |> Enum.group_by(fn {e, tier, _} -> {e["index"], tier} end)
    |> Enum.flat_map(fn {{index, tier}, grp} ->
      {e, _, _} = hd(grp)
      owners = grp |> Enum.map(&elem(&1, 2)) |> Enum.uniq() |> Enum.sort()
      parts = for {slot, g} <- @pieces, d = drafts["#{g}/#{index}"], do: {slot, d}
      total = parts |> Enum.map(fn {_, d} -> d["def"] || 0 end) |> Enum.sum() |> max(1)
      budget = at(pick, ["stats", "set_def"], tier) * mult

      missing =
        for {slot, g} <- @pieces,
            drafts["#{g}/#{index}"] == nil,
            do: {:error, "bộ #{e["name"]}: thiếu #{slot} #{g}/#{index} trong Item.txt"}

      made =
        for {slot, d} <- parts do
          classes = if slot == "helm", do: owners -- no_helm, else: owners
          name = "#{names[slot] || slot} #{e["name"]}"
          weight = get_in(pick, ["prices", "piece_weight", slot]) || 1.0

          {:ok,
           base(d, %{"name" => name}, pick, slot, tier, classes)
           |> Map.put("level", at(pick, ["levels", "set"], tier))
           |> Map.put("set", e["name"])
           |> Map.put("def", max(round(budget * (d["def"] || 0) / total), 1))
           |> Map.put("price", round(at(pick, ["prices", "set"], tier) * weight))}
        end

      made ++ missing
    end)
    |> split()
  end

  # ---------- chung ----------
  defp base(d, e, pick, slot, tier, classes) do
    levels = pick["levels"] || %{}
    key = if slot in ~w(weapon shield), do: slot, else: "set"
    mult = pick["req_mult"] || 1.0

    %{
      "id" => d["id"],
      "ref" => d["ref"],
      "name" => e["name"],
      "mu_name" => d["name"],
      "slot" => slot,
      "tier" => tier,
      "level" => Enum.at(levels[key] || [], tier - 1, tier),
      "classes" => classes,
      "req" => req(d, pick, slot, tier, mult),
      "sourceType" => pick["sourceType"],
      "version" => pick["version"],
      "verified" => pick["verified"]
    }
  end

  # đồ khởi đầu (bậc trong `no_req_tiers`, chỉ vũ khí và bộ giáp) mặc được ngay khi tạo nhân vật
  defp req(d, pick, slot, tier, mult) do
    if slot != "shield" and tier in (pick["no_req_tiers"] || []),
      do: %{},
      else: Map.new(d["req"] || %{}, fn {k, v} -> {k, round(v * mult)} end)
  end

  defp with_draft(drafts, ref, f) do
    case drafts[ref] do
      nil -> {:error, "không có #{ref} trong Item.txt"}
      d -> {:ok, f.(d)}
    end
  end

  defp at(pick, path, tier), do: Enum.at(get_in(pick, path) || [], tier - 1, 0)

  # `"mg": "dk"` → dùng chung danh sách của lớp khác
  defp resolve(nil), do: %{}

  defp resolve(m),
    do: Map.new(m, fn {cls, v} -> {cls, if(is_binary(v), do: m[v] || [], else: v)} end)

  @order %{
    "weapon" => 0,
    "shield" => 1,
    "helm" => 2,
    "armor" => 3,
    "pants" => 4,
    "gloves" => 5,
    "boots" => 6
  }

  defp split(results) do
    {oks, errs} = Enum.split_with(results, &match?({:ok, _}, &1))

    items =
      oks
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort_by(&{@order[&1["slot"]], &1["tier"], &1["classes"], &1["id"]})

    {items, Enum.map(errs, &elem(&1, 1))}
  end
end

defmodule Mu.Game.Quests do
  @moduledoc """
  Luật quest (P6-M2, P6-2) — hàm thuần, như `Engine`. Học ý từ `HacLong.Game.Quests` của repo
  nền (đếm kill từ lúc nhận, collect nộp khi trả); dữ liệu và trạng thái theo dự án.

  Trạng thái của một nhân vật (`states`): `%{quest_id => %{state: "ACTIVE" | "DONE", progress}}`,
  `progress` = `%{"<vị trí mục tiêu>" => số đã hạ}` (chỉ mục tiêu `kill`; `collect` đếm trong túi
  lúc xem / lúc trả; `level` so với cấp hiện tại).
  """

  alias Mu.Game.{Config, Data, Inventory}

  @doc "Quest nhận được: chưa từng nhận, đủ cấp (theo thứ tự `quests.json`)."
  def available(level, states) do
    Enum.filter(Data.quests(), &(not Map.has_key?(states, &1["id"]) and level >= &1["minLevel"]))
  end

  @doc """
  Kiểm nhận quest: `:ok` hoặc `{:error, code}` — không có quest → `INVALID_TARGET`; đã nhận / đã
  xong / đủ `quest.maxActive` quest đang làm → `FORBIDDEN`; chưa đủ cấp → `REQUIREMENT_NOT_MET`.
  """
  def can_accept(id, level, states) do
    q = Data.quest(id)

    cond do
      q == nil -> {:error, "INVALID_TARGET"}
      Map.has_key?(states, id) -> {:error, "FORBIDDEN"}
      active_count(states) >= Config.get(["quest", "maxActive"]) -> {:error, "FORBIDDEN"}
      level < q["minLevel"] -> {:error, "REQUIREMENT_NOT_MET"}
      true -> :ok
    end
  end

  def active_count(states), do: Enum.count(states, fn {_, st} -> st.state == "ACTIVE" end)

  @doc """
  Hạ một con `monster_id`: `[{quest_id, progress mới}]` của các quest đang làm có mục tiêu `kill`
  quái này mà chưa đủ (đủ rồi thì không đếm thêm).
  """
  def on_kill(states, monster_id) do
    for {id, %{state: "ACTIVE", progress: pr}} <- states,
        q = Data.quest(id),
        q != nil,
        {pr2, changed?} = bump(q, pr, monster_id),
        changed?,
        do: {id, pr2}
  end

  defp bump(q, pr, monster_id) do
    q["objectives"]
    |> Enum.with_index()
    |> Enum.reduce({pr, false}, fn
      {%{"type" => "kill", "monsterId" => ^monster_id, "count" => n}, i}, {pr, changed?} ->
        k = Integer.to_string(i)
        have = Map.get(pr, k, 0)
        if have < n, do: {Map.put(pr, k, have + 1), true}, else: {pr, changed?}

      _, acc ->
        acc
    end)
  end

  @doc "Tiến độ từng mục tiêu: `[%{type, target, have, need}]` (`have` không vượt `need`)."
  def objectives(q, progress, level, items) do
    bag = Inventory.inventory(items)

    q["objectives"]
    |> Enum.with_index()
    |> Enum.map(fn
      {%{"type" => "kill", "monsterId" => m, "count" => n}, i} ->
        %{
          type: "kill",
          target: m,
          name: target_name("kill", m),
          have: min(Map.get(progress, Integer.to_string(i), 0), n),
          need: n
        }

      {%{"type" => "collect", "templateId" => t, "count" => n}, _} ->
        have = bag |> Enum.filter(&(&1.template_id == t)) |> Enum.map(& &1.quantity) |> Enum.sum()

        %{
          type: "collect",
          target: t,
          name: target_name("collect", t),
          have: min(have, n),
          need: n
        }

      {%{"type" => "level", "min" => n}, _} ->
        %{type: "level", target: nil, name: nil, have: min(level, n), need: n}
    end)
  end

  def complete?(q, progress, level, items),
    do: Enum.all?(objectives(q, progress, level, items), &(&1.have >= &1.need))

  @doc "Vật phẩm phải nộp khi trả: `[{template_id, số}]`."
  def collect_needs(q) do
    for %{"type" => "collect", "templateId" => t, "count" => n} <- q["objectives"], do: {t, n}
  end

  @doc "Event `quests` (P6-8): `active` (kèm tiến độ, đủ chưa), `done` (id), `available`."
  def view(states, level, items) do
    active =
      for q <- Data.quests(), %{state: "ACTIVE", progress: pr} <- [states[q["id"]]] do
        q
        |> brief()
        |> Map.merge(%{
          objectives: objectives(q, pr, level, items),
          complete: complete?(q, pr, level, items)
        })
      end

    %{
      active: active,
      done: for(q <- Data.quests(), match?(%{state: "DONE"}, states[q["id"]]), do: q["id"]),
      available: Enum.map(available(level, states), &brief/1),
      maxActive: Config.get(["quest", "maxActive"])
    }
  end

  defp brief(q) do
    %{
      id: q["id"],
      name: q["name"],
      description: q["description"],
      minLevel: q["minLevel"],
      goals:
        Enum.map(q["objectives"], fn o ->
          target = o["monsterId"] || o["templateId"]

          %{
            type: o["type"],
            target: target,
            name: target_name(o["type"], target),
            need: o["count"] || o["min"]
          }
        end),
      rewards: q["rewards"]
    }
  end

  # tên hiển thị của quái / item mục tiêu (client không có danh sách quái)
  defp target_name("kill", m), do: Data.monster(m)["name"]
  defp target_name("collect", t), do: Data.item(t)["name"]
  defp target_name(_, _), do: nil
end

defmodule HacLong.Mailbox do
  @moduledoc """
  Hộp thư: thư hệ thống gửi cho người chơi, có thể kèm quà (vàng, kinh nghiệm, đồ).

  - Dùng để báo thưởng nhận lúc vắng mặt (trùm thế giới) và cho quản trị viên tặng quà.
  - Mở thư là nhận quà luôn (`claim/3`); thư không có quà thì mở là đánh dấu đã đọc.
  - Nhận quà trong một transaction cùng lần ghi nhân vật: đánh dấu thư đã nhận chỉ thành
    công một lần (`claimed_at IS NULL`), nên bấm hai lần hay hai tab cùng bấm cũng không
    nhận đôi.
  - Gửi thư thì báo số thư chưa mở qua PubSub (`{:mail, số}` trên kênh của người chơi).
  - Giữ tối đa `RULES.mail.keep` thư mới nhất mỗi người; thư cũ đã mở bị xóa. Thư quá
    `RULES.mail.expire_days` ngày bị xóa, **trừ thư còn quà chưa nhận** (Phase 5, H12, câu 5-I).
  - `claim_all/3` nhận quà mọi thư chưa mở trong một transaction; `delete_read/1` xóa thư đã mở.
  """
  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Game.{Character, Data, Engine, Gear}

  @rules Data.rules().mail
  @keep @rules.keep

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc """
  Gửi thư. `attrs`: `subject` (bắt buộc), `body`, `gold`, `xp`, `items` (`%{id => số}`).

  Đồ riêng từng món (Phase 11, V10) ghi trong `items` với khóa `"gear:<mẫu>:<độ hiếm>:<+N>"`:
  độ hiếm 0 là đồ thường (`Gear.plain/1`), 1..3 là đồ hiếm chỉ số theo cấp người nhận. Mở thư thì
  tạo từng món vào túi đồ hiếm; túi không đủ chỗ thì không mở được (giữ thư).
  """
  def send(user_id, attrs) do
    with {:ok, row} <- row(attrs) do
      Repo.insert_all("mails", [Map.put(row, :user_id, user_id)])
      notify(user_id)
      :ok
    end
  end

  @doc "Gửi cho mọi người đã có nhân vật. Trả về số thư đã gửi."
  def send_all(attrs) do
    with {:ok, row} <- row(attrs) do
      ids = Repo.all(from c in Character, select: c.user_id)
      rows = Enum.map(ids, &Map.put(row, :user_id, &1))
      rows |> Enum.chunk_every(1000) |> Enum.each(&Repo.insert_all("mails", &1))
      Enum.each(ids, &notify/1)
      {:ok, length(ids)}
    end
  end

  defp row(attrs) do
    a = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    subject = a["subject"] |> to_string() |> String.trim() |> String.slice(0, 80)
    gold = a["gold"] || 0
    xp = a["xp"] || 0
    items = a["items"] || %{}

    cond do
      subject == "" ->
        {:error, "Thư cần có tiêu đề."}

      not (is_integer(gold) and gold >= 0 and is_integer(xp) and xp >= 0) ->
        {:error, "Vàng và kinh nghiệm phải là số không âm."}

      not (is_map(items) and
               Enum.all?(items, fn {id, n} -> valid_item?(id) && is_integer(n) && n in 1..100 end)) ->
        {:error, "Vật phẩm không hợp lệ."}

      true ->
        {:ok,
         %{
           subject: subject,
           body: a["body"] |> to_string() |> String.slice(0, 1000),
           gold: gold,
           xp: xp,
           items: items,
           inserted_at: now()
         }}
    end
  end

  @doc "Số thư chưa mở."
  def unread(user_id) do
    Repo.aggregate(
      from(m in "mails", where: m.user_id == ^user_id and is_nil(m.claimed_at)),
      :count
    )
  end

  @doc "Các thư gần nhất, mới trước."
  def list(user_id) do
    cleanup(user_id)

    Repo.all(
      from m in "mails",
        where: m.user_id == ^user_id,
        order_by: [desc: m.id],
        limit: @keep,
        select: %{
          id: m.id,
          subject: m.subject,
          body: m.body,
          gold: m.gold,
          xp: m.xp,
          items: m.items,
          claimed: not is_nil(m.claimed_at),
          at: m.inserted_at
        }
    )
  end

  # thư hết hạn (trừ thư còn quà chưa nhận); thư đã mở nằm ngoài @keep thư mới nhất thì xóa
  @doc false
  def cleanup(user_id, now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@rules.expire_days * 86_400, :second)

    Repo.delete_all(
      from m in "mails",
        where:
          m.user_id == ^user_id and m.inserted_at < ^cutoff and
            (not is_nil(m.claimed_at) or
               (m.gold == 0 and m.xp == 0 and m.items == ^%{}))
    )

    keep_newest(user_id)
  end

  defp keep_newest(user_id) do
    case Repo.one(
           from m in "mails",
             where: m.user_id == ^user_id,
             order_by: [desc: m.id],
             offset: ^(@keep - 1),
             limit: 1,
             select: m.id
         ) do
      nil ->
        :ok

      oldest ->
        Repo.delete_all(
          from m in "mails",
            where: m.user_id == ^user_id and m.id < ^oldest and not is_nil(m.claimed_at)
        )
    end
  end

  @doc """
  Mở thư `id` của `user_id` và trao quà cho nhân vật `p`. `save` được gọi với nhân vật mới
  trong cùng transaction (để ghi database). Trả về `{:ok, thông_báo, nhân_vật}` hoặc
  `{:error, lý_do}`.
  """
  def claim(user_id, id, p, save) when is_integer(id) do
    Repo.transaction(fn ->
      {n, rows} =
        Repo.update_all(
          from(m in "mails",
            where: m.id == ^id and m.user_id == ^user_id and is_nil(m.claimed_at),
            select: %{subject: m.subject, gold: m.gold, xp: m.xp, items: m.items}
          ),
          set: [claimed_at: now()]
        )

      if n == 0, do: Repo.rollback("Thư đã mở rồi.")
      mail = hd(rows)
      p = give(p, mail)
      save.(p)
      {describe(mail), p}
    end)
    |> case do
      {:ok, {msg, p}} ->
        notify(user_id)
        {:ok, msg, p}

      {:error, msg} ->
        {:error, msg}
    end
  end

  def claim(_user_id, _id, _p, _save), do: {:error, "Thư không hợp lệ."}

  @doc "Nhận quà mọi thư chưa mở (một transaction, như `claim/4`)."
  def claim_all(user_id, p, save) do
    Repo.transaction(fn ->
      {n, rows} =
        Repo.update_all(
          from(m in "mails",
            where: m.user_id == ^user_id and is_nil(m.claimed_at),
            select: %{subject: m.subject, gold: m.gold, xp: m.xp, items: m.items}
          ),
          set: [claimed_at: now()]
        )

      if n == 0, do: Repo.rollback("Không còn thư chưa mở.")

      total =
        Enum.reduce(rows, %{gold: 0, xp: 0, items: %{}}, fn m, acc ->
          %{
            gold: acc.gold + m.gold,
            xp: acc.xp + m.xp,
            items: Map.merge(acc.items, m.items, fn _, a, b -> a + b end)
          }
        end)

      p = give(p, total)
      save.(p)
      {"Mở #{n} thư. " <> describe(total), p}
    end)
    |> case do
      {:ok, {msg, p}} ->
        notify(user_id)
        {:ok, msg, p}

      {:error, msg} ->
        {:error, msg}
    end
  end

  @doc "Xóa mọi thư đã mở. Trả về số thư đã xóa."
  def delete_read(user_id) do
    {n, _} =
      Repo.delete_all(
        from m in "mails", where: m.user_id == ^user_id and not is_nil(m.claimed_at)
      )

    n
  end

  # ---------- Đồ riêng từng món: "gear:<mẫu>:<độ hiếm>:<+N>" ----------

  @doc "Khóa `items` cho một món đồ riêng (dùng khi gửi)."
  def gear_key(base, rarity, up), do: "gear:#{base}:#{rarity}:#{up}"

  defp parse_gear("gear:" <> rest) do
    with [base, r, u] <- String.split(rest, ":"),
         {rarity, ""} <- Integer.parse(r),
         {up, ""} <- Integer.parse(u),
         it when not is_nil(it) <- Data.item(base),
         true <- it.slot in Engine.equip_slots(),
         true <- rarity in 0..3 and up in 0..Engine.max_upgrade(),
         true <- rarity == 0 or it.slot in ~w(weapon armor shield) do
      {base, rarity, up, it}
    else
      _ -> nil
    end
  end

  defp parse_gear(_), do: nil

  defp valid_item?(id), do: Data.item(id) != nil or parse_gear(id) != nil

  defp make_gear(p, {base, 0, _up, _it}), do: {Gear.plain(base), p}

  defp make_gear(p, {base, rarity, _up, _it}) do
    top = 1 + floor(p.level / 6)
    {Gear.new(base, rarity, Gear.stats() |> Enum.take(rarity) |> Map.new(&{&1, top})), p}
  end

  defp give(p, mail) do
    p = %{p | gold: p.gold + mail.gold}
    {gear, plain} = Enum.split_with(mail.items, fn {id, _} -> parse_gear(id) != nil end)
    need = Enum.reduce(gear, 0, fn {_, n}, acc -> acc + n end)

    if need > 0 and length(Gear.bag(p)) + need > Gear.max_bag(),
      do: Repo.rollback("Túi đồ hiếm không đủ chỗ cho #{need} món, dọn bớt rồi mở thư.")

    p =
      Enum.reduce(plain, p, fn {id, n}, p ->
        if Data.item(id), do: Engine.add_item(p, id, n), else: p
      end)

    p =
      Enum.reduce(gear, p, fn {id, n}, p ->
        {_, _, up, _} = spec = parse_gear(id)

        Enum.reduce(1..n, p, fn _, p ->
          {g, p} = make_gear(p, spec)
          {p, :kept} = Gear.add(p, g)

          if up > 0,
            do: Map.put(p, :upgrades, Map.put(Map.get(p, :upgrades) || %{}, g.uid, up)),
            else: p
        end)
      end)

    {_levels, p} = Engine.gain_xp(p, mail.xp)
    p
  end

  defp describe(%{gold: 0, xp: 0, items: items}) when map_size(items) == 0, do: "Đã đọc thư."

  defp describe(mail) do
    parts =
      [
        mail.gold > 0 && "+#{mail.gold} vàng",
        mail.xp > 0 && "+#{mail.xp} kinh nghiệm"
        | Enum.map(mail.items, fn {id, n} ->
            name = item_name(id)
            if n > 1, do: "#{name} ×#{n}", else: name
          end)
      ]
      |> Enum.filter(& &1)

    "Nhận quà: " <> Enum.join(parts, ", ") <> "."
  end

  @rarity %{1 => "Tốt", 2 => "Hiếm", 3 => "Sử Thi"}

  defp item_name(id) do
    case parse_gear(id) do
      {_, r, up, it} ->
        it.name <>
          if(r > 0, do: " (#{@rarity[r]})", else: "") <> if(up > 0, do: " +#{up}", else: "")

      nil ->
        if it = Data.item(id), do: it.name, else: id
    end
  end

  defp notify(user_id) do
    Phoenix.PubSub.broadcast(
      HacLong.PubSub,
      HacLong.Game.Session.topic(user_id),
      {:mail, unread(user_id)}
    )
  end
end

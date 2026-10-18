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

  Đồ riêng từng món (Phase 11, V10) ghi trong `items` với khóa `"gear:<mẫu>:<số dòng>:<+N>"`:
  số dòng cộng thêm kiểu MU 0..`Gear.max_opt/0` (B-15; thư cũ ghi độ hiếm 1..3 thành chừng đó dòng). Mở thư thì
  tạo từng món vào túi đồ hiếm; túi không đủ chỗ thì không mở được (giữ thư).
  """
  def send(user_id, attrs) do
    with {:ok, row} <- row(attrs) do
      Repo.insert_all("mails", [Map.put(row, :user_id, user_id)])
      notify(user_id)
      :ok
    end
  end

  @doc """
  Gửi cho mọi người đã có nhân vật (trừ bot), lọc theo `filter` (Phase 2): `min_level`, `max_level`,
  `min_rebirths`, `online` (true: chỉ người đang online). Trả về số thư đã gửi.
  """
  def send_all(attrs, filter \\ %{}) do
    with {:ok, row} <- row(attrs) do
      ids = recipients(filter)
      rows = Enum.map(ids, &Map.put(row, :user_id, &1))
      rows |> Enum.chunk_every(1000) |> Enum.each(&Repo.insert_all("mails", &1))
      Enum.each(ids, &notify/1)
      {:ok, length(ids)}
    end
  end

  @doc "Những người nhận của `send_all/2` với `filter` (mã tài khoản)."
  def recipients(filter \\ %{}) do
    f = Map.new(filter || %{}, fn {k, v} -> {to_string(k), v} end)
    int = fn k -> if is_integer(f[k]), do: f[k] end

    q =
      from c in Character,
        join: u in HacLong.Accounts.User,
        on: u.id == c.user_id,
        where: u.role != "bot",
        select: c.user_id

    q = if v = int.("min_level"), do: where(q, [c], c.level >= ^v), else: q
    q = if v = int.("max_level"), do: where(q, [c], c.level <= ^v), else: q
    q = if v = int.("min_rebirths"), do: where(q, [c], c.rebirths >= ^v), else: q
    ids = Repo.all(q)

    if f["online"] == true do
      on = MapSet.new(HacLong.Game.Session.online(1_000_000).players, & &1.id)
      Enum.filter(ids, &MapSet.member?(on, &1))
    else
      ids
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

  # ---------- Đồ riêng từng món: "gear:<mẫu>:<số dòng>:<+N>" ----------

  @doc "Khóa `items` cho một món đồ riêng (dùng khi gửi)."
  def gear_key(base, opt, up), do: "gear:#{base}:#{opt}:#{up}"

  defp parse_gear("gear:" <> rest) do
    with [base, r, u] <- String.split(rest, ":"),
         {opt, ""} <- Integer.parse(r),
         {up, ""} <- Integer.parse(u),
         it when not is_nil(it) <- Data.item(base),
         # "ring" (nhẫn) là loại đồ, ô mặc là ring1 / ring2: so với loại đồ mặc được
         true <- it.slot in Engine.item_slots(),
         true <- opt in 0..Gear.max_opt() and up in 0..Engine.max_upgrade(),
         true <- opt == 0 or it.slot in Engine.gear_slots() do
      {base, opt, up, it, %{}}
    else
      _ -> nil
    end
  end

  # đồ đủ dòng (May mắn / Kỹ năng / Excellent / Thần / dòng phụ cánh): "gearx:<base64 JSON>", server tự tạo
  # khi túi đồ hiếm đầy (`send_overflow/2`)
  defp parse_gear("gearx:" <> b64) do
    with {:ok, json} <- Base.url_decode64(b64, padding: false),
         {:ok, %{"base" => base} = m} <- Jason.decode(json),
         {base, 0, 0, it, _} <- parse_gear(gear_key(base, 0, 0)),
         opt when is_integer(opt) <- m["opt"] || 0,
         true <- opt in 0..Gear.max_opt() and extras_ok?(it, m) do
      {base, opt, 0, it, Map.take(m, ~w(luck skill exc anc wopt))}
    else
      _ -> nil
    end
  end

  defp parse_gear(_), do: nil

  defp extras_ok?(it, m) do
    m["luck"] in [nil, true] and m["skill"] in [nil, true] and m["anc"] in [nil, true] and
      (m["wopt"] == nil or Gear.wopt_value(it[:tier], m["wopt"]) > 0) and
      (m["exc"] == nil or
         (is_list(m["exc"]) and
            Enum.all?(m["exc"], &(is_binary(&1) and Gear.exc_value(it.slot, &1) > 0))))
  end

  defp gearx_key(g) do
    spec =
      g
      |> Map.take([:base, :opt, :luck, :skill, :exc, :anc, :wopt])
      |> Map.reject(fn {_, v} -> v in [nil, false, [], 0] end)

    "gearx:" <> Base.url_encode64(Jason.encode!(spec), padding: false)
  end

  defp valid_item?(id), do: Data.item(id) != nil or parse_gear(id) != nil

  defp make_gear(p, {base, opt, _up, _it, extras}) do
    g =
      Enum.reduce(extras, Gear.new(base, opt), fn
        {"exc", v}, g -> Map.put(g, :exc, Enum.uniq(v))
        {k, v}, g -> Map.put(g, String.to_existing_atom(k), v)
      end)

    {g, p}
  end

  @doc """
  Gửi các món chờ trong `p.mail_out` (túi đồ hiếm đầy, `Gear.add/2`) vào Hộp thư, mỗi món một thư, giữ đủ dòng.
  Hộp thư đã có `RULES.mail.keep` thư chưa mở thì bán món còn lại lấy vàng. Gọi trong transaction lưu nhân vật.
  Trả về nhân vật đã bỏ `mail_out` (và cộng vàng bán, nếu có).
  """
  def send_overflow(user_id, %{mail_out: [_ | _] = list} = p) do
    room = max(@keep - unread(user_id), 0)
    {mail, sell} = Enum.split(list, room)

    Enum.each(mail, fn g ->
      __MODULE__.send(user_id, %{
        subject: "Túi trang bị đầy: #{Gear.label(g)}",
        body:
          "Món này rơi lúc túi trang bị đã đủ #{Gear.max_bag()} món. Dọn túi rồi mở thư để nhận.",
        items: %{gearx_key(g) => 1}
      })
    end)

    gold = sell |> Enum.map(&Gear.price/1) |> Enum.sum()
    %{Map.delete(p, :mail_out) | gold: p.gold + gold}
  end

  def send_overflow(_user_id, p), do: Map.delete(p, :mail_out)

  defp give(p, mail) do
    p = %{p | gold: p.gold + mail.gold}
    {gear, plain} = Enum.split_with(mail.items, fn {id, _} -> parse_gear(id) != nil end)
    need = Enum.reduce(gear, 0, fn {_, n}, acc -> acc + n end)

    if need > 0 and length(Gear.bag(p)) + need > Gear.max_bag(),
      do: Repo.rollback("Túi trang bị không đủ chỗ cho #{need} món, dọn bớt rồi mở thư.")

    p =
      Enum.reduce(plain, p, fn {id, n}, p ->
        if Data.item(id), do: Engine.add_item(p, id, n), else: p
      end)

    p =
      Enum.reduce(gear, p, fn {id, n}, p ->
        {_, _, up, _, _} = spec = parse_gear(id)

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

  defp item_name(id) do
    case parse_gear(id) do
      {_, _, up, _, _} = spec ->
        {g, _} = make_gear(nil, spec)
        Gear.label(g) <> if(up > 0, do: " +#{up}", else: "")

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

defmodule Mu.Guild do
  @moduledoc """
  Guild đang online (`KB_GAME_DESIGN §14`, P4-M3 theo P4-5). Dữ liệu guild nằm trong DB
  (`Mu.Guilds`); tiến trình này giữ phần **trong RAM**: ai đang online (Session nào), lời mời
  (hết hạn sau `guild.inviteSeconds`), và là nơi duy nhất áp luật quyền của từng vai trò rồi gọi
  `Mu.Guilds` tuần tự.

  - Quyền: master + assistant mời; master đuổi mọi người, assistant đuổi member; chỉ master phong
    / hạ assistant và giải tán; master không rời được (phải giải tán).
  - Mỗi thay đổi: đẩy event `guild` cho mọi thành viên đang online (gửi qua Session:
    `{:guild_push, event, payload}`); người bị đổi guild (vào / rời / bị đuổi / giải tán) nhận
    thêm `{:guild_changed, membership}` để Session báo MapServer (tên guild trên đầu, `spawn`).
  - Thông báo trong guild (vào / rời / bị đuổi / phong / hạ / giải tán / từ chối) là dòng chat
    `SYSTEM`; chat `GUILD` tới mọi thành viên đang online.
  - Session tắt (rời game hẳn) → `{:DOWN, ...}` → offline (khác Party: vẫn là thành viên).
  """
  use GenServer

  alias Mu.{Chat, Guilds}
  alias Mu.Game.Config

  # ---------- API ----------

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Session của nhân vật `%{cid, name}` vào game (tiến trình gọi = Session). Trả membership
  (`%{guild_id, name, role}` hoặc `nil`) và đẩy `guild` cho Session đó.
  """
  def online(me), do: GenServer.call(__MODULE__, {:online, me, self()})

  @doc "Nhân vật rời game hẳn."
  def offline(cid), do: GenServer.call(__MODULE__, {:offline, cid})

  @doc "Tạo guild: `{:ok, %{zen, version}}` hoặc `{:error, code}`."
  def create(cid, name), do: GenServer.call(__MODULE__, {:create, cid, name})

  def invite(cid, to), do: GenServer.call(__MODULE__, {:invite, cid, to})
  def accept(cid, guild), do: GenServer.call(__MODULE__, {:accept, cid, guild})
  def decline(cid, guild), do: GenServer.call(__MODULE__, {:decline, cid, guild})
  def leave(cid), do: GenServer.call(__MODULE__, {:leave, cid})
  def kick(cid, name), do: GenServer.call(__MODULE__, {:kick, cid, name})
  def promote(cid, name), do: GenServer.call(__MODULE__, {:role, cid, name, "assistant"})
  def demote(cid, name), do: GenServer.call(__MODULE__, {:role, cid, name, "member"})
  def disband(cid), do: GenServer.call(__MODULE__, {:disband, cid})

  @doc "Tin chat GUILD tới mọi thành viên đang online; không có guild → `INVALID_TARGET`."
  def chat(cid, msg), do: GenServer.call(__MODULE__, {:chat, cid, msg})

  @doc "Membership đang giữ trong RAM của nhân vật online (test)."
  def membership(cid), do: GenServer.call(__MODULE__, {:membership, cid})

  # ---------- GenServer ----------

  @impl true
  def init(_) do
    schedule()

    {:ok,
     %{
       # cid → %{name, session, ref, guild: %{guild_id, name, role} | nil}
       online: %{},
       # tên chữ thường → cid (người đang online)
       names: %{},
       # cid người được mời → %{guild_id => %{from: tên người mời, from_cid, until: ms}}
       invites: %{},
       # guild_id → %{id, name, members: [%{character_id, name, class, level, role}]} đọc từ DB
       # lần thay đổi gần nhất; offline / online chỉ cần đẩy lại cờ `online` nên không đọc DB
       views: %{}
     }}
  end

  @impl true
  def handle_call({:online, me, session}, _from, s) do
    s = drop_online(s, me.cid)
    ref = Process.monitor(session)
    m = Guilds.membership(me.cid)

    s = %{
      s
      | online: Map.put(s.online, me.cid, %{name: me.name, session: session, ref: ref, guild: m}),
        names: Map.put(s.names, String.downcase(me.name), me.cid)
    }

    # có guild: đọc lại danh sách (cấp mới của thành viên) rồi đẩy cho cả guild
    s = if m, do: refresh(s, m.guild_id), else: s
    unless m, do: send(session, {:guild_push, "guild", render(s, nil)})
    {:reply, m, s}
  end

  def handle_call({:offline, cid}, _from, s) do
    g = guild_of(s, cid)
    s = drop_online(s, cid)
    {:reply, :ok, if(g, do: push_view(s, g.guild_id), else: s)}
  end

  def handle_call({:create, cid, name}, _from, s) do
    with %{} = me <- s.online[cid] || {:error, "FORBIDDEN"},
         {:ok, m, zen} <- Guilds.create(cid, name) do
      s = set_guild(s, cid, m)
      send(me.session, {:guild_changed, m})
      {:reply, {:ok, zen}, refresh(s, m.guild_id)}
    else
      {:error, code} -> {:reply, {:error, code}, s}
    end
  end

  def handle_call({:invite, cid, to}, _from, s) do
    target = s.names[String.downcase(to)]

    with %{role: role} = g when role in ~w(master assistant) <-
           guild_of(s, cid) || {:error, "INVALID_TARGET"},
         true <- (target != nil and target != cid) || {:error, "INVALID_TARGET"},
         nil <- guild_of(s, target) && {:error, "INVALID_TARGET"},
         true <- Guilds.count(g.guild_id) < max_members() || {:error, "FORBIDDEN"} do
      until = now() + Config.get(["guild", "inviteSeconds"]) * 1000
      inv = %{from: s.online[cid].name, from_cid: cid, name: g.name, until: until}
      invites = Map.update(s.invites, target, %{g.guild_id => inv}, &Map.put(&1, g.guild_id, inv))

      send(
        s.online[target].session,
        {:guild_push, "guild_invite", %{from: inv.from, guild: g.name}}
      )

      {:reply, :ok, %{s | invites: invites}}
    else
      %{} -> {:reply, {:error, "FORBIDDEN"}, s}
      {:error, code} -> {:reply, {:error, code}, s}
    end
  end

  def handle_call({:accept, cid, guild}, _from, s) do
    with {:ok, gid, inv, s} <- take_invite(s, cid, guild),
         nil <- guild_of(s, cid) && {:error, "INVALID_TARGET"},
         :ok <- Guilds.add_member(gid, cid) do
      m = %{guild_id: gid, name: inv.name, role: "member"}
      s = set_guild(s, cid, m)
      send(s.online[cid].session, {:guild_changed, m})
      notice(s, gid, "#{s.online[cid].name} đã vào guild.")
      {:reply, :ok, refresh(s, gid)}
    else
      {:error, code} -> {:reply, {:error, code}, s}
    end
  end

  def handle_call({:decline, cid, guild}, _from, s) do
    case take_invite(s, cid, guild) do
      {:ok, _gid, inv, s} ->
        if from = s.online[inv.from_cid],
          do: system(from.session, "#{s.online[cid].name} từ chối lời mời vào guild.")

        {:reply, :ok, s}

      {:error, code} ->
        {:reply, {:error, code}, s}
    end
  end

  def handle_call({:leave, cid}, _from, s) do
    case guild_of(s, cid) do
      nil ->
        {:reply, {:error, "INVALID_TARGET"}, s}

      %{role: "master"} ->
        {:reply, {:error, "FORBIDDEN"}, s}

      g ->
        :ok = Guilds.remove_member(cid)
        {:reply, :ok, removed(s, g.guild_id, cid, "#{s.online[cid].name} đã rời guild.")}
    end
  end

  def handle_call({:kick, cid, name}, _from, s) do
    with %{} = g <- guild_of(s, cid) || {:error, "INVALID_TARGET"},
         %{} = t <- member(g.guild_id, name) || {:error, "INVALID_TARGET"},
         true <- t.character_id != cid || {:error, "INVALID_TARGET"},
         true <- can_kick?(g.role, t.role) || {:error, "FORBIDDEN"},
         :ok <- Guilds.remove_member(t.character_id) do
      {:reply, :ok, removed(s, g.guild_id, t.character_id, "#{t.name} bị mời ra khỏi guild.")}
    else
      {:error, code} -> {:reply, {:error, code}, s}
    end
  end

  def handle_call({:role, cid, name, role}, _from, s) do
    with %{} = g <- guild_of(s, cid) || {:error, "INVALID_TARGET"},
         true <- g.role == "master" || {:error, "FORBIDDEN"},
         %{} = t <- member(g.guild_id, name) || {:error, "INVALID_TARGET"},
         true <- t.role != role || {:error, "INVALID_TARGET"},
         :ok <- Guilds.set_role(g.guild_id, t.character_id, role) do
      s =
        if s.online[t.character_id],
          do: set_guild(s, t.character_id, %{g | role: role}),
          else: s

      text =
        if role == "assistant",
          do: "#{t.name} được phong làm phó guild.",
          else: "#{t.name} thôi làm phó guild."

      notice(s, g.guild_id, text)
      {:reply, :ok, refresh(s, g.guild_id)}
    else
      {:error, code} -> {:reply, {:error, code}, s}
    end
  end

  def handle_call({:disband, cid}, _from, s) do
    case guild_of(s, cid) do
      nil ->
        {:reply, {:error, "INVALID_TARGET"}, s}

      %{role: "master"} = g ->
        notice(s, g.guild_id, "Guild #{g.name} đã giải tán.")
        :ok = Guilds.disband(g.guild_id)

        s =
          Enum.reduce(online_members(s, g.guild_id), s, fn {mcid, m}, s ->
            send(m.session, {:guild_changed, nil})
            send(m.session, {:guild_push, "guild", render(s, nil)})
            set_guild(s, mcid, nil)
          end)

        s = %{s | views: Map.delete(s.views, g.guild_id)}

        invites =
          for {to, by} <- s.invites,
              by = Map.delete(by, g.guild_id),
              map_size(by) > 0,
              into: %{},
              do: {to, by}

        {:reply, :ok, %{s | invites: invites}}

      _ ->
        {:reply, {:error, "FORBIDDEN"}, s}
    end
  end

  def handle_call({:chat, cid, msg}, _from, s) do
    case guild_of(s, cid) do
      nil ->
        {:reply, {:error, "INVALID_TARGET"}, s}

      g ->
        for {_, m} <- online_members(s, g.guild_id),
            do: send(m.session, {:guild_push, "chat", msg})

        {:reply, :ok, s}
    end
  end

  def handle_call({:membership, cid}, _from, s), do: {:reply, guild_of(s, cid), s}

  @impl true
  def handle_info(:tick, s) do
    schedule()
    t = now()

    invites =
      for {to, by} <- s.invites,
          live = Map.filter(by, fn {_, inv} -> inv.until > t end),
          map_size(live) > 0,
          into: %{},
          do: {to, live}

    {:noreply, %{s | invites: invites}}
  end

  # Session tắt (rời game hẳn / lỗi): offline, vẫn là thành viên
  def handle_info({:DOWN, ref, :process, _pid, _}, s) do
    case Enum.find(s.online, fn {_, o} -> o.ref == ref end) do
      {cid, o} ->
        s = drop_online(s, cid)
        {:noreply, if(o.guild, do: push_view(s, o.guild.guild_id), else: s)}

      nil ->
        {:noreply, s}
    end
  end

  def handle_info(_msg, s), do: {:noreply, s}

  # ---------- Nội bộ ----------

  # Payload event `guild`: `%{id, name, master, members: [%{name, class, level, role, online}]}`;
  # không có guild → `%{id: nil, name: nil, master: nil, members: []}`.
  defp render(s, guild_id) do
    case guild_id && s.views[guild_id] do
      nil ->
        %{id: nil, name: nil, master: nil, members: []}

      v ->
        members =
          for m <- v.members do
            %{
              name: m.name,
              class: m.class,
              level: m.level,
              role: m.role,
              online: Map.has_key?(s.online, m.character_id)
            }
          end

        master = Enum.find_value(members, &(&1.role == "master" && &1.name))
        %{id: v.id, name: v.name, master: master, members: members}
    end
  end

  # đọc lại guild từ DB rồi đẩy cho thành viên đang online
  defp refresh(s, guild_id) do
    views =
      case Guilds.get(guild_id) do
        nil -> Map.delete(s.views, guild_id)
        g -> Map.put(s.views, guild_id, %{id: g.id, name: g.name, members: Guilds.members(g.id)})
      end

    push_view(%{s | views: views}, guild_id)
  end

  # đẩy bản đang giữ (không đọc DB); guild không còn ai online thì bỏ bản giữ
  defp push_view(s, guild_id) do
    case online_members(s, guild_id) do
      [] ->
        %{s | views: Map.delete(s.views, guild_id)}

      ms ->
        v = render(s, guild_id)
        for {_, m} <- ms, do: send(m.session, {:guild_push, "guild", v})
        s
    end
  end

  # `cid` ra khỏi guild (rời / bị đuổi): báo guild, báo người đó (đang online)
  defp removed(s, guild_id, cid, text) do
    notice(s, guild_id, text)

    s =
      case s.online[cid] do
        nil ->
          s

        o ->
          send(o.session, {:guild_changed, nil})
          send(o.session, {:guild_push, "guild", render(s, nil)})
          set_guild(s, cid, nil)
      end

    refresh(s, guild_id)
  end

  defp can_kick?("master", _), do: true
  defp can_kick?("assistant", "member"), do: true
  defp can_kick?(_, _), do: false

  defp member(guild_id, name) when is_binary(name) do
    lc = String.downcase(name)
    Enum.find(Guilds.members(guild_id), &(String.downcase(&1.name) == lc))
  end

  defp member(_, _), do: nil

  defp take_invite(s, cid, guild) when is_binary(guild) do
    lc = String.downcase(guild)
    by = Map.get(s.invites, cid, %{})
    t = now()

    case Enum.find(by, fn {_, inv} -> String.downcase(inv.name) == lc and inv.until > t end) do
      {gid, inv} ->
        by = Map.delete(by, gid)

        invites =
          if map_size(by) == 0, do: Map.delete(s.invites, cid), else: Map.put(s.invites, cid, by)

        {:ok, gid, inv, %{s | invites: invites}}

      nil ->
        {:error, "INVALID_TARGET"}
    end
  end

  defp take_invite(_s, _cid, _guild), do: {:error, "INVALID_TARGET"}

  defp guild_of(_s, nil), do: nil
  defp guild_of(s, cid), do: s.online[cid] && s.online[cid].guild

  defp set_guild(s, cid, m), do: put_in(s.online[cid].guild, m)

  defp online_members(s, guild_id),
    do: Enum.filter(s.online, fn {_, o} -> o.guild && o.guild.guild_id == guild_id end)

  defp drop_online(s, cid) do
    case s.online[cid] do
      nil ->
        s

      o ->
        Process.demonitor(o.ref, [:flush])

        %{
          s
          | online: Map.delete(s.online, cid),
            names: Map.delete(s.names, String.downcase(o.name)),
            invites: Map.delete(s.invites, cid)
        }
    end
  end

  defp notice(s, guild_id, text),
    do: for({_, m} <- online_members(s, guild_id), do: system(m.session, text))

  defp system(pid, text),
    do:
      send(
        pid,
        {:guild_push, "chat", Chat.message("SYSTEM", Config.get(["chat", "systemName"]), text)}
      )

  defp max_members, do: Config.get(["guild", "maxMembers"])

  defp schedule, do: Process.send_after(self(), :tick, 1000)
  defp now, do: System.monotonic_time(:millisecond)
end

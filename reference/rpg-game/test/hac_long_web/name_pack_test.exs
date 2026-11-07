defmodule HacLongWeb.NamePackTest do
  # DECISIONS "Bộ tên thay cho tên MU": một công tắc cho cả server, lưu qua admin_log, báo mọi người đang chơi
  use HacLongWeb.ChannelCase
  import Phoenix.ConnTest, only: [build_conn: 0, get: 2, json_response: 2]

  alias HacLong.{Accounts, Moderation, NamePack}
  alias HacLong.Game.{Characters, Commands}
  alias HacLongWeb.{ClientVersion, UserSocket}

  @endpoint HacLongWeb.Endpoint

  setup do
    HacLong.RateLimit.reset()
    on_exit(fn -> :persistent_term.put({NamePack, :pack}, "mu") end)
    :ok
  end

  defp join(user) do
    {_, p} =
      Commands.run(nil, %{
        "act" => "create",
        "name" => "Np #{rem(System.unique_integer([:positive]), 100_000)}",
        "cls" => "dk"
      })

    Characters.save!(
      user.id,
      Map.merge(p, %{tutorial: nil, pos: %{map: "village", x: 12, y: 14}}),
      "TEST"
    )

    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})
    {:ok, _reply, socket} = subscribe_and_join(socket, "game", %{"v" => ClientVersion.current()})
    socket
  end

  defp admin(socket, op, payload \\ %{}) do
    ref = push(socket, "admin", Map.put(payload, "op", op))
    assert_reply ref, status, r
    {status, r}
  end

  defp pack_api, do: build_conn() |> get("/api/names") |> json_response(200)

  test "quản trị đổi bộ tên: /api/names đổi, người đang chơi được báo, khởi động lại vẫn nhớ" do
    :persistent_term.put({NamePack, :pack}, "mu")
    a = create_user()
    {:ok, _} = Moderation.set_admin(a.username, true)
    sa = join(a)
    su = join(create_user())

    assert %{"pack" => "mu"} = pack_api()
    assert {:ok, %{name_pack: "mu"}} = admin(sa, "flags")
    assert {:error, _} = admin(su, "name_pack", %{"pack" => "alt"})
    assert {:error, _} = admin(sa, "name_pack", %{"pack" => "xyz"})

    assert {:ok, %{name_pack: "alt"}} = admin(sa, "name_pack", %{"pack" => "alt"})
    assert_push "name_pack", %{pack: "alt"}
    assert %{"pack" => "alt"} = pack_api()

    # như vừa khởi động lại: đọc từ admin_log
    :persistent_term.erase({NamePack, :pack})
    assert NamePack.get() == "alt"

    assert {:ok, %{name_pack: "mu"}} = admin(sa, "name_pack", %{"pack" => "mu"})
    assert %{"pack" => "mu"} = pack_api()
  end

  test "names_alt.json: khóa và tên mới không trống, tên mới không chứa khóa khác (đổi một lượt, không đổi chồng)" do
    d =
      Path.join(:code.priv_dir(:hac_long), "static/i18n/names_alt.json")
      |> File.read!()
      |> Jason.decode!()

    pairs = for {_g, m} <- d["groups"], {k, v} <- m, do: {k, v}
    assert length(pairs) > 300
    keys = Enum.map(pairs, &elem(&1, 0))

    for {k, [vi, en]} <- pairs do
      assert k != "" and vi != "" and en != ""

      for other <- keys,
          do:
            refute(
              Regex.match?(~r/(?<![\p{L}\p{N}])#{Regex.escape(other)}(?![\p{L}\p{N}])/u, vi),
              "#{vi} (tên mới của #{k}) chứa khóa #{other}"
            )
    end
  end
end

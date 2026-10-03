defmodule Mu.SchemaTest do
  @moduledoc "Ràng buộc DB của KB_TECHNICAL §9 chặn dữ liệu sai kể cả khi bỏ qua code app."
  use Mu.DataCase, async: true

  defp sql(query, params), do: Ecto.Adapters.SQL.query(Repo, query, params)

  defp uuid, do: Ecto.UUID.bingenerate()

  defp insert_character(account_id, overrides \\ %{}) do
    v =
      Map.merge(
        %{name: "Check#{rem(System.unique_integer([:positive]), 10000)}", class: "DK", zen: 0},
        overrides
      )

    id = uuid()

    with {:ok, _} <-
           sql(
             """
             INSERT INTO characters (id, account_id, name, class, strength, agility, vitality,
               energy, hp_current, mana_current, zen, map_id, position_x, position_y)
             VALUES ($1, $2, $3, $4, 28, 20, 25, 10, 185, 30, $5, 'lorencia', 1, 1)
             """,
             [id, account_id, v.name, v.class, v.zen]
           ) do
      {:ok, id}
    end
  end

  defp insert_item(quantity \\ 1) do
    id = uuid()
    serial = String.pad_leading("#{System.unique_integer([:positive])}", 26, "0")

    with {:ok, _} <-
           sql("INSERT INTO items (id, serial, template_id, quantity) VALUES ($1, $2, 'x', $3)", [
             id,
             serial,
             quantity
           ]) do
      {:ok, id}
    end
  end

  defp locate(item_id, location, character_id, account_id, slot) do
    sql(
      "INSERT INTO item_locations (item_id, location, character_id, account_id, slot) VALUES ($1, $2, $3, $4, $5)",
      [item_id, location, character_id, account_id, slot]
    )
  end

  setup do
    account = create_account()
    {:ok, account_id} = Ecto.UUID.dump(account.id)
    {:ok, char_id} = insert_character(account_id)
    %{account_id: account_id, char_id: char_id}
  end

  test "characters: CHECK tên, class, zen; tên unique không phân biệt hoa thường", ctx do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_character(ctx.account_id, %{name: "ab"})

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_character(ctx.account_id, %{name: "Trần12"})

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_character(ctx.account_id, %{class: "XX"})

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_character(ctx.account_id, %{zen: -1})

    assert {:ok, _} = insert_character(ctx.account_id, %{name: "SameName"})

    assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
             insert_character(ctx.account_id, %{name: "SAMENAME"})
  end

  test "accounts: username unique không phân biệt hoa thường" do
    q = "INSERT INTO accounts (id, username, password_hash) VALUES ($1, $2, 'h')"
    assert {:ok, _} = sql(q, [uuid(), "CaseUser"])

    assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
             sql(q, [uuid(), "caseuser"])
  end

  test "items: quantity ≥ 1, serial unique" do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} = insert_item(0)

    q = "INSERT INTO items (id, serial, template_id) VALUES ($1, $2, 'x')"
    serial = String.duplicate("Z", 26)
    assert {:ok, _} = sql(q, [uuid(), serial])

    assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
             sql(q, [uuid(), serial])
  end

  test "item_locations: một item chỉ một chỗ (chặn dupe)", ctx do
    {:ok, item} = insert_item()
    assert {:ok, _} = locate(item, "INVENTORY", ctx.char_id, nil, 0)

    assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
             locate(item, "EQUIPMENT", ctx.char_id, nil, 1)
  end

  test "item_locations: owner đúng loại location", ctx do
    {:ok, item} = insert_item()

    for {loc, char, acc} <- [
          {"INVENTORY", nil, ctx.account_id},
          {"INVENTORY", ctx.char_id, ctx.account_id},
          {"EQUIPMENT", nil, nil},
          {"WAREHOUSE", ctx.char_id, nil},
          {"MAIL", ctx.char_id, nil}
        ] do
      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               locate(item, loc, char, acc, 0),
             "#{loc} char=#{!!char} acc=#{!!acc}"
    end

    assert {:ok, _} = locate(item, "WAREHOUSE", nil, ctx.account_id, 0)
  end

  test "item_locations: giới hạn slot theo location", ctx do
    for {loc, char, acc, bad, good} <- [
          {"EQUIPMENT", ctx.char_id, nil, 10, 9},
          {"INVENTORY", ctx.char_id, nil, 64, 63},
          {"WAREHOUSE", nil, ctx.account_id, 120, 119}
        ] do
      {:ok, item} = insert_item()

      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               locate(item, loc, char, acc, bad)

      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               locate(item, loc, char, acc, -1)

      assert {:ok, _} = locate(item, loc, char, acc, good)
    end
  end

  test "item_locations: hai item không cùng một slot (partial unique index)", ctx do
    {:ok, a} = insert_item()
    {:ok, b} = insert_item()
    assert {:ok, _} = locate(a, "INVENTORY", ctx.char_id, nil, 5)

    assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
             locate(b, "INVENTORY", ctx.char_id, nil, 5)

    {:ok, c} = insert_item()
    {:ok, d} = insert_item()
    assert {:ok, _} = locate(c, "WAREHOUSE", nil, ctx.account_id, 5)

    assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
             locate(d, "WAREHOUSE", nil, ctx.account_id, 5)
  end

  test "item_audit_log không có FK tới items (log sống lâu hơn item)" do
    assert {:ok, _} =
             sql("INSERT INTO item_audit_log (item_id, action) VALUES ($1, 'CREATE')", [uuid()])
  end
end

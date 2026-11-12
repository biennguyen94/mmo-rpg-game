# Chuẩn bị nhân vật cho e2e/hac_long.mjs: gọi vào server đang chạy (`elixir --sname mu -S mix phx.server`) qua Erlang
# distribution, sửa nhân vật trong Session của nó (như quản trị).
#
#     elixir --sname prep$RANDOM scripts/hacprep.exs <tên nhân vật> ready
#
# ready: có Long Vương và Chim Lạc cấp tối đa (đủ điều kiện ghép Hắc Long ở Lão Hỗn Nguyên).
[name, mode] = System.argv()
{:ok, host} = :inet.gethostname()
node = :"#{System.get_env("HL_NODE", "mu")}@#{host}"
true = Node.connect(node) || raise "không kết nối được #{node}"

code = """
alias HacLong.Game.{Data, Kite, Pets}
u = HacLong.Moderation.find_user(#{inspect(name)}) || raise "không có #{name}"

fun =
  case #{inspect(mode)} do
    "ready" ->
      fn p ->
        ids = [Data.rules().fishing.dragon.pet, Kite.rules().bird.pet]
        xp = Map.new(ids, &{&1, Pets.xp_for(Pets.max_level(&1))})

        p =
          p
          |> Map.put(:pets, Enum.uniq((Map.get(p, :pets) || []) ++ ids))
          |> Map.put(:pet_xp, Map.merge(Map.get(p, :pet_xp) || %{}, xp))

        {:ok, p, "e2e: đủ điều kiện ghép Hắc Long"}
      end
  end

HacLong.Game.Session.admin(u.id, fun)
"""

{res, _} = :erpc.call(node, Code, :eval_string, [code])
IO.inspect(res, label: "hacprep")

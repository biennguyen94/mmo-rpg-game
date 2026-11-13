# Thang vùng co giãn theo server (DECISIONS "Thang vùng co giãn theo server"): chỉnh độ dốc sau mức 10
# (`RULES.realms.ladder.hp_after`, `atk_after`). Nhân vật đồ tối đa chuyển sinh k (10, 12, 15, 20, 25, 30; điểm và máu theo
# chuyển sinh vô hạn) đánh quái thường của vùng 10 dời lên đúng mức k (`HacLong.RealmLadder.adjust/5`). Mục tiêu: số đòn
# thường để hạ và % máu mất mỗi đòn quái trúng ở mọi k gần bằng k = 10 (độ khó đi cùng người chơi).
#   MIX_ENV=test mix run --no-start scripts/realm_ladder/tune.exs          # bảng với hệ số đang có trong RULES
#   SEARCH=1 MIX_ENV=test mix run --no-start scripts/realm_ladder/tune.exs # dò lưới, in cặp hệ số tốt nhất
Code.require_file(Path.join(__DIR__, "../pvp/build.exs"))

defmodule KhoDo.RealmTune do
  alias HacLong.Game.{Data, Engine}
  alias HacLong.RealmLadder

  @ks [10, 12, 15, 20, 25, 30]
  @classes ~w(dk dw elf mg)
  @mons ~w(r10_white_wizard r10_lich r10_stone_giant)

  def ks, do: @ks

  defp avg(f), do: Enum.sum(for(_ <- 1..120, do: f.())) / 120

  def chars do
    :rand.seed(:exsss, {3, 1, 4})
    for k <- @ks, c <- @classes, into: %{}, do: {{c, k}, Engine.derived(Max.build(c, rebirths: k))}
  end

  # vùng 10 dời tới mức k: thang chỉ đổi vùng 10
  defp monster(id, k, r) do
    ks = Enum.to_list(1..9) ++ [k]
    spec = RealmLadder.adjust(Data.side_monster(id), 10, k, ks, r)
    Engine.make_monster(spec, false)
  end

  @doc "Mỗi k: %{hits, taken} trung bình 4 lớp × 3 quái."
  def measure(chars, r) do
    for k <- @ks, into: %{} do
      vs =
        for c <- @classes, id <- @mons do
          d = chars[{c, k}]
          m = monster(id, k, r)
          hit = avg(fn -> Engine.damage(d.atk, m.def) end)
          taken = avg(fn -> Engine.damage(m.atk, d.def) end) * (1 - d.wingAbsorb) * (1 - d.excAbsorb)
          {m.maxHp / max(hit, 1), taken / d.maxHp * 100}
        end

      n = length(vs)
      {k, %{hits: Enum.sum(Enum.map(vs, &elem(&1, 0))) / n, taken: Enum.sum(Enum.map(vs, &elem(&1, 1))) / n}}
    end
  end

  def with(r, hp, atk), do: put_in(r, [:ladder, :hp_after], hp) |> put_in([:ladder, :atk_after], atk)

  # độ lệch tương đối lớn nhất so với k = 10 (số đòn và % máu)
  def score(m) do
    b = m[10]
    @ks |> Enum.map(fn k -> max(abs(m[k].hits / b.hits - 1), abs(m[k].taken / b.taken - 1)) end) |> Enum.max()
  end

  def print(m) do
    for k <- @ks, do: IO.puts("  CS #{k}: #{Float.round(m[k].hits, 1)} đòn · #{Float.round(m[k].taken, 1)}% máu / đòn quái")
  end
end

alias KhoDo.RealmTune
r = HacLong.Game.Data.rules().realms
chars = RealmTune.chars()
IO.puts("Hệ số hiện tại: hp_after #{r.ladder.hp_after}, atk_after #{r.ladder.atk_after}")
cur = RealmTune.measure(chars, r)
RealmTune.print(cur)
IO.puts("  lệch lớn nhất so với CS 10: #{round(RealmTune.score(cur) * 100)}%")

if System.get_env("SEARCH") == "1" do
  grid =
    for hp <- Enum.map(0..16, &(&1 * 0.025)), atk <- Enum.map(0..12, &(&1 * 0.0125)) do
      m = RealmTune.measure(chars, RealmTune.with(r, hp, atk))
      {RealmTune.score(m), hp, atk, m}
    end

  {s, hp, atk, m} = Enum.min_by(grid, &elem(&1, 0))
  IO.puts("\nTốt nhất: hp_after #{Float.round(hp, 3)}, atk_after #{Float.round(atk, 4)} (lệch #{round(s * 100)}%)")
  RealmTune.print(m)
end

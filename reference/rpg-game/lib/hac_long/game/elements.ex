defmodule HacLong.Game.Elements do
  @moduledoc """
  Nguyên tố (Phase 3, DECISIONS B-29, `RULES.elements`): kỹ năng có `element`; quái mang nguyên tố theo cấp
  (`by_level`) hoặc `element` riêng. Kỹ năng khắc nguyên tố quái thì × (1 + strong), bị quái khắc thì
  × (1 − weak), còn lại × 1. Hàm thuần.
  """
  alias HacLong.Game.Data

  @r Data.rules().elements
  @beats Map.new(@r.beats, fn {k, v} -> {Atom.to_string(k), v} end)
  @by_level @r.by_level

  def rules, do: @r
  def list, do: @r.list

  @doc "Nguyên tố của quái cấp `level` (không có `element` riêng)."
  def for_level(level) when is_integer(level) do
    Enum.reduce(@by_level, nil, fn [from, el], acc -> if level >= from, do: el, else: acc end)
  end

  def for_level(_), do: nil

  @doc "`a` khắc `b` không."
  def beats?(a, b) when is_binary(a) and is_binary(b), do: b in (@beats[a] || [])
  def beats?(_, _), do: false

  @doc "Hệ số sát thương kỹ năng nguyên tố `skill` đánh quái nguyên tố `target`: `{hệ_số, :strong | :weak | nil}`."
  def mult(skill, target) do
    cond do
      beats?(skill, target) -> {1 + @r.strong, :strong}
      beats?(target, skill) -> {1 - @r.weak, :weak}
      true -> {1, nil}
    end
  end

  def name(el), do: (@r.names |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end))[el]
end

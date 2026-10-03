defmodule Mu.Ulid do
  @moduledoc """
  ULID (https://github.com/ulid/spec): 48 bit thời gian (ms) + 80 bit ngẫu nhiên, mã hóa
  Crockford base32 thành 26 ký tự, sắp xếp được theo thời gian. Dùng cho `items.serial`
  (`KB_TECHNICAL §9`, do server sinh). Tự viết thay gói `ecto_ulid` (DEC-5).
  """

  @alphabet ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  @max_ms 281_474_976_710_656

  @doc "ULID mới. `ms` (thời gian Unix, ms) và `random` (10 byte) chỉ truyền trong test."
  def generate(ms \\ System.os_time(:millisecond), random \\ :crypto.strong_rand_bytes(10))
      when is_integer(ms) and ms >= 0 and ms < @max_ms and byte_size(random) == 10 do
    encode(<<ms::unsigned-size(48), random::binary>>)
  end

  @doc "Mã hóa 128 bit thành 26 ký tự Crockford base32 (2 bit 0 đệm ở đầu)."
  def encode(<<bin::bits-size(128)>>) do
    for <<(c::5 <- <<0::2, bin::bits>>)>>, into: "", do: <<Enum.at(@alphabet, c)>>
  end

  @doc "Chuỗi có đúng dạng ULID không."
  def valid?(s) when is_binary(s), do: s =~ ~r/^[0-7][0-9A-HJKMNP-TV-Z]{25}$/
  def valid?(_), do: false
end

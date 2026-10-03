defmodule Mu.ChatTest do
  use ExUnit.Case, async: false

  alias Mu.Chat

  test "clean: bỏ ký tự điều khiển, gộp khoảng trắng, cắt maxLength (100); trống → lỗi" do
    assert {:ok, "xin chào bạn"} = Chat.clean("  xin\tchào\n\n bạn ​ ")
    assert {:ok, long} = Chat.clean(String.duplicate("á", 150))
    assert String.length(long) == 100
    assert {:error, "INVALID_TARGET"} = Chat.clean("   \n ")
    assert {:error, "INVALID_TARGET"} = Chat.clean(123)
    # thẻ HTML giữ nguyên chữ (client hiển thị bằng text node, không phải HTML)
    assert {:ok, "<b>hi</b>"} = Chat.clean("<b>hi</b>")
  end

  test "filter: từ cấm (không phân biệt hoa thường) thay bằng ***; danh sách mặc định rỗng" do
    assert Chat.filter("Đồ XẤU và Bad quá", ["xấu", "bad"]) == "Đồ *** và *** quá"
    assert Chat.filter("không đổi") == "không đổi"
  end

  test "mute có thời hạn, vĩnh viễn (tới khi khởi động lại), unmute; không phân biệt hoa thường" do
    assert Chat.muted_until("Abc1") == nil
    :ok = Chat.mute("abc1", 10)
    assert Chat.muted_until("ABC1") > System.os_time(:second)
    :ok = Chat.mute("Abc1", nil)
    assert Chat.muted_until("abc1") == :infinity
    :ok = Chat.unmute("ABC1")
    assert Chat.muted_until("abc1") == nil
    :ok = Chat.mute("abc1", -1)
    assert Chat.muted_until("abc1") == nil
  end
end

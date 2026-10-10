defmodule HacLong.TienLen.Text do
  @moduledoc """
  Chữ tiếng Việt cho bàn Tiến Lên (lấy từ `TienLenWeb.Text` của repo gốc, "coin" đổi thành
  "vàng"): lý do lỗi, tên bộ bài, tên tới trắng.
  """

  @reasons %{
    empty: "Hãy chọn lá bài",
    duplicate_cards: "Lá bài bị trùng",
    invalid_combination: "Bộ bài không hợp lệ",
    does_not_match: "Không cùng loại với bài trên bàn",
    too_low: "Chưa đủ lớn để chặn",
    cannot_chop: "Không được chặt bằng bộ này",
    must_include_card: "Nước đầu phải có lá bắt buộc",
    cannot_pass_on_lead: "Đang đi đầu, không được bỏ lượt",
    not_four_pair: "Chỉ bốn đôi thông mới chặt ngoài lượt được",
    no_chop_target: "Không có gì để chặt",
    game_over: "Ván đã kết thúc",
    not_in_game: "Bạn không có trong ván này",
    not_active: "Bạn đã xong ván này",
    not_your_turn: "Chưa đến lượt bạn",
    not_your_cards: "Bạn không có những lá này",
    not_host: "Chỉ chủ phòng mới được bắt đầu",
    not_enough_players: "Cần ít nhất 2 người",
    game_in_progress: "Ván đang diễn ra",
    room_full: "Phòng đã đủ 4 người",
    room_not_found: "Phòng không tồn tại",
    not_in_room: "Bạn không ở trong phòng này",
    no_game: "Chưa có ván nào",
    unknown_command: "Lệnh không hợp lệ",
    too_many_rooms: "Máy chủ đang quá nhiều phòng, hãy thử lại sau",
    unknown_request: "Yêu cầu không hợp lệ",
    not_enough_coins: "Cần ít nhất 2 người có đủ 10× tiền cược",
    invalid_stake: "Tiền cược phải là 0 hoặc từ 10 trở lên",
    not_found: "Không tìm thấy",
    insufficient_coins: "Không đủ vàng để trừ",
    invalid_amount: "Số vàng không hợp lệ",
    kicked: "Bạn đã bị mời ra khỏi phòng này",
    invalid_message: "Tin nhắn phải có 1–200 ký tự",
    muted: "Bạn đang bị cấm chat",
    chat_too_fast: "Bạn gửi tin quá nhanh, chờ vài giây",
    invalid_target: "Chỉ ném được vào ghế có người khác",
    throw_too_fast: "Từ từ, 3 giây mới ném được một lần",
    cannot_afford: "Bạn không đủ vàng",
    blow_too_fast: "Thổi từ từ thôi, 3 giây một lần",
    not_enough_coins_to_join: "Bạn không đủ vàng cho mức cược của phòng này",
    bots_need_free_room: "Máy chơi chỉ có ở phòng chơi vui (cược 0)",
    too_many_spectators: "Phòng đã đủ 20 người xem",
    busy: "Có người trong bàn đang bận, thử lại sau",
    settle_failed: "Lỗi trả vàng, chưa ai mất gì"
  }

  @types %{
    single: "Lá lẻ",
    pair: "Đôi",
    triple: "Sám",
    straight: "Sảnh",
    four_of_a_kind: "Tứ quý",
    three_pair: "Ba đôi thông",
    four_pair: "Bốn đôi thông"
  }

  @instant %{
    four_twos: "Tứ quý heo",
    six_pairs: "Sáu đôi",
    dragon: "Sảnh rồng",
    four_threes: "Tứ quý 3"
  }

  @doc "Lời báo cho một lý do lỗi."
  def reason({:error, reason}), do: reason(reason)
  def reason(reason) when is_atom(reason), do: Map.get(@reasons, reason, "Có lỗi xảy ra")
  def reason(_), do: "Có lỗi xảy ra"

  @doc "Tên các loại bộ và tới trắng (gửi kèm dữ liệu client)."
  def types, do: @types
  def instants, do: @instant
end

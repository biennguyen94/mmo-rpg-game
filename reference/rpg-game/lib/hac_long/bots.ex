defmodule HacLong.Bots do
  @moduledoc """
  Người chơi AI (Phase 16, câu 16-A): `RULES.bots.count` bot (mặc định 20) chạy trên server như người chơi
  thật (đi lại, đánh quái, lên cấp, cộng điểm, mặc đồ rơi ra, về Nhà hồi máu, nói vài câu trong chat).

  - Mỗi bot là một tài khoản `bot_01`… (`users.role = "bot"`, mật khẩu ngẫu nhiên, không đăng nhập được
    bằng tay) có nhân vật thật trong database; điều khiển bởi `HacLong.Bots.Bot` qua `Session`.
  - Không đánh dấu là bot. Không lên bảng xếp hạng (`HacLong.Leaderboard` bỏ tài khoản bot), không nhận
    giao dịch, từ chối cược đấu; vẫn thách đấu (đấu trường) được.
  - Số bot chỉnh bằng biến môi trường `HL_BOTS` (0 là tắt); test tắt sẵn.
  """
  use Supervisor
  import Ecto.Query

  alias HacLong.{Accounts, Repo}
  alias HacLong.Accounts.User
  alias HacLong.Game.Data

  @names ~w(Hắc_Phong Bạch_Vân Thanh_Tùng Minh_Khang Gia_Huy Bảo_Ngọc Thu_Hà Đức_Anh Quốc_Bảo Hải_Đăng
            Ngọc_Lan Phong_Vũ Tuấn_Kiệt Lam_Anh Khánh_Linh Hoàng_Long Mộc_Miên Trúc_Lâm Vân_Phi Tiểu_Hổ
            Kim_Ngân Thiên_Ân Bích_Thủy Hùng_Cường Mai_Chi Tùng_Lâm Diệp_Anh Hà_My Trọng_Nghĩa An_Nhiên)
  @classes ~w(dk dw elf mg)

  def start_link(_), do: Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Số bot sẽ chạy (cấu hình `:bots, :count`, mặc định `RULES.bots.count`)."
  def count do
    Application.get_env(:hac_long, :bots, [])[:count] || Data.rules().bots.count
  end

  @impl true
  def init(:ok) do
    children = [
      {Registry, keys: :unique, name: HacLong.Bots.Registry},
      {DynamicSupervisor, name: HacLong.Bots.Sup, strategy: :one_for_one},
      {Task, &start_bots/0}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp start_bots do
    for i <- 1..count()//1, count() > 0 do
      uid = ensure_account(i)
      name = @names |> Enum.at(rem(i - 1, length(@names))) |> String.replace("_", " ")
      cls = Enum.at(@classes, rem(i - 1, 4))
      DynamicSupervisor.start_child(HacLong.Bots.Sup, {HacLong.Bots.Bot, {uid, name, cls}})
    end
  end

  @doc "Tài khoản bot thứ `i` (tạo nếu chưa có), trả về id."
  def ensure_account(i) do
    username = "bot_" <> String.pad_leading("#{i}", 2, "0")

    user =
      Repo.get_by(User, username: username) ||
        case Accounts.register(%{
               "username" => username,
               "password" => Base.encode64(:crypto.strong_rand_bytes(18))
             }) do
          {:ok, u} -> u
          {:error, _} -> Repo.get_by!(User, username: username)
        end

    if user.role != "bot",
      do: Repo.update_all(from(u in User, where: u.id == ^user.id), set: [role: "bot"])

    user.id
  end

  @doc "Tài khoản có phải bot không."
  def bot?(user_id) when is_integer(user_id),
    do: Repo.exists?(from u in User, where: u.id == ^user_id and u.role == "bot")

  def bot?(_), do: false
end

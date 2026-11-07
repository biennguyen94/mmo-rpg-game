defmodule HacLong.Repo.Migrations.AddSecurityQuestion do
  use Ecto.Migration

  # CHANGE_REASON: DECISIONS "Câu hỏi bảo mật": lúc đăng ký chọn câu hỏi bảo mật và trả lời (lưu dạng băm), quên mật
  # khẩu thì trả lời đúng là đặt được mật khẩu mới, không cần chờ quản trị. Cột để trống với tài khoản cũ.
  def change do
    alter table(:users) do
      add :security_question, :string
      add :security_answer_hash, :string
    end
  end
end

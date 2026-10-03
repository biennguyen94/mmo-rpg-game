defmodule Mix.Tasks.Mu.Chat do
  @shortdoc "Quản trị chat: cấm / bỏ cấm chat, gửi thông báo hệ thống (P2-12)"
  @moduledoc """
  Chạy trên server đang chạy (cấm chat giữ trong RAM của server, không lưu DB):

      # server phải có tên node: elixir --sname mu -S mix phx.server
      mix mu.chat mute TenNhanVat 30 --node mu@host     # cấm 30 phút (bỏ số phút = tới khi server khởi động lại)
      mix mu.chat unmute TenNhanVat --node mu@host
      mix mu.chat system "Bảo trì lúc 3h sáng" --node mu@host

  Bản release: `bin/mu rpc 'Mu.Chat.mute("TenNhanVat", 30)'` (tương tự `unmute/1`, `system/1`).
  Cùng user hệ điều hành với server (dùng chung `~/.erlang.cookie`).
  """
  use Mix.Task

  @impl true
  def run(args) do
    {o, rest, _} = OptionParser.parse(args, strict: [node: :string])
    node = String.to_atom(o[:node] || Mix.raise("thiếu --node (vd. mu@#{host()})"))
    {:ok, _} = Node.start(:"mu_chat_admin_#{System.unique_integer([:positive])}", :shortnames)
    Node.connect(node) || Mix.raise("không kết nối được #{node}")

    {fun, call_args} =
      case rest do
        ["mute", name] -> {:mute, [name, nil]}
        ["mute", name, minutes] -> {:mute, [name, String.to_integer(minutes)]}
        ["unmute", name] -> {:unmute, [name]}
        ["system", text] -> {:system, [text]}
        _ -> Mix.raise("dùng: mix mu.chat mute|unmute|system ... --node NODE")
      end

    case :rpc.call(node, Mu.Chat, fun, call_args) do
      :ok -> Mix.shell().info("#{fun}: xong")
      other -> Mix.raise("#{fun}: #{inspect(other)}")
    end
  end

  defp host, do: :inet.gethostname() |> elem(1)
end

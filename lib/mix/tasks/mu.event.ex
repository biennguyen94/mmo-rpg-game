defmodule Mix.Tasks.Mu.Event do
  @shortdoc "Quản trị event thế giới: bật / tắt Golden Invasion, world boss (P6-M5)"
  @moduledoc """
  Chạy trên server đang chạy (event sống trong RAM của server):

      # server phải có tên node: elixir --sname mu -S mix phx.server
      mix mu.event start golden_invasion --node mu@host
      mix mu.event start world_boss --node mu@host
      mix mu.event stop world_boss --node mu@host

  Bản release: `bin/mu rpc 'Mu.WorldEvents.start("world_boss")'` (tương tự `stop/1`).
  Cùng user hệ điều hành với server (dùng chung `~/.erlang.cookie`).
  """
  use Mix.Task

  @impl true
  def run(args) do
    {o, rest, _} = OptionParser.parse(args, strict: [node: :string])
    node = String.to_atom(o[:node] || Mix.raise("thiếu --node (vd. mu@#{host()})"))

    {fun, kind} =
      case rest do
        [cmd, kind] when cmd in ~w(start stop) -> {String.to_atom(cmd), kind}
        _ -> Mix.raise("dùng: mix mu.event start|stop golden_invasion|world_boss --node NODE")
      end

    {:ok, _} = Node.start(:"mu_event_admin_#{System.unique_integer([:positive])}", :shortnames)
    Node.connect(node) || Mix.raise("không kết nối được #{node}")

    case :rpc.call(node, Mu.WorldEvents, fun, [kind]) do
      :ok -> Mix.shell().info("#{fun} #{kind}: xong")
      other -> Mix.raise("#{fun} #{kind}: #{inspect(other)}")
    end
  end

  defp host, do: :inet.gethostname() |> elem(1)
end

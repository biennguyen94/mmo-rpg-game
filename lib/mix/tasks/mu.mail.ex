defmodule Mix.Tasks.Mu.Mail do
  @shortdoc "Quản trị hộp thư: gửi mail hệ thống / quà cho một nhân vật (P2-13)"
  @moduledoc """
  Gửi qua server đang chạy (để người chơi đang online thấy badge ngay):

      # server phải có tên node: elixir --sname mu -S mix phx.server
      mix mu.mail send TenNhanVat "Bảo trì server" "Bảo trì lúc 3h sáng mai" --node mu@host
      mix mu.mail send TenNhanVat "Quà Tết" "Tặng 1000 Zen" --zen 1000 --node mu@host
      mix mu.mail send TenNhanVat "Quà" "Potion" --item hp_potion_small --quantity 10 --node mu@host

  Có `--zen` hoặc `--item` thì loại `GIFT`, không thì `SYSTEM`. Bản release:
  `bin/mu rpc 'Mu.Mail.deliver_to_name("Ten", %{kind: "GIFT", title: "...", zen: 1000})'`.
  """
  use Mix.Task

  @impl true
  def run(args) do
    {o, rest, _} =
      OptionParser.parse(args,
        strict: [node: :string, zen: :integer, item: :string, quantity: :integer]
      )

    node =
      String.to_atom(
        o[:node] || Mix.raise("thiếu --node (vd. mu@#{:inet.gethostname() |> elem(1)})")
      )

    {name, title, body} =
      case rest do
        ["send", name, title, body] ->
          {name, title, body}

        ["send", name, title] ->
          {name, title, ""}

        _ ->
          Mix.raise(
            ~s(dùng: mix mu.mail send TEN "tiêu đề" ["nội dung"] [--zen N] [--item ID --quantity N] --node NODE)
          )
      end

    gift? = o[:zen] != nil or o[:item] != nil

    attrs =
      %{kind: if(gift?, do: "GIFT", else: "SYSTEM"), title: title, body: body, zen: o[:zen] || 0}
      |> then(
        &if(o[:item], do: Map.merge(&1, %{item: o[:item], quantity: o[:quantity] || 1}), else: &1)
      )

    {:ok, _} = Node.start(:"mu_mail_admin_#{System.unique_integer([:positive])}", :shortnames)
    Node.connect(node) || Mix.raise("không kết nối được #{node}")

    case :rpc.call(node, Mu.Mail, :deliver_to_name, [name, attrs]) do
      {:ok, m} -> Mix.shell().info("đã gửi mail #{m.id} (#{attrs.kind}) cho #{name}")
      other -> Mix.raise("không gửi được: #{inspect(other)}")
    end
  end
end

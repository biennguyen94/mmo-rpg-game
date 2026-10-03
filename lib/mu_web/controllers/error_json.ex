defmodule MuWeb.ErrorJSON do
  @moduledoc "Lỗi HTTP chưa bắt (404, 500...) trả JSON."

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end

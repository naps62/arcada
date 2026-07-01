defmodule OQueMudouWeb.AdminNav do
  @moduledoc """
  `on_mount` hook shared by every admin LiveView (`live_view_admin`). Tracks the
  live navigation path in `@current_path` so the `:admin` layout's sidebar can
  highlight the active section without each page wiring it up. See issue #29.
  """
  import Phoenix.LiveView, only: [attach_hook: 4]
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, nil)
      |> attach_hook(:admin_nav_path, :handle_params, &set_current_path/3)

    {:cont, socket}
  end

  defp set_current_path(_params, uri, socket) do
    {:cont, assign(socket, :current_path, URI.parse(uri).path)}
  end
end

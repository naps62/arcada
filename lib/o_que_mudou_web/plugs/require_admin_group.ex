defmodule OQueMudouWeb.Plugs.RequireAdminGroup do
  @moduledoc """
  Defense-in-depth gate for the `/admin` area. The real boundary is at the edge:
  Traefik routes `/admin` through the `authelia` forwardAuth middleware (and the
  VPN ACL), so both the HTTP render and the LiveView WebSocket upgrade are gated
  there. Authelia passes the authenticated user's groups back in the
  `Remote-Groups` header; this plug re-checks it on the HTTP request so a
  misconfigured edge can't silently expose the page.

  Config (`config/config.exs`):

      config :o_que_mudou, :admin, group: "oqm-admin", bypass: false

  `bypass: true` (dev only) skips the header check so the page is reachable
  without Authelia in front.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    cfg = Application.get_env(:o_que_mudou, :admin, [])

    cond do
      cfg[:bypass] -> conn
      authorized?(conn, cfg[:group] || "oqm-admin") -> conn
      true -> conn |> send_resp(403, "Forbidden") |> halt()
    end
  end

  defp authorized?(conn, group) do
    conn
    |> get_req_header("remote-groups")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.member?(group)
  end
end

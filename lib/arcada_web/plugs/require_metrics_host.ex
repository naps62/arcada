defmodule ArcadaWeb.Plugs.RequireMetricsHost do
  @moduledoc """
  Host guard for the Prometheus `/metrics` endpoint. `PromEx.Plug` is mounted in
  the endpoint (before the router), so unlike `/admin` it has no pipeline to
  protect it and would otherwise answer on **any** host — including the public
  `arcada.naps.pt` once it goes live. This plug 404s `/metrics` on any host other
  than the configured private host (issue #11).

  Internal Prometheus/Alloy scrapes hit the container directly over the
  dokploy-network, addressed by container **IP** (e.g. `10.0.1.130:4000`), so
  the request `Host` is an IP literal rather than a public FQDN. We must let
  those through, otherwise the scrape 404s and every app metric goes dark. So
  the guard permits the configured host **and any IP-literal host**: a request
  routed to the public `arcada.naps.pt` always carries that name (Traefik routes
  by `Host()`), never a bare IP, so allowing IP hosts cannot expose `/metrics`
  publicly.

  Only the exact `/metrics` request path is guarded; every other request passes
  through untouched (this plug runs for every request in the endpoint). It raises
  `Phoenix.Router.NoRouteError` — a plain 404, not 403 — so the endpoint is
  byte-for-byte indistinguishable from an unknown path on the public host and
  never confirms `/metrics` exists there.

  Config (`config/config.exs` + `config/runtime.exs`):

      config :arcada, :metrics, host: "arcada.example.internal"

  When `host` is `nil`/unset (dev, test, single-host deployments) the check is
  skipped, so `/metrics` stays reachable on any host.
  """

  @metrics_path "/metrics"

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: @metrics_path} = conn, _opts) do
    cfg = Application.get_env(:arcada, :metrics, [])

    cond do
      is_nil(cfg[:host]) -> conn
      conn.host == cfg[:host] -> conn
      ip_literal?(conn.host) -> conn
      true -> raise Phoenix.Router.NoRouteError, conn: conn, router: ArcadaWeb.Router
    end
  end

  def call(conn, _opts), do: conn

  # The internal Alloy scrape addresses the container by IP, so conn.host is an
  # IP literal ("10.0.1.130"). Public traffic always arrives with a hostname.
  defp ip_literal?(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end
end

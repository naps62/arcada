defmodule ArcadaWeb.Plugs.RequireMetricsHost do
  @moduledoc """
  Host guard for the Prometheus `/metrics` endpoint. `PromEx.Plug` is mounted in
  the endpoint (before the router), so unlike `/admin` it has no pipeline to
  protect it and would otherwise answer on **any** host — including the public
  `arcada.naps.pt` once it goes live. This plug 404s `/metrics` on any host other
  than the configured private host, mirroring `RequireAdminHost` (issue #11).

  Internal Prometheus/Alloy scrapes hit the container directly over the
  dokploy-network (not via a public hostname), so they are unaffected.

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
      true -> raise Phoenix.Router.NoRouteError, conn: conn, router: ArcadaWeb.Router
    end
  end

  def call(conn, _opts), do: conn
end

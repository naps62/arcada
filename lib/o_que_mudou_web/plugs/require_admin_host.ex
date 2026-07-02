defmodule OQueMudouWeb.Plugs.RequireAdminHost do
  @moduledoc """
  Host-based guard for the `/admin` area, and the **sole** in-app admin gate.
  Admin is served **only** on the private VPN host (`arcada.example.internal`); on the
  public host (`arcada.naps.pt`) the admin surface must not exist at all.
  Reaching the VPN host is the access boundary — there is no further auth.

  On a non-matching host it raises `Phoenix.Router.NoRouteError`, so the response
  is byte-for-byte identical to any genuinely unknown path (a normal 404). We
  deliberately do **not** 403: a 403 would confirm the admin surface exists on
  the public host.

  This guards the HTTP request (the dead render). The LiveView WebSocket upgrade
  is gated at the edge (Traefik host routing + VPN ACL); without a successful
  dead render on the admin host there is no valid session to connect a socket
  with.

  Config (`config/config.exs` + `config/runtime.exs`):

      config :o_que_mudou, :admin, host: "arcada.example.internal"

  When `host` is `nil`/unset (dev, test, single-host deployments) the check is
  skipped, so `/admin` stays reachable on any host (e.g. `localhost`).
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    cfg = Application.get_env(:o_que_mudou, :admin, [])

    cond do
      is_nil(cfg[:host]) -> conn
      conn.host == cfg[:host] -> conn
      true -> raise Phoenix.Router.NoRouteError, conn: conn, router: OQueMudouWeb.Router
    end
  end
end

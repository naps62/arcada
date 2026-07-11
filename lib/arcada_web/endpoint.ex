defmodule ArcadaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :arcada

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  # secure: on in prod, off in dev/test (http localhost) — see :secure_cookies.
  @session_options [
    store: :cookie,
    key: "_arcada_key",
    signing_salt: "xSzix2Dy",
    same_site: "Lax",
    secure: Application.compile_env(:arcada, :secure_cookies, false)
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :arcada,
    gzip: false,
    only: ArcadaWeb.static_paths()

  # Kaffy ships its CSS/JS in its own dep (deps/kaffy/priv/static/assets) and
  # references them at /kaffy/assets/...; it has no Plug.Static of its own, so
  # the host must serve them. Releases bundle deps' priv, so this works in prod.
  plug Plug.Static,
    at: "/kaffy",
    from: :kaffy,
    gzip: false,
    only: ~w(assets)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :arcada
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  # Prometheus metrics are NOT served on this public endpoint. They live on a
  # dedicated internal Bandit listener (Arcada.Application, port :metrics_port),
  # un-routed publicly and scraped by Alloy over the dokploy overlay (#11, #46).

  # Recover the real client IP from the Cloudflare → Traefik forwarded headers
  # (issue #43). Placed before RequestId/Telemetry so logs and request metrics
  # carry the true visitor IP, not the Traefik container. No-op unless
  # `config :arcada, :remote_ip` is set (see the plug + config/runtime.exs).
  plug ArcadaWeb.Plugs.RemoteIp

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ArcadaWeb.Router
end

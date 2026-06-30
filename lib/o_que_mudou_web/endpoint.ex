defmodule OQueMudouWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :o_que_mudou

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_o_que_mudou_key",
    signing_salt: "xSzix2Dy",
    same_site: "Lax"
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
    from: :o_que_mudou,
    gzip: false,
    only: OQueMudouWeb.static_paths()

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
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :o_que_mudou
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  # Expose Prometheus metrics at /metrics. Placed before RequestId/Telemetry
  # so scrapes don't generate request logs or skew request metrics.
  plug PromEx.Plug, prom_ex_module: OQueMudou.PromEx

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug OQueMudouWeb.Router
end

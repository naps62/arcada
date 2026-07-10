import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/arcada start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :arcada, ArcadaWeb.Endpoint, server: true
end

# Host on which the /admin area is served. On a two-host deploy the public host
# (arcada.naps.pt) must NOT expose /admin at all — only the private VPN host
# (arcada.example.internal) does. RequireAdminHost 404s admin paths on any other host.
# Unset (dev/test/single-host) → admin reachable on every host. Deep-merges the
# host into the :admin keyword list from config.exs.
if admin_host = System.get_env("ADMIN_HOST") do
  config :arcada, :admin, host: admin_host
  # /metrics lives on the same private VPN host as /admin. Reuse ADMIN_HOST so
  # RequireMetricsHost 404s it on the public host (issue #11); METRICS_HOST
  # overrides if they ever need to diverge.
  config :arcada, :metrics, host: System.get_env("METRICS_HOST") || admin_host
end

# Real client IP behind Cloudflare → Traefik (issue #43). Makes conn.remote_ip
# the actual visitor instead of the Traefik container peer. Enabled by setting
# REMOTE_IP=true (or any of the tuning vars below); unset → the plug is a no-op,
# so dev/test/single-host keep the socket peer. Read in every env so a release
# can flip it without a rebuild.
#
# Two strategies, chosen by REMOTE_IP_HEADERS:
#
#   x-forwarded-for (default) — walk X-Forwarded-For, trusting the proxy CIDRs in
#     :proxies (Cloudflare ranges + the Docker/Traefik overlay, via
#     ArcadaWeb.RemoteIpProxies.default/0). Safe even if the origin is NOT yet
#     firewalled to Cloudflare: a direct-to-origin request has an untrusted peer,
#     so remote_ip stays put and cannot be spoofed to an arbitrary value.
#
#   cf-connecting-ip — trust Cloudflare's single CF-Connecting-IP header. Simpler,
#     but SPOOFABLE unless the origin is locked to Cloudflare IP ranges (the
#     CF-lock in the arcada-public-golive plan). Prefer this only post go-live:
#       REMOTE_IP_HEADERS=cf-connecting-ip
#
# Overrides: REMOTE_IP_HEADERS / REMOTE_IP_PROXIES / REMOTE_IP_CLIENTS are
# comma-separated lists; REMOTE_IP_PROXIES replaces the built-in default proxy set.
remote_ip_enabled? =
  System.get_env("REMOTE_IP") == "true" ||
    Enum.any?(
      ~w(REMOTE_IP_HEADERS REMOTE_IP_PROXIES REMOTE_IP_CLIENTS),
      &System.get_env/1
    )

if remote_ip_enabled? do
  csv = fn var, default ->
    case System.get_env(var) do
      nil -> default
      v -> String.split(v, ",", trim: true) |> Enum.map(&String.trim/1)
    end
  end

  config :arcada, :remote_ip,
    headers: csv.("REMOTE_IP_HEADERS", ["x-forwarded-for"]),
    proxies: csv.("REMOTE_IP_PROXIES", ArcadaWeb.RemoteIpProxies.default()),
    clients: csv.("REMOTE_IP_CLIENTS", [])
end

# Umami analytics (privacy-preserving, cookieless). Both vars must be set for
# the tracking tag to render (see ArcadaWeb.Layouts.umami/0). Read in every
# env so it works for releases; left unset in dev and the VPN deployment.
config :arcada, :umami,
  script_url: System.get_env("UMAMI_SCRIPT_URL"),
  website_id: System.get_env("UMAMI_WEBSITE_ID")

# Summarizer (Claude API). Set ANTHROPIC_API_KEY to use the `:api` adapter;
# without it the adapter returns {:error, :missing_api_key} and the manual
# default applies. Read at runtime in every env so it works for releases + dev.
if api_key = System.get_env("ANTHROPIC_API_KEY") do
  config :arcada, Arcada.Summarizer.Adapters.Api, api_key: api_key

  # If a key is present, default to the api adapter unless overridden.
  if System.get_env("SUMMARIZER_ADAPTER") in [nil, "api"] do
    config :arcada, Arcada.Summarizer, adapter: :api
  end
end

# SSH adapter — runs `claude -p` on a remote host that already has the CLI
# authenticated (no ANTHROPIC_API_KEY in the app). Set SUMMARIZER_SSH_HOST (and
# SUMMARIZER_ADAPTER=ssh) to use it.
if ssh_host = System.get_env("SUMMARIZER_SSH_HOST") do
  config :arcada, Arcada.Summarizer.Adapters.Ssh,
    host: ssh_host,
    user: System.get_env("SUMMARIZER_SSH_USER") || "claude",
    identity_file: System.get_env("SUMMARIZER_SSH_IDENTITY") || "/app/.ssh/id_ed25519",
    claude_cmd: System.get_env("SUMMARIZER_CLAUDE_CMD") || "claude -p --output-format json",
    model: System.get_env("SUMMARIZER_SSH_MODEL") || "claude-cli"
end

# Explicit adapter override always wins (:manual | :api | :local | :ssh).
if adapter = System.get_env("SUMMARIZER_ADAPTER") do
  config :arcada, Arcada.Summarizer, adapter: String.to_atom(adapter)
end

# Embeddings-based section ranking for oversized diplomas. An env fallback for the
# admin-page setting: point it at an OpenAI-compatible embeddings server (llama.cpp
# `llama-server --embeddings`, Ollama, …), e.g. on a local GPU box. Without it (and
# with no admin override) oversized acts head-truncate as before.
if base_url = System.get_env("EMBEDDINGS_BASE_URL") do
  config :arcada, Arcada.Summarizer.Embeddings,
    base_url: base_url,
    model: System.get_env("EMBEDDINGS_MODEL") || "bge-m3"
end

# Global summarize worker pool. Per-provider limits (`providers.max_concurrency`,
# issue #22) throttle each provider *within* this pool — SSH stays at 1 via its
# provider limit, API providers fan out up to theirs — so this is just the overall
# ceiling across all providers, no longer tied to any single adapter. Size it to
# the total parallelism you want. Override with SUMMARIZER_CONCURRENCY.
summarize_concurrency =
  case System.get_env("SUMMARIZER_CONCURRENCY") do
    nil -> 10
    v -> String.to_integer(v)
  end

# Deep-merges into the Oban queues list from config.exs (keeps default/scrape).
config :arcada, Oban, queues: [summarize: summarize_concurrency]

# Public-user email via Resend (verification + password reset). Set RESEND_API_KEY
# to send for real; without it the mailer stays on the compile-time adapter and
# delivery no-ops (safe default). MAILER_FROM_EMAIL must be on a Resend-verified
# domain. Read at runtime so it works for releases; guarded so dev/test keep the
# Local/Test adapters from config/*.exs.
# Reply-To for account emails. We send from a no-reply address; set this to a
# real monitored inbox (e.g. a SimpleLogin alias) so replies reach you. Read in
# every env so it also shows in the dev mailbox preview. Unset → plain no-reply.
if reply_to = System.get_env("MAILER_REPLY_TO") do
  config :arcada, :mailer_reply_to, reply_to
end

# Cloudflare Turnstile keys for the signup bot check. Both must be set for the
# widget to render and be verified; missing either keeps Turnstile disabled.
# Read in every env so you can smoke-test with Cloudflare's test keys locally.
turnstile_site_key = System.get_env("TURNSTILE_SITE_KEY")
turnstile_secret_key = System.get_env("TURNSTILE_SECRET_KEY")

if turnstile_site_key && turnstile_secret_key do
  config :arcada, ArcadaWeb.Turnstile,
    site_key: turnstile_site_key,
    secret_key: turnstile_secret_key
end

if config_env() == :prod do
  if resend_key = System.get_env("RESEND_API_KEY") do
    config :arcada, Arcada.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: resend_key
  end

  if from_email = System.get_env("MAILER_FROM_EMAIL") do
    config :arcada,
           :mailer_from,
           {System.get_env("MAILER_FROM_NAME") || "Arcada", from_email}
  end
end

if config_env() == :prod do
  # Fail closed on the admin gate. `/admin`, `/admin/db` (raw-DB CRUD) and
  # `/admin/jobs` have no in-app auth — RequireAdminHost is the only gate, and it
  # passes everything when the host is unset. In prod that would silently expose
  # the entire admin + DB surface on the public host, so require ADMIN_HOST at
  # boot instead of defaulting open (issue #55).
  System.get_env("ADMIN_HOST") ||
    raise """
    environment variable ADMIN_HOST is missing.
    /admin has no in-app authentication and is gated only by request host; without
    ADMIN_HOST the admin + raw-DB surface is reachable on every host. Set it to the
    private admin host (e.g. arcada.example.internal) so admin paths 404 elsewhere.
    """

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :arcada, Arcada.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :arcada, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # The app is served on several hosts (public `arcada.naps.pt` + the private VPN
  # host `arcada.example.internal`, issue #37). Phoenix defaults `check_origin: true`,
  # which allows only PHX_HOST — so LiveView WebSocket upgrades would be rejected
  # on every other host. Allow PHX_HOST, ADMIN_HOST, and any extra comma-separated
  # hosts in CHECK_ORIGIN_HOSTS (both http/https).
  check_origins =
    [host, System.get_env("ADMIN_HOST")]
    |> Enum.concat(String.split(System.get_env("CHECK_ORIGIN_HOSTS") || "", ",", trim: true))
    |> Enum.map(&(&1 && String.trim(&1)))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.flat_map(&["https://#{&1}", "http://#{&1}"])
    |> Enum.uniq()

  config :arcada, ArcadaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: check_origins,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :arcada, ArcadaWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :arcada, ArcadaWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end

# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :o_que_mudou,
  ecto_repos: [OQueMudou.Repo],
  generators: [timestamp_type: :utc_datetime]

# DRE scraper. apiVersion hashes rotate on each DRE deploy. These are just the
# seed/fallback values from recon (docs/endpoints.md): the client self-heals at
# runtime — on `hasApiVersionChanged: true` it re-derives the current hash over
# HTTP (ApiVersionResolver) and retries — so they no longer need manual updates.
config :o_que_mudou, OQueMudou.Scraper.Client,
  base_url: "https://diariodarepublica.pt",
  list_api_version: "1ZNbiINloOPj8IhEJxM3QA",
  detail_api_version: "f6iEozloG7S5uAiM9ydqeQ"

# Summarizer providers are configured at runtime in the DB (see issue #20 and
# the /admin page); the active provider+model drives auto-summarize. There's no
# compile-time adapter selection any more.

# SSH adapter — runs `claude -p` on a remote host that has the CLI logged in
# (no ANTHROPIC_API_KEY needed in the app). host/identity come from env at
# runtime (runtime.exs); these are the static defaults.
config :o_que_mudou, OQueMudou.Summarizer.Adapters.Ssh,
  user: "claude",
  claude_cmd: "claude -p --output-format json",
  model: "claude-cli",
  ssh_extra: [
    "-o",
    "StrictHostKeyChecking=accept-new",
    "-o",
    "BatchMode=yes",
    "-o",
    "ConnectTimeout=20",
    # Avoid known_hosts writes (the app's HOME may be /nonexistent); keeps ssh
    # diagnostics off stdout so the JSON parse stays clean.
    "-o",
    "UserKnownHostsFile=/dev/null"
  ]

# Adaptive text cap for the summarizer prompt (see `OQueMudou.Summarizer.ContextWindow`,
# issue #18). The cap on how much act text is fed to the model is derived from the
# target model's context window instead of a fixed char count — leaving the module
# defaults active covers this deployment (Claude ~1M, everything else 200k). Override
# any knob here (or the DB `max_text_chars`) if the model line-up changes:
#
#   config :o_que_mudou, OQueMudou.Summarizer.ContextWindow,
#     default_window: 200_000,
#     windows: %{"claude-sonnet-4" => 1_000_000, "claude-opus-4" => 1_000_000, "claude-cli" => 1_000_000},
#     reserve_fraction: 0.2,
#     chars_per_token: 3.5

# Embeddings ranking for oversized diplomas (see `OQueMudou.Summarizer.Embeddings`).
# `base_url` is left unset here → ranking is off and oversized acts fall back to
# head-truncation. Set it (admin page or EMBEDDINGS_BASE_URL) to an OpenAI-compatible
# embeddings server — llama.cpp `llama-server --embeddings`, Ollama, etc. — to keep
# the operative articles instead of whatever lands in the first N chars.
#
# Default model is bge-m3: multilingual (1024-dim), the right fit for Portuguese
# legal text. nomic-embed-text is English-centric and additionally needs task
# prefixes for good retrieval — if you point at nomic, also set:
#   query_prefix: "search_query: ", document_prefix: "search_document: "
# (left empty for bge-m3, which doesn't use them).
config :o_que_mudou, OQueMudou.Summarizer.Embeddings,
  model: "bge-m3",
  timeout: 30_000

# Configures Oban (background jobs + daily cron).
# The DRE scraper runs on a daily cron; see docs/PLAN.md.
config :o_que_mudou, Oban,
  repo: OQueMudou.Repo,
  queues: [default: 10, scrape: 1, summarize: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # Série I publishes on business days only (no weekends) — mostly the morning,
    # but same-day Suplementos land through the day. Poll every 2 hours across the
    # working day so supplements/late editions are picked up the same day.
    # 07:00–19:00 UTC (~08:00–20:00 Lisbon in summer); UTC avoids a tzdata dep.
    # IngestWorker defaults to today's date and is idempotent, so re-runs are free.
    {Oban.Plugins.Cron, crontab: [{"0 7-19/2 * * 1-5", OQueMudou.Scraper.IngestWorker}]}
  ]

# Admin area (/admin): edge-gated by Authelia (Remote-Groups header) + VPN ACL.
# `bypass: true` (dev) skips the in-app group check. See issue #19.
config :o_que_mudou, :admin, group: "oqm-admin", bypass: false

# Prometheus /metrics: served by PromEx.Plug in the endpoint (no router
# pipeline), so RequireMetricsHost host-guards it. `host: nil` (dev/test) leaves
# it reachable on any host; prod sets it from ADMIN_HOST in runtime.exs. See #11.
config :o_que_mudou, :metrics, host: nil

# Kaffy raw-DB admin (mounted at /admin/db, behind the same Authelia/VPN gate).
# Schemas are auto-discovered from the Repo; see OQueMudouWeb.Router.
config :kaffy,
  otp_app: :o_que_mudou,
  ecto_repo: OQueMudou.Repo,
  router: OQueMudouWeb.Router,
  admin_title: "o-que-mudou DB",
  hide_dashboard: false,
  # Restyle Kaffy to our palette + a denser layout (see OQueMudouWeb.KaffyTheme).
  extensions: [OQueMudouWeb.KaffyTheme]

# Configures the endpoint
config :o_que_mudou, OQueMudouWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: OQueMudouWeb.ErrorHTML, json: OQueMudouWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: OQueMudou.PubSub,
  live_view: [signing_salt: "6KZMKO7g"]

# SEO indexing gate. Off by default so the pre-launch site stays out of search
# engines even if briefly reachable; flip to true (SEO_INDEXABLE=true in
# runtime.exs) on go-live. See OQueMudouWeb.SEO and issue #36.
config :o_que_mudou, :seo, indexable: false

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  o_que_mudou: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  o_que_mudou: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger. The console formatter is the human-readable
# default for dev/test; prod overrides the default handler with a JSON
# formatter (see config/prod.exs) so logs land structured in Loki.
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Prometheus metrics (PromEx). Dashboards are not auto-uploaded; metrics are
# exposed at /metrics via PromEx.Plug and scraped by Prometheus over the
# dokploy-network.
config :o_que_mudou, OQueMudou.PromEx,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Public-user email (account verification + password reset), sent via the
# OQueMudou.Mailer / Swoosh. Swoosh's HTTP calls go through Req (already a dep)
# rather than pulling in hackney/Finch. The per-environment adapter is set in
# dev/test/prod: Local mailbox preview in dev, Test collector in test, Resend
# in prod (API key via env — see config/runtime.exs).
config :swoosh, api_client: Swoosh.ApiClient.Req

# From address for account emails. Overridden at runtime in prod
# (MAILER_FROM_EMAIL / MAILER_FROM_NAME) — the Resend sender must be on a
# verified domain. The dev/test default is only ever seen in the mailbox preview.
config :o_que_mudou, :mailer_from, {"Arcada", "nao-responder@arcada.local"}

# Global cap on new signups per UTC day. Protects the Resend free quota
# (100 emails/day) since every registration sends a confirmation email.
# Kept below 100 to leave headroom for password-reset / re-confirm mails.
config :o_que_mudou, :daily_signup_cap, 80

# Cloudflare Turnstile bot check on the signup form. Disabled by default
# (no keys) — dev/test skip the widget and verification. Prod keys come from
# env at runtime (see config/runtime.exs).
config :o_que_mudou, OQueMudouWeb.Turnstile, site_key: nil, secret_key: nil

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

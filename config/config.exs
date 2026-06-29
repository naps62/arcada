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

# DRE scraper. apiVersion hashes rotate on each DRE deploy; these are the
# last-known-good values from recon (docs/endpoints.md). The list action is
# load-bearing; the detail action degrades gracefully when its hash drifts.
config :o_que_mudou, OQueMudou.Scraper.Client,
  base_url: "https://diariodarepublica.pt",
  list_api_version: "1ZNbiINloOPj8IhEJxM3QA",
  # Re-derived 2026-06-28 (rotated from CMMMWnKmYa2KRIcPVVt9uQ). See issue for
  # self-healing re-derivation so this stops needing manual updates on DRE deploys.
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

# Embeddings ranking for oversized diplomas (see `OQueMudou.Summarizer.Embeddings`).
# `base_url` is left unset here → ranking is off and oversized acts fall back to
# head-truncation. Set it (admin page or EMBEDDINGS_BASE_URL) to an OpenAI-compatible
# embeddings server — llama.cpp `llama-server --embeddings`, Ollama, etc. — to keep
# the operative articles instead of whatever lands in the first N chars.
config :o_que_mudou, OQueMudou.Summarizer.Embeddings,
  model: "nomic-embed-text",
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

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

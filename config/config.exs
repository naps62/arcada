# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :arcada,
  ecto_repos: [Arcada.Repo],
  generators: [timestamp_type: :utc_datetime]

# DRE scraper. apiVersion hashes rotate on each DRE deploy. These are just the
# seed/fallback values from recon (docs/endpoints.md): the client self-heals at
# runtime — on `hasApiVersionChanged: true` it re-derives the current hash over
# HTTP (ApiVersionResolver) and retries — so they no longer need manual updates.
config :arcada, Arcada.Scraper.Client,
  base_url: "https://diariodarepublica.pt",
  list_api_version: "1ZNbiINloOPj8IhEJxM3QA",
  detail_api_version: "f6iEozloG7S5uAiM9ydqeQ"

# Summarizer providers are configured at runtime in the DB (see issue #20 and
# the /admin page); the active provider+model drives auto-summarize. There's no
# compile-time adapter selection any more.

# SSH adapter — runs `claude -p` on a remote host that has the CLI logged in
# (no ANTHROPIC_API_KEY needed in the app). host/identity come from env at
# runtime (runtime.exs); these are the static defaults.
config :arcada, Arcada.Summarizer.Adapters.Ssh,
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

# Adaptive text cap for the summarizer prompt (see `Arcada.Summarizer.ContextWindow`,
# issue #18). The cap on how much act text is fed to the model is derived from the
# target model's context window instead of a fixed char count — leaving the module
# defaults active covers this deployment (Claude ~1M, everything else 200k). Override
# any knob here (or the DB `max_text_chars`) if the model line-up changes:
#
#   config :arcada, Arcada.Summarizer.ContextWindow,
#     default_window: 200_000,
#     reserve_fraction: 0.2,
#     chars_per_token: 3.5
config :arcada, Arcada.Summarizer.ContextWindow,
  windows: %{
    # Claude (SSH `claude -p`) exposes ~1M tokens; acts summarise whole.
    "claude-sonnet-4" => 1_000_000,
    "claude-opus-4" => 1_000_000,
    "claude-cli" => 1_000_000,
    # AMALIA-9B (local llama.cpp, `owned_by: llama-swap`) runs at `-c 32768` on
    # the GPU box, but its tokenizer is dense on PT legal text (~1.7 chars/token)
    # and llama-server reserves context for the generated summary — so the safe
    # *input* budget is far below the raw window. This is an EFFECTIVE budget, not
    # amalia's real context: 14_600 here → a ~40.9k-char cap (via the 3.5
    # chars_per_token derivation), validated against the largest acts (~228k raw,
    # ranked down to fit). Keep in step with the `-c` value in the llama-swap
    # config on the GPU host — raising -c lets you raise this proportionally.
    "amalia" => 14_600
  }

# Cost target the ranker trims act text down to, distinct from the safety cap
# above (issue #41). Ranking fills this budget with the most change-relevant
# sections even when the act fits under the cap, keeping token spend down. The DB
# `target_text_chars` overrides it; default (120k chars) lives in `Arcada.Admin`.
#
#   config :arcada, Arcada.Summarizer, target_text_chars: 120_000

# Embeddings ranking for oversized diplomas (see `Arcada.Summarizer.Embeddings`).
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
#
# `min_relevance_score` (optional, unset = off) drops sections below that cosine
# similarity even when the budget has room — trims obviously-irrelevant chunks for
# cost. Model-specific; tune against real scores before enabling (issue #41).
config :arcada, Arcada.Summarizer.Embeddings,
  model: "bge-m3",
  timeout: 30_000

# Configures Oban (background jobs + daily cron).
# The DRE scraper runs on a daily cron; see docs/PLAN.md.
config :arcada, Oban,
  repo: Arcada.Repo,
  queues: [default: 10, scrape: 1, summarize: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # Série I publishes on business days only (no weekends) — mostly the morning,
    # but same-day Suplementos land through the day. Poll every 2 hours across the
    # working day so supplements/late editions are picked up the same day.
    # 07:00–19:00 UTC (~08:00–20:00 Lisbon in summer); UTC avoids a tzdata dep.
    # IngestWorker defaults to today's date and is idempotent, so re-runs are free.
    {Oban.Plugins.Cron,
     crontab: [
       {"0 7-19/2 * * 1-5", Arcada.Scraper.IngestWorker},
       # Drain the backlog of un-summarized acts (historical backfill + any daily
       # summary whose job failed out) a batch at a time. Cheap no-op query once
       # everything is summarized. See Arcada.Summarizer.SummarySweeper.
       {"*/5 * * * *", Arcada.Summarizer.SummarySweeper}
     ]}
  ]

# Admin area (/admin): served only on the private VPN host. `host` (set from
# ADMIN_HOST in runtime.exs) makes RequireAdminHost 404 /admin on the public
# host; `host: nil` (dev/test) leaves it reachable on any host. The VPN is the
# access boundary — no in-app auth. See issues #19, #37.
config :arcada, :admin, host: nil

# Prometheus /metrics: served by PromEx.Plug in the endpoint (no router
# pipeline), so RequireMetricsHost host-guards it. `host: nil` (dev/test) leaves
# it reachable on any host; prod sets it from ADMIN_HOST in runtime.exs. See #11.
config :arcada, :metrics, host: nil

# Kaffy raw-DB admin (mounted at /admin/db, behind the same Authelia/VPN gate).
# Schemas are auto-discovered from the Repo; see ArcadaWeb.Router.
config :kaffy,
  otp_app: :arcada,
  ecto_repo: Arcada.Repo,
  router: ArcadaWeb.Router,
  admin_title: "arcada DB",
  hide_dashboard: false,
  # Restyle Kaffy to our palette + a denser layout (see ArcadaWeb.KaffyTheme).
  extensions: [ArcadaWeb.KaffyTheme]

# Configures the endpoint
config :arcada, ArcadaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ArcadaWeb.ErrorHTML, json: ArcadaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Arcada.PubSub,
  live_view: [signing_salt: "6KZMKO7g"]

# Real client IP behind the Cloudflare → Traefik proxy chain (issue #43). Off by
# default (nil → the ArcadaWeb.Plugs.RemoteIp plug is a no-op, so dev/test and
# any no-proxy setup keep the socket peer as conn.remote_ip). Prod sets it from
# env in config/runtime.exs. The value maps straight to RemoteIp plug options
# (:headers, :proxies, :clients).
config :arcada, :remote_ip, nil

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  arcada: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  arcada: [
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
config :arcada, Arcada.PromEx,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

# Per-caller rate limits for semantic search (issue #32). Two tiers, two windows
# each. `:anon` is deliberately loose (a load valve + signup nudge, not a bot
# wall — real IP keying awaits #43); `:user` rewards a verified account with far
# more headroom. Over budget, search degrades to FTS-only, never fails. Tune here
# without a code change.
config :arcada, Arcada.RateLimit,
  anon: [per_minute: 20, per_day: 200],
  user: [per_minute: 120, per_day: 2_000]

# Recency boost for hybrid search ranking. After semantic+FTS fusion (RRF), each
# act's score is multiplied by a bounded factor in [1, 1+recency_beta]: newest
# acts get the full boost, older ones decay toward 1.0 with `recency_half_life_days`.
# Bounded on purpose — recency only breaks near-ties; a relevance gap wider than a
# factor of (1+beta) still wins, and a recent-but-irrelevant act can't be lifted
# into the results. `recency_beta: 0.0` disables it (pure relevance). ~1.6% RRF per
# rank near the top, so beta 0.15 lets recency swing ~9 ranks; drop it for a gentler
# nudge. Tunable here without a code change.
config :arcada, Arcada.Search,
  recency_beta: 0.15,
  recency_half_life_days: 180,
  # Relevance floor on the semantic leg (see `Arcada.Search.above_relevance_floor/1`):
  # drop acts whose cosine is below `max(min_relevance_score, relevance_ratio × top)`.
  # Relative-to-top because bge-m3's scores swing by query (weak ~0.39, strong ~0.64),
  # so no fixed cutoff fits both; `min_relevance_score` is the nonsense-query backstop
  # (nothing clears it → no results). FTS/exact-term matches are never dropped (they
  # re-enter via the FTS list). `relevance_ratio: 0.0` disables the floor.
  relevance_ratio: 0.90,
  min_relevance_score: 0.33

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Public-user email (account verification + password reset), sent via the
# Arcada.Mailer / Swoosh. Swoosh's HTTP calls go through Req (already a dep)
# rather than pulling in hackney/Finch. The per-environment adapter is set in
# dev/test/prod: Local mailbox preview in dev, Test collector in test, Resend
# in prod (API key via env — see config/runtime.exs).
config :swoosh, api_client: Swoosh.ApiClient.Req

# From address for account emails. Overridden at runtime in prod
# (MAILER_FROM_EMAIL / MAILER_FROM_NAME) — the Resend sender must be on a
# verified domain. The dev/test default is only ever seen in the mailbox preview.
config :arcada, :mailer_from, {"Arcada", "nao-responder@arcada.local"}

# Global cap on new signups per UTC day. Protects the Resend free quota
# (100 emails/day) since every registration sends a confirmation email.
# Kept below 100 to leave headroom for password-reset / re-confirm mails.
config :arcada, :daily_signup_cap, 80

# Cloudflare Turnstile bot check on the signup form. Disabled by default
# (no keys) — dev/test skip the widget and verification. Prod keys come from
# env at runtime (see config/runtime.exs).
config :arcada, ArcadaWeb.Turnstile, site_key: nil, secret_key: nil

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

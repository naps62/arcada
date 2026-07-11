# Deploy — arcada on `example.internal` (VPN-gated)

Private, VPN-only deployment via **Dokploy** on `example.internal`, per `docs/PLAN.md`
(audience: private only; no app-level auth — network gating only).

## What's in the repo

- **`Dockerfile`** — multi-stage Elixir release (`hexpm/elixir:1.18.4-erlang-27.3.4.14`
  builder → `debian:bookworm-slim` runtime). Runs `mix assets.deploy` + `mix release`.
- **`rel/overlays/bin/{server,migrate}`**, **`lib/arcada/release.ex`** — release entrypoints.
- **`config/runtime.exs`** — reads `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`,
  `PORT`, `ANTHROPIC_API_KEY`, `SUMMARIZER_ADAPTER` at boot.

The image is verified end-to-end locally: builds, `bin/migrate` applies all
migrations, the server boots and serves the register, and Oban runs the daily
cron `{"0 9 * * 1-5", Arcada.Scraper.IngestWorker}` with queues
`[default, scrape, summarize]`.

## Required env vars (set in Dokploy → app → Environment)

| Var | Value |
|---|---|
| `DATABASE_URL` | `ecto://<user>:<pass>@<pg-host>/arcada_prod` (Dokploy-managed Postgres) |
| `SECRET_KEY_BASE` | `mix phx.gen.secret` (64+ bytes) |
| `PHX_HOST` | canonical public hostname for generated URLs (e.g. `arcada.naps.pt`) |
| `ADMIN_HOST` | private VPN host still served (e.g. `arcada.example.internal`); now only seeds `CHECK_ORIGIN_HOSTS` for LiveView. Optional — gates nothing (`/admin` is Authelia-edge-gated, `/metrics` is on its own un-routed port; #46). Drop it once `n62.casa` is retired. |
| `PHX_SERVER` | `true` |
| `PORT` | `4000` |
| `ANTHROPIC_API_KEY` | Claude API key — **secret**; enables the `:api` summarizer adapter |
| `SUMMARIZER_ADAPTER` | optional; `manual` (default) · `api` · `ssh` · `local`. With an API key present, defaults to `api`. |
| `RESEND_API_KEY` | **secret**; enables real delivery of account emails (verification + password reset) via Resend. Without it the mailer no-ops. |
| `MAILER_FROM_EMAIL` | sender for account emails — must be on a Resend-verified domain (e.g. `nao-responder@oqm.example`) |
| `MAILER_FROM_NAME` | optional; display name for the sender (defaults to `Arcada`) |
| `MAILER_REPLY_TO` | optional; a real monitored inbox (e.g. a SimpleLogin alias) that replies to account emails are directed to. Unset = plain no-reply. |

> Without a configured summarizer the app stays on the `manual` adapter
> (no external calls); ingestion still runs and acts appear unsummarized.

> Public-user email uses Swoosh's Resend adapter in prod (over Req; no extra
> HTTP client dep). In dev, mail is captured at `/dev/mailbox`; in tests it's
> collected in-process. Without `RESEND_API_KEY` in prod, delivery no-ops
> safely — registration still works but no confirmation email is sent.

### Summarizer adapter options

| Adapter | How it summarizes | Needs |
|---|---|---|
| `manual` (default) | nothing automatic — human backfill via console | — |
| `api` | Claude API (Sonnet 4.6), structured output | `ANTHROPIC_API_KEY` |
| `ssh` | SSHes to a host with the `claude` CLI and runs `claude -p` | SSH key + `SUMMARIZER_SSH_HOST` |
| `local` | placeholder (not implemented) | — |

**`ssh` adapter env / setup** (no `ANTHROPIC_API_KEY` needed — auth lives on the
remote machine where `claude` is already logged in):

| Var | Value |
|---|---|
| `SUMMARIZER_ADAPTER` | `ssh` |
| `SUMMARIZER_SSH_HOST` | host with the `claude` CLI (e.g. `192.0.2.10`) |
| `SUMMARIZER_SSH_USER` | SSH user (e.g. `naps62`) — default `claude` |
| `SUMMARIZER_SSH_IDENTITY` | private-key path in the container (default `/app/.ssh/id_ed25519`) |
| `SUMMARIZER_CLAUDE_CMD` | default `claude -p --output-format json`; use an **absolute path** to `claude` if it isn't in the non-login `PATH` |

Wiring steps:
1. The runtime image already ships `openssh-client`.
2. Generate a keypair; mount the **private key** into the container at
   `SUMMARIZER_SSH_IDENTITY` (Dokploy → app → Advanced → Volumes/Mounts, or a
   build secret) with `chmod 600`.
3. Add the **public key** to `~<user>/.ssh/authorized_keys` on the SSH host.
4. The act text is base64-piped to the remote `claude` over SSH — no act content
   touches a shell. `claude -p` reads the prompt from stdin and returns the JSON
   envelope the adapter parses.

## Dokploy setup

1. **Project + Postgres**: create a Dokploy project; add a Postgres service;
   create database `arcada_prod`. Copy its connection string into `DATABASE_URL`.
2. **Application**: source = this Gitea repo (`yolo/arcada`), build type =
   **Dockerfile**. Set the env vars above (mark `ANTHROPIC_API_KEY` / `SECRET_KEY_BASE` as secrets).
3. **Migrations on deploy**: set the pre-deploy/start command to run
   `/app/bin/migrate` before `/app/bin/server` (or run `bin/migrate` once via a
   Dokploy command). The container's default `CMD` is `/app/bin/server`.
4. **Deploy** and watch logs for `Running ArcadaWeb.Endpoint`.

## Two-host setup — public `arcada.naps.pt` + private `arcada.example.internal` (issue #37)

**LIVE since 2026-07-09.** The app is served publicly on `arcada.naps.pt`
(Cloudflare-proxied) and privately on `arcada.example.internal` (VPN).

| Host | Audience | Entrypoint | Edge middlewares | `/admin*` |
|---|---|---|---|---|
| `arcada.example.internal` | private (VPN) | `websecure` (:443) | `vpn-allowlist` | served (VPN only) |
| `arcada.naps.pt` | public | `websecure-public` (:8443) | `cloudflare-only` (+ `authelia` on `/admin*`) | Authelia SSO (#46) |

**How the public host works.** The Dokploy Traefik defines a dedicated
`websecure-public` entrypoint on `:8443` that trusts Cloudflare forwarded headers
and carries **no** default VPN ACL (the `:443 websecure` entrypoint applies
`vpn-allowlist` to every router by default). The `arcada.naps.pt`
domain row is pointed at that entrypoint (`customEntrypoint: websecure-public`)
with the `cloudflare-only@file` ipAllowList so only Cloudflare edge IPs can reach
the origin (no direct-to-origin bypass). Cloudflare proxies `arcada.naps.pt`
(orange-cloud A record → origin `:8443`). `PHX_HOST=arcada.naps.pt` so canonical
URLs / OG tags / sitemap advertise the public host; on the public host `/admin*`
is gated by Authelia SSO at the edge (see below), and `CHECK_ORIGIN_HOSTS` lists
both hosts so LiveView upgrades work on either. `REMOTE_IP=true` (X-Forwarded-For)
recovers the real visitor IP behind Cloudflare. `ADMIN_HOST=arcada.example.internal`
gates nothing now — `/admin` is Authelia-edge-gated and `/metrics` lives on its own
un-routed internal port (#46); `ADMIN_HOST` only seeds `CHECK_ORIGIN_HOSTS`.

**The one non-Dokploy gotcha:** a public app must live on the `:8443`
`websecure-public` entrypoint. Left on the default `:443` entrypoint it inherits
the VPN ACL and Cloudflare-proxied traffic 404s (wrong entrypoint) — this is set
per-domain-row via `customEntrypoint`, not an app env var.

- **`arcada.example.internal`** is the private VPN host carrying the
  `vpn-allowlist` IP-allowlist middleware (per the `*.example.internal`
  model), and is `PHX_HOST`. It is the only host where `/admin*` exists. The VPN
  IP-allowlist is the access boundary — `/admin` needs no further auth (see the
  Admin section below).
- **`arcada.naps.pt`** is open to the public for `/` (no auth gate — the sign-in/up
  UI is hidden, issue #53, but the register is world-readable). `/admin*` on this
  host is gated by Authelia SSO. It is hardened by: the `authelia` edge middleware
  on `/admin*`, `cloudflare-only` origin lock, and a `noindex`-free but `/admin`-
  `/users`-`/dev`-disallowing `robots.txt`.

  **Authelia gate for `/admin` (#46):** the shared `authelia` middleware
  forward-auths to Authelia at `192.0.2.20:9091`. Authelia picks its portal from
  the request's cookie domain, so a `naps.pt` session-cookie entry was added
  (`authelia_url` reuses the existing public portal `auth.example.com` — legal
  because that host is itself under `naps.pt`, so it can set a `Domain=naps.pt`
  cookie). An access-control rule scopes `arcada.naps.pt ^/admin` to
  `group:admin` / two-factor, with an explicit `deny` so the `one_factor`
  default policy can't admit any other authenticated user. The cookie is
  `naps.pt`-wide (shared SSO across `*.naps.pt`, `HttpOnly`+`Secure`+`SameSite=Lax`).

Dokploy domain rows (per host):

| Host | Path | Middlewares |
|---|---|---|
| `arcada.example.internal` | `/` | `vpn-allowlist` |
| `arcada.example.internal` | `/admin` | `vpn-allowlist` |
| `arcada.naps.pt` | `/` | `cloudflare-only` |
| `arcada.naps.pt` | `/admin` | `cloudflare-only`, `authelia` |

`robots.txt` disallows `/admin*` (SEO issue).

## VPN gating (no public exposure)

The app has **no auth** — access control is the network. Do **not** attach a
public Traefik domain / Let's Encrypt cert. Options:

- **Preferred:** bind the published port to the VPN interface only (e.g.
  WireGuard/Tailscale address), not `0.0.0.0`. In Dokploy, expose the container
  port on the host's VPN IP, or front it with Traefik bound to the VPN network.
- Or restrict the Traefik router to the VPN CIDR (IP allowlist middleware).
- Confirm from off-VPN that the host/port is unreachable, and on-VPN that
  `http://oqm.example.internal/` serves the register.

## Operations

- **Manual scrape** (Dokploy app shell):
  ```
  /app/bin/arcada rpc 'Arcada.Scraper.IngestWorker.new(%{date: "2026-06-24"}) |> Oban.insert()'
  ```
- **Historical backfill** (ingest-only; the sweeper summarizes afterwards):
  ```
  /app/bin/arcada rpc 'Arcada.Scraper.backfill_since(~D[2025-07-03])'   # → today
  /app/bin/arcada rpc 'Arcada.Scraper.backfill(~D[2025-06-01], ~D[2025-06-30])'
  # or in a dev/console env:
  mix dre.scrape --backfill --months 12
  ```
  Enqueues one ingest job per **business day**, newest first, each `summarize:
  false` — the acts land without summaries and the **SummarySweeper** picks them
  up. Idempotent; safe to re-run.
- **Summary sweeper** (`Arcada.Summarizer.SummarySweeper`, cron `*/5 * * * *`):
  every 5 min it enqueues a summarize job for up to `batch` (default 100) acts
  that have no summary — historical backlog *and* any daily summary whose job
  failed. Low priority (daily jumps ahead) and deduped per act, so it never
  floods or double-queues. The real pace is the provider's `max_concurrency`
  (SSH/local = 1). A summary that fails is simply retried on a later tick, so the
  register self-heals until every act is summarized; once it is, the tick is a
  single cheap query. Tune the batch with
  `config :arcada, Arcada.Summarizer.SummarySweeper, batch: N`.
- **Manual summary backfill** (manual adapter): use
  `Arcada.Summarizer.create_summary/2` from `bin/arcada remote`.
- The ingest cron runs automatically every 2 hours, 07:00–19:00 UTC on weekdays
  (`0 7-19/2 * * 1-5`), once the release is up. Idempotent, so re-runs are free.

## Admin page — `/admin` (issues #19, #20)

Manage summarizer **providers** and pick the **active** provider+model used by
the daily cron / auto-summarize. Providers are DB rows (CRUD at `/admin`), kind
= `anthropic` | `openai` (OpenAI-compatible: llmbase, ollama, synthetic.new) |
`ssh` (a CLI like `claude -p` over SSH). Per act, `/admin/acts/:id` lists every
summary with its provider/model, lets you trigger a run against any
provider+model, and publish one as the canonical (public) summary.

Active changes apply on the **next** summarize job.

**Per-provider concurrency (issue #22).** Each provider sets its own **Max
concurrency** (admin form; SSH defaults to 1, API providers to 5). Summarize jobs
share a single Oban queue whose width is just the global pool ceiling
(`SUMMARIZER_CONCURRENCY`, default 10), but each job checks how many jobs for its
provider are already running and defers (Oban snooze) when the provider is at its
limit. So SSH stays at one concurrent session while API providers fan out, and
switching or editing a provider re-tunes its limit live — no restart, no queue
churn.

**Long diplomas.** Two `/admin` knobs, distinct on purpose (issue #41):

- **Safety cap** (`max_text_chars`) — the overflow ceiling. Left empty it's
  derived adaptively from the active model's context window
  (`Arcada.Summarizer.ContextWindow` — ~2.8M chars on the ~1M-context Claude,
  ~560k on the conservative default).
- **Cost target** (`target_text_chars`, default 120k) — how much text each act is
  actually trimmed to. With an embeddings server, ranking fills this budget with
  the most change-relevant sections even when the act fits under the cap, so token
  spend stays down. It's clamped to never exceed the cap.

With an embeddings server for section
ranking, when an act
exceeds the **target**, instead of truncating its opening the summarizer keeps the most
change-relevant sections (articles) and drops trailing annexes; an optional
`min_relevance_score` also drops sections below a cosine threshold. Without a
ranker, an act that still fits under the **cap** is sent whole (only genuine
giants past the ceiling head-truncate). Point it at any
OpenAI-compatible `/v1/embeddings` server — llama.cpp `llama-server --embeddings`
or Ollama on a GPU box — via the admin field or `EMBEDDINGS_BASE_URL`
(+ `EMBEDDINGS_MODEL`, default `bge-m3`: multilingual, right for Portuguese). The
server must be reachable from the app over the VPN/LAN. Unset → oversized acts
head-truncate as before. (nomic-embed is English-centric and needs `query_prefix`/
`document_prefix` task prefixes — see the config comment; bge-m3 needs neither.)

Seeding (first deploy): create at least one provider and set it active, e.g.
via `bin/arcada rpc` —
`Arcada.Providers.create_provider/1` then `Arcada.Admin.update_settings/1`
with `active_provider_id`/`active_model`.

Admin has **no in-app auth** — the access boundary is the edge, and it differs
per host (see the two-host section above):

1. **Public `arcada.naps.pt`.** The `/admin` domain row carries the `authelia`
   forwardAuth middleware, so Authelia SSO (`group:admin` / two-factor) gates every
   `/admin*` request before it reaches the app (#46).
2. **Private `arcada.example.internal`.** The router carries only the
   `vpn-allowlist` IP-allowlist, so any VPN client is trusted; `/admin` needs no
   further auth there.

There is no in-app host guard or group check — reaching `/admin` means the edge
already authorized the request. `RequireAdminHost` was removed in #46. If a future
deploy needs finer per-user admin auth, that's a separate change.

## Observability (Loki + Prometheus)

**Logs (Loki).** In `prod` the Logger default handler uses
`LoggerJSON.Formatters.Basic`, so the app writes one JSON object per line to
stdout (`{"time","severity","message","metadata"}`). Alloy ships the
container's stdout to Loki, where `| json` parses the fields. Oban job
lifecycle is logged via `Oban.Telemetry.attach_default_logger/1`. `LOG_LEVEL`
(env) overrides the level at boot. Query in Grafana:

```
{service="arcada-app"} | json | severity="error"
```

**Metrics (Prometheus).** PromEx (`Arcada.PromEx`) exposes `GET /metrics` via
`PromEx.Plug`, served on a **dedicated internal Bandit listener** on its own port
(`config :arcada, :metrics_port`, default `9091`; started in `Arcada.Application`,
only when the web server runs). It is **not** served on the public `:4000`
endpoint — so it is un-routed publicly and needs no host guard. Plugins:
Application, Beam, Phoenix, Ecto, Oban, PhoenixLiveView (~60 metric families, all
prefixed `arcada_prom_ex_*`). (PromEx's own `metrics_server` isn't used — it needs
`plug_cowboy` and the app runs on Bandit.)

Scraping is **opt-in via container labels**, not a static target. Grafana
Alloy (`infra/alloy` → `config.alloy`) discovers Docker containers and only
scrapes ones carrying these labels, hitting `<container>:<prometheus.port>/metrics`
over `dokploy-network` by container IP (bypasses Traefik — no ACL, no TLS, no
hostname). The scrape port **must** match the metrics listener:

```dockerfile
# Dockerfile (runner stage) — already set:
LABEL prometheus.scrape="true"
LABEL prometheus.port="9091"
```

This mirrors how other scraped services (e.g. `example-service`) opt in, so no edits to
the shared Alloy config are needed when this app is redeployed. Metrics land in
Prometheus prefixed `arcada_prom_ex_*` within ~15s of a deploy.

Because the scrape addresses the container by IP over the overlay, there is no
hostname in the request — this is why metrics must live on their own un-gated
port (the old `/metrics` on `:4000` was host-gated to `ADMIN_HOST` and so the
IP-addressed scrape always 404'd; issue #46). Nothing exposes this port
publicly, and only the dokploy overlay can reach a container IP.

Dashboards aren't auto-uploaded (`grafana: :disabled`); import the bundled
PromEx dashboards manually against the `prometheus` datasource if wanted.

## Local verification (what was run before shipping)

```
docker build -t oqm:deploy-test .
# postgres container, then:
docker run --rm --network <net> -e DATABASE_URL=... -e SECRET_KEY_BASE=... oqm:deploy-test /app/bin/migrate
docker run -d --network <net> -p 4011:4000 -e DATABASE_URL=... -e SECRET_KEY_BASE=... \
  -e PHX_HOST=localhost -e PHX_SERVER=true oqm:deploy-test
curl http://127.0.0.1:4011/    # -> 200, register UI
```

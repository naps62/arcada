# Deploy — o-que-mudou on `example.internal` (VPN-gated)

Private, VPN-only deployment via **Dokploy** on `example.internal`, per `docs/PLAN.md`
(audience: private only; no app-level auth — network gating only).

## What's in the repo

- **`Dockerfile`** — multi-stage Elixir release (`hexpm/elixir:1.17.3-erlang-25.3.2.8`
  builder → `debian:bullseye-slim` runtime). Runs `mix assets.deploy` + `mix release`.
- **`rel/overlays/bin/{server,migrate}`**, **`lib/o_que_mudou/release.ex`** — release entrypoints.
- **`config/runtime.exs`** — reads `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`,
  `PORT`, `ANTHROPIC_API_KEY`, `SUMMARIZER_ADAPTER` at boot.

The image is verified end-to-end locally: builds, `bin/migrate` applies all
migrations, the server boots and serves the register, and Oban runs the daily
cron `{"0 9 * * 1-5", OQueMudou.Scraper.IngestWorker}` with queues
`[default, scrape, summarize]`.

## Required env vars (set in Dokploy → app → Environment)

| Var | Value |
|---|---|
| `DATABASE_URL` | `ecto://<user>:<pass>@<pg-host>/o_que_mudou_prod` (Dokploy-managed Postgres) |
| `SECRET_KEY_BASE` | `mix phx.gen.secret` (64+ bytes) |
| `PHX_HOST` | canonical public hostname for generated URLs (e.g. `arcada.naps.pt`) |
| `ADMIN_HOST` | host on which `/admin*` is served (e.g. `arcada.example.internal`). On any other host admin paths 404. Unset → admin reachable on every host (single-host / dev). |
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
   create database `o_que_mudou_prod`. Copy its connection string into `DATABASE_URL`.
2. **Application**: source = this Gitea repo (`yolo/o-que-mudou`), build type =
   **Dockerfile**. Set the env vars above (mark `ANTHROPIC_API_KEY` / `SECRET_KEY_BASE` as secrets).
3. **Migrations on deploy**: set the pre-deploy/start command to run
   `/app/bin/migrate` before `/app/bin/server` (or run `bin/migrate` once via a
   Dokploy command). The container's default `CMD` is `/app/bin/server`.
4. **Deploy** and watch logs for `Running OQueMudouWeb.Endpoint`.

## Two-host setup — public `arcada.naps.pt` + private `arcada.example.internal` (issue #37)

The app is served on **two** hosts by the same Dokploy application (add both as
domain rows on the app):

| Host | Audience | Edge middlewares | `/admin*` |
|---|---|---|---|
| `arcada.naps.pt` | public *(closed for now)* | `authelia` | **404** (host guard) |
| `arcada.example.internal` | private (VPN) | `vpn-allowlist` | Authelia-gated, served |

- **`arcada.naps.pt`** is the canonical public host (`PHX_HOST`). It is **not
  open yet** — until go-public it sits behind the `authelia` forwardAuth
  middleware so only authenticated users reach it. Drop the `authelia`
  middleware from this row when ready to open to the world. It never serves
  `/admin`: `ADMIN_HOST=arcada.example.internal` makes `RequireAdminHost` raise a 404
  (identical to any unknown path — no 403, which would confirm the surface).
- **`arcada.example.internal`** is the private VPN host carrying the
  `vpn-allowlist` IP-allowlist middleware (per the `*.example.internal`
  model). It is the only host where `/admin*` exists; `/admin` additionally
  routes through `authelia` + the in-app `RequireAdminGroup` check (see the
  Admin section below).

Dokploy domain rows (per host, path `/`):

| Host | Path | Middlewares |
|---|---|---|
| `arcada.naps.pt` | `/` | `authelia` |
| `arcada.example.internal` | `/` | `vpn-allowlist` |
| `arcada.example.internal` | `/admin` | `authelia`, `vpn-allowlist` |

Set `ADMIN_HOST=arcada.example.internal` in the app environment so the in-app host guard
matches the edge routing. `robots.txt` disallows `/admin*` (SEO issue).

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

- **Manual scrape / backfill** (Dokploy app shell):
  ```
  /app/bin/o_que_mudou rpc 'OQueMudou.Scraper.IngestWorker.new(%{date: "2026-06-24"}) |> Oban.insert()'
  /app/bin/o_que_mudou rpc 'OQueMudou.Scraper.backfill(~D[2026-06-01], ~D[2026-06-27])'
  ```
- **Manual summary backfill** (manual adapter): use
  `OQueMudou.Summarizer.create_summary/2` from `bin/o_que_mudou remote`.
- The ingest cron runs automatically every 2 hours, 07:00–19:00 UTC on weekdays
  (`0 7-19/2 * * 1-5`), once the release is up. Idempotent, so re-runs are free.

## Admin page — `/admin` (issues #19, #20)

Manage summarizer **providers** and pick the **active** provider+model used by
the daily cron / auto-summarize. Providers are DB rows (CRUD at `/admin`), kind
= `anthropic` | `openai` (OpenAI-compatible: llmbase, ollama, synthetic.new) |
`ssh` (a CLI like `claude -p` over SSH). Per act, `/admin/acts/:id` lists every
summary with its provider/model, lets you trigger a run against any
provider+model, and publish one as the canonical (public) summary.

Active changes apply on the **next** summarize job. Oban queue concurrency is
fixed at boot, so it doesn't re-tune when you switch the active provider.

**Long diplomas.** The `/admin` page also sets the prompt cap (`max_text_chars`,
default 80k) and an optional embeddings server for section ranking: when an act
exceeds the cap, instead of truncating its opening the summarizer keeps the most
change-relevant sections (articles) and drops trailing annexes. Point it at any
OpenAI-compatible `/v1/embeddings` server — llama.cpp `llama-server --embeddings`
or Ollama on a GPU box — via the admin field or `EMBEDDINGS_BASE_URL`
(+ `EMBEDDINGS_MODEL`, default `bge-m3`: multilingual, right for Portuguese). The
server must be reachable from the app over the VPN/LAN. Unset → oversized acts
head-truncate as before. (nomic-embed is English-centric and needs `query_prefix`/
`document_prefix` task prefixes — see the config comment; bge-m3 needs neither.)

Seeding (first deploy): create at least one provider and set it active, e.g.
via `bin/o_que_mudou rpc` —
`OQueMudou.Providers.create_provider/1` then `OQueMudou.Admin.update_settings/1`
with `active_provider_id`/`active_model`.

Admin lives **only** on the private host `arcada.example.internal` (see the two-host
section above). Gated in three layers (fails closed):

1. **Host (Traefik + app).** `/admin*` is not routed on the public host at all,
   and `RequireAdminHost` 404s it in-app if `conn.host != ADMIN_HOST`. So the
   surface simply doesn't exist off the VPN host.
2. **Edge (Traefik).** Add a Dokploy domain row: `host=arcada.example.internal`,
   `path=/admin`, middlewares `[authelia, vpn-allowlist]`. This
   routes `/admin` through Authelia (and the VPN ACL); the path-specific router
   wins over the catch-all `/` row.
3. **App (defense in depth).** `OQueMudouWeb.Plugs.RequireAdminGroup` checks the
   `Remote-Groups` header (set by Authelia) for `oqm-admin`. Config:
   `config :o_que_mudou, :admin, group: "oqm-admin", bypass: false`. Dev sets
   `bypass: true`.

Authelia setup: create group `oqm-admin`, add the operator user to it, and add an
access-control rule for `arcada.example.internal/admin` requiring group `oqm-admin`.

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

**Metrics (Prometheus).** PromEx (`OQueMudou.PromEx`) exposes
`GET /metrics` via `PromEx.Plug` (mounted before `Plug.Telemetry`, so scrapes
aren't logged). Plugins: Application, Beam, Phoenix, Ecto, Oban,
PhoenixLiveView (~60 metric families, all prefixed `o_que_mudou_prom_ex_*`).

Scraping is **opt-in via container labels**, not a static target. Grafana
Alloy (`infra/alloy` → `config.alloy`) discovers Docker containers and only
scrapes ones carrying these labels, hitting `<container>:<prometheus.port>/metrics`
over `dokploy-network` (bypasses Traefik — no ACL, no TLS):

```dockerfile
# Dockerfile (runner stage) — already set:
LABEL prometheus.scrape="true"
LABEL prometheus.port="4000"
```

This mirrors how other scraped services (e.g. `example-service`) opt in, so no edits to
the shared Alloy config are needed when this app is redeployed. Metrics land in
Prometheus prefixed `o_que_mudou_prom_ex_*` within ~15s of a deploy.

`/metrics` is *also* reachable at `https://oqm.example.internal/metrics`, but it
inherits the host's `vpn-allowlist@file` ipAllowList (the router
rule is `Host()`-only, no path split) — so it's already restricted to the
VPN/docker ranges, same as the rest of the app. No metrics-specific Traefik
config is needed. Prefer the internal `dokploy-network` target above.

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

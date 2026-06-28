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
| `PHX_HOST` | the internal/VPN hostname (e.g. `oqm.example.internal`) |
| `PHX_SERVER` | `true` |
| `PORT` | `4000` |
| `ANTHROPIC_API_KEY` | Claude API key — **secret**; enables the `:api` summarizer adapter |
| `SUMMARIZER_ADAPTER` | optional; `manual` (default) · `api` · `ssh` · `local`. With an API key present, defaults to `api`. |

> Without a configured summarizer the app stays on the `manual` adapter
> (no external calls); ingestion still runs and acts appear unsummarized.

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

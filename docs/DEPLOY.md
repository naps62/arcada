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
| `SUMMARIZER_ADAPTER` | optional; `manual` (default) or `api`. With a key present, defaults to `api`. |

> Without `ANTHROPIC_API_KEY` the summarizer stays on the `manual` adapter
> (no external calls); ingestion still runs and acts appear unsummarized.

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
- The daily cron runs automatically at 09:00 UTC on weekdays once the release is up.

## Local verification (what was run before shipping)

```
docker build -t oqm:deploy-test .
# postgres container, then:
docker run --rm --network <net> -e DATABASE_URL=... -e SECRET_KEY_BASE=... oqm:deploy-test /app/bin/migrate
docker run -d --network <net> -p 4011:4000 -e DATABASE_URL=... -e SECRET_KEY_BASE=... \
  -e PHX_HOST=localhost -e PHX_SERVER=true oqm:deploy-test
curl http://127.0.0.1:4011/    # -> 200, register UI
```

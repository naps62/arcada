# Observability

Two dashboards, two jobs. Issue #98.

| Dashboard | UID | Question it answers | Source |
|---|---|---|---|
| **Arcada — App & Processing** | `oqm-overview` | Is the machine healthy? | PromEx built-ins + Loki + Traefik |
| **Arcada — Negócio** | `arcada-business` | Is the product growing / is content fresh? | `Arcada.PromEx.BusinessMetrics` |

Runtime plumbing (PromEx, `/metrics` on :9091, Alloy scrape labels) lives in
`docs/DEPLOY.md` § Observability. This doc covers what gets measured and why.

## 1. Why a separate business plugin

Infra metrics come free from PromEx built-ins (Beam, Phoenix, Ecto, Oban). Business
metrics do not exist until someone counts rows. `Arcada.PromEx.BusinessMetrics` is a
**polling** plugin: it runs grouped `count`/`sum` queries on a timer and emits gauges.

Polling, not events, because these are **stock levels** (how many users exist), not
flows (how many searches happened). `SearchMetrics` is the event counterpart — keep the
two patterns unmixed.

## 2. Frozen metric contract

Telemetry name maps to Prometheus name by PromEx's usual rule (dots/underscores). Names
below are the contract — dashboards query them, tests assert them. Change one, change
both.

| Telemetry metric | Prometheus | Tags | Meaning |
|---|---|---|---|
| `[:arcada, :business, :users, :count]` | `arcada_business_users_count` | `state` = `confirmed` \| `unconfirmed` | registered users |
| `[:arcada, :business, :subscribers, :count]` | `arcada_business_subscribers_count` | — | distinct users with >=1 subscription |
| `[:arcada, :business, :subscriptions, :count]` | `arcada_business_subscriptions_count` | `period`, `kind` = `tema` \| `digest`, `active` | subscriptions |
| `[:arcada, :business, :acts, :count]` | `arcada_business_acts_count` | `summarized` = `true` \| `false` | acts ingested |
| `[:arcada, :business, :acts, :by_tipo, :count]` | `arcada_business_acts_by_tipo_count` | `tipo` (bucketed, see §4) | acts by diploma type |
| `[:arcada, :business, :acts, :by_domain, :count]` | `arcada_business_acts_by_domain_count` | `domain` (10 life domains) | published acts per domain |
| `[:arcada, :business, :editions, :count]` | `arcada_business_editions_count` | — | editions scraped |
| `[:arcada, :business, :register, :lag_days]` | `arcada_business_register_lag_days` | — | days since newest act's `published_at` |
| `[:arcada, :business, :summaries, :count]` | `arcada_business_summaries_count` | — | summaries generated |
| `[:arcada, :business, :summaries, :cost_usd]` | `arcada_business_summaries_cost_usd` | `cost_source` = `api` \| `subscription` \| `unknown` | cumulative LLM spend |
| `[:arcada, :business, :summaries, :tokens]` | `arcada_business_summaries_tokens` | `direction` = `input` \| `output` | cumulative tokens |

All are `last_value` gauges. All are **cumulative absolute counts**, not rates — growth
is `delta(metric[7d])` in the dashboard, never a counter reset.

### Poll groups

| Group | Rate | Covers | Why |
|---|---|---|---|
| `:arcada_business_fast` | 60s | users, subscribers, subscriptions | small tables, the numbers people watch |
| `:arcada_business_slow` | 300s | acts, editions, summaries, lag | bigger scans, slow-moving data |

## 3. What is NOT measured, and why

- **Provenance ladder counts** (unreviewed / community / verified). DESIGN.md describes
  the ladder but no review state exists in the DB yet — every summary is unreviewed.
  Nothing to count. Add when the column lands.
- **Per-user or per-act series.** Unbounded cardinality. See §4.
- **`emitter` breakdown.** Hundreds of distinct issuing bodies. Query Postgres for that,
  not Prometheus.
- **Search volume / funnel.** Already on the infra dashboard via `SearchMetrics`.

## 4. Landmines

**Cardinality.** Every tag value becomes a Prometheus series forever. Hard cap ~20
distinct values per tag. `tipo` is free text scraped from DRE — bucket it against a
known allowlist and fold everything else into `outro`. NEVER tag by user, act, emitter,
query text, or anything a stranger can create.

**Multi-node aggregation.** These gauges are global DB counts, so every node reports the
same number. Dashboard queries MUST use `max by (...)` and never `sum by (...)` — with N
replicas `sum` reports N times the truth. Single node today; the query survives scaling.

**Poller must not crash.** A raising poll function takes the PromEx poller down and ALL
metrics with it, infra included. Wrap DB access and emit nothing on failure.

**`cost_usd` is `Decimal` and often nil.** Convert to float, treat nil as 0.

## 5. Dashboards as code

`priv/grafana/*.json` is the source of truth. `mix arcada.grafana` syncs both ways:

```
mix arcada.grafana pull <uid>   # Grafana -> priv/grafana/<uid>.json
mix arcada.grafana push [uid]   # priv/grafana -> Grafana
```

Needs `GRAFANA_URL` + `GRAFANA_SERVICE_ACCOUNT_TOKEN`. Never commit the token.

**Rejected: PromEx `upload_dashboards_on_start`.** It would overwrite `oqm-overview` —
41 hand-tuned panels including Loki and Traefik queries PromEx knows nothing about —
with whatever the repo last held. A push has to be a deliberate act, not a deploy side
effect. `grafana: :disabled` stays.

**Rejected: leave dashboards in Grafana only** (status quo). `oqm-overview` existed for
months with no versioned copy; one bad edit loses it.

The product design system in `DESIGN.md` governs the **reader-facing** product. It does
not apply to these dashboards — internal ops surfaces, default Grafana styling.

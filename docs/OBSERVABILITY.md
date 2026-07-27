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
| `[:arcada, :business, :subscriptions, :count]` | `arcada_business_subscriptions_count` | `period`, `kind` = `tema` \| `digest`, `active` = `true` \| `false` | subscriptions |
| `[:arcada, :business, :acts, :count]` | `arcada_business_acts_count` | `summarized` = `true` \| `false` | acts ingested |
| `[:arcada, :business, :acts, :by_tipo, :count]` | `arcada_business_acts_by_tipo_count` | `tipo` (bucketed, see §4) | acts by diploma type |
| `[:arcada, :business, :acts, :by_domain, :count]` | `arcada_business_acts_by_domain_count` | `domain` (10 life domains) | **acts that have a published summary**, per domain — see §4 |
| `[:arcada, :business, :editions, :count]` | `arcada_business_editions_count` | — | editions scraped |
| `[:arcada, :business, :register, :lag_days]` | `arcada_business_register_lag_days` | — | days since newest act's `published_at` |
| `[:arcada, :business, :summaries, :count]` | `arcada_business_summaries_count` | — | summaries generated |
| `[:arcada, :business, :summaries, :cost_usd]` | `arcada_business_summaries_cost_usd` | `cost_source` = `api` \| `subscription` \| `unknown` | cumulative LLM spend |
| `[:arcada, :business, :summaries, :tokens]` | `arcada_business_summaries_tokens` | `direction` = `input` \| `output` | cumulative tokens |
| `[:arcada, :business, :emails, :total]` | `arcada_business_emails_total` | `kind` = `tema` \| `digest`, `result` = `sent` \| `failed` | subscription emails attempted — see §2.1 |

All except `emails` are `last_value` gauges holding **cumulative absolute counts**, not
rates. `emails` is a `counter` (a flow, not a stock).

**Tag values are strings.** `active` and `summarized` emit `"true"`/`"false"`, not
booleans or 1/0 — dashboards match on `active="true"`. Get this wrong and every
subscription panel silently goes blank, which reads as a deploy failure.

### Growth over a range

Use `max_over_time(m[$__range]) - min_over_time(m[$__range])`.

**NOT `delta()`.** `delta` extrapolates to the window edges, which on a young series is
wildly wrong — measured against a live gauge sitting at `10`, `delta(m[30d])` returned
`3232.5`. That is exactly the first month after deploy, the month anyone actually watches.
`rate`/`increase` are also wrong here: these are gauges, not counters.

### 2.1 Why email is in a business dashboard

Subscriptions are only real when the mail lands. Scaleway TEM caps at 100 messages/day
shared with account mail, and `DispatchWorker` caps itself at 80 sends per run — so a
growing list silently truncates, and no stock metric can show that. Every other metric
here is a stock; this is the one flow, and it is the one that answers "did today's send
actually go out".

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

**`cost_source=api` is cash; `subscription` is imputed.** `api` is money that left the
account. `subscription` is a flat fee apportioned per call — it does not change if you
summarize twice as much. Summing them yields a number that is neither, so the headline
cost panel charts `api` only and the total is broken out by source beside it.

**`acts_count` and `acts_by_domain_count` do not reconcile, by design.** `acts_count` is
everything ingested; domains only exist on a summary, so `acts_by_domain_count` covers
only acts that have one. An act with two domains counts in both. Never present the two
side by side as if they should add up.

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

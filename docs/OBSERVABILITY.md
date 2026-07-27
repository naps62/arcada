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
| `[:arcada, :business, :subscribers, :count]` | `arcada_business_subscribers_count` | `active` = `true` \| `false` | distinct users with >=1 subscription in that state |
| `[:arcada, :business, :subscriptions, :count]` | `arcada_business_subscriptions_count` | `period`, `kind` = `tema` \| `digest`, `active` = `true` \| `false` | subscriptions |
| `[:arcada, :business, :acts, :count]` | `arcada_business_acts_count` | `summarized` = `true` \| `false` | acts ingested |
| `[:arcada, :business, :acts, :by_tipo, :count]` | `arcada_business_acts_by_tipo_count` | `tipo` (bucketed, see §4) | acts by diploma type |
| `[:arcada, :business, :acts, :by_domain, :count]` | `arcada_business_acts_by_domain_count` | `domain` (10 life domains) | **acts that have a published summary**, per domain — see §4 |
| `[:arcada, :business, :editions, :count]` | `arcada_business_editions_count` | — | editions scraped |
| `[:arcada, :business, :register, :lag_days]` | `arcada_business_register_lag_days` | — | days since newest act's `published_at` — is **scraping** alive |
| `[:arcada, :business, :summaries, :lag_days]` | `arcada_business_summaries_lag_days` | — | days since the newest summarized act's `published_at` — is **summarizing** alive |
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
  the ladder, but `docs/PLAN.md` defers the 👥 and ✓ rungs out of the MVP — only 🤖
  unreviewed ships. No review state exists in the DB, so every summary is unreviewed and
  there is nothing to count. Add when the column lands, not before.
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

**A raising poll function is dropped forever, silently.** `telemetry_poller` catches the
exception and permanently removes that MFA for the life of the node
(`make_measurements_and_filter_misbehaving/1`) — it never retries, and PromEx groups
pollers by `poll_rate` so nothing else is affected. So the blast radius is one metric
family, not the whole exporter, but the failure is worse than a crash: the series just
stops with no restart and no alert. Rescue inside the poll function and emit nothing, so
the next tick still runs.

**`cost_usd` is `Decimal` and often nil.** Convert to float, treat nil as 0.

**`cost_usd` is NULL on every row in prod today** (2,350 summaries, all null — measured,
not assumed). Nothing in the summarizer writes it. The metric is implemented and correct,
but it will read `0` until cost capture lands, so the dashboard does NOT give it a money
panel — a permanently-zero cost tile teaches people to ignore the whole dashboard. Tokens
ARE populated (11.8M in / 282k out) and carry the "what is this costing" signal for now.

When cost capture does land: `cost_source=api` is cash that left the account;
`subscription` is a flat fee apportioned per call and does not change if you summarize
twice as much. Summing them gives a number that is neither — chart `api` alone.

**Two lag metrics, because one hides the other.** `register_lag_days` catches a dead
scraper. It cannot catch a dead summarizer: acts keep landing, so register lag stays at 0
while the unsummarized backlog grows slowly enough to go unnoticed for a week.
`summaries_lag_days` is the pairing metric. Watch both or neither.

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

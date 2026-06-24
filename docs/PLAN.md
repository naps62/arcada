# o-que-mudou — MVP plan

> Living planning doc. Decisions captured from the initial scoping session.

## Goal (MVP)

A **private register of what changed** in Diário da República **Série I**, in **plain
language**, with **citations**. Something the maintainer browses and validates privately.

Explicitly **deferred**: personal-profile filters, newsletter/social distribution,
community review / provenance promotion (the 👥 and ✓ rungs). MVP ships only the
🤖 **unreviewed** rung plus a private **validated** flag.

## Constraints / decisions

- **Ingestion:** build our own scraper (no reuse of Apify/`hgg/dre`, though they confirm feasibility). **Pure HTTP** (Req) — recon confirmed no browser runtime is needed in production (see `endpoints.md`).
- **Audience:** private only. Hosted on `example.internal`, VPN-gated. **No app-level auth in MVP** — network gating only.
- **Stack:** Elixir / **Phoenix + LiveView**, Postgres. No SPA / React. LiveView only where it makes the UI snappier.
- **App structure:** **single Phoenix app**. Extract the crawl/classify/summarize pipeline into a shared lib only when `filho-em-portugal` actually consumes it (YAGNI — no umbrella up front).
- **LLM provider:** **Claude API** for the MVP (default model **Sonnet 4.6** — legal text rewards nuance and Série I volume is tiny, so cost stays coffee-sized; revisit Haiku if cost grows). Summarization stays abstracted behind a behaviour with `api | local | manual` adapters; the `manual` (SSH-driven) adapter is the backfill/escape hatch. The pipeline must not assume a synchronous API call. Model + `prompt_version` recorded per summary.
- **Classification:** done in the **same LLM call** as the summary (one prompt → `{plain_text, domains[]}`), not a separate pass.
- **Deployment:** **Dokploy** on `example.internal` — Dockerized Elixir release; Dokploy-managed Postgres; secrets (Claude API key) via Dokploy env.
- **Validation:** in scope for MVP — a private "mark validated" toggle.

## Source reality (recon)

- `diariodarepublica.pt` is an **OutSystems SPA**. Every route returns the same ~2.3KB
  bootstrap shell; all data is fetched at runtime via `screenservices` POST endpoints.
- **No official API.** PDFs under `files.diariodarepublica.pt` are a stable citation/fallback artifact.
- Série I is published on **business-day mornings**, low daily volume (keeps editorial cadence "coffee-sized").

### First task: endpoint discovery
Drive the live site in a browser, capture the XHR/`screenservices` calls for:
1. **list editions by date** (find the Série I issue(s) for a given day)
2. **sumário → acts for an edition** (the list of acts published)
3. **act detail / full text** (title, type, emitter, body, source + PDF URLs)

Document each: URL, headers, request payload shape, response shape. Then replay with an HTTP client.

## Architecture

```
scrape ──> store ──> summarize+classify ──> browse (LiveView)
 (Oban daily)         (pluggable adapter)     (private, validate toggle)
```

- **HTTP:** Req
- **Scheduling:** Oban cron — daily after publication; idempotent upsert by `dre_id`
- **Summarizer:** behaviour `Summarizer.adapter/1` with adapters (api | local | manual). Summaries written async; a manual adapter can backfill.

## Data model (initial)

- **editions** — `serie`, `number` (e.g. `118/2026`), `date`, `sumario_url`, `scraped_at`
- **acts** — `edition_id`, `dre_id` (unique), `tipo` (Decreto-Lei / Portaria / …),
  `emitter` (ministério), `title`, `full_text`, `source_url`, `pdf_url`, `published_at`
- **summaries** — `act_id`, `plain_text`, `domains[]`, `model`, `prompt_version`,
  `status` (`unreviewed` for now), `generated_at`, **`validated_at`** (null = unvalidated)

Life-domain taxonomy (fixed enum to start): fiscal, trabalho, saúde, família, habitação,
educação, transportes, justiça, ambiente, administração, …

## Build order

1. **Endpoint recon** (browser) → document the 3 screenservices calls.
2. **Scraper** — Req client replaying them; idempotent upsert by `dre_id`; Oban daily cron.
3. **Summarize + classify** — adapter interface; plain-PT summary + domain tags; labeled 🤖 unreviewed.
4. **LiveView UI** — register grouped by date, static domain filter, act-detail page
   (summary + citation + official-source link), **"mark validated" toggle**.

## Risks

- screenservices endpoints may change / rate-limit → tolerant parsing + PDF-artifact fallback.
- LLM mis-summary of legal text → full text + citation always one click away; the
  validate toggle is the human safety net before anything is trusted.

## v2 — municipal decisions ("o que decidiu a minha câmara?")

Same engine, different source. Câmara / assembleia municipal **deliberações** live in
buried PDFs across 308 municipalities; this is the *exact* scrape → classify → summarize →
register pipeline pointed at local government instead of Diário da República.

- **Why a v2 and not its own project:** reuses the entire ingestion/summarization/UI
  skeleton; the only new parts are per-municipality source adapters and a "município"
  dimension on the data model.
- **GTM principle:** one district deep (Braga) first, not 308 shallow — PDF layouts vary
  wildly per município, so each source is a small adapter, seeded from one.
- **Accountability angle:** local government is the level citizens can actually act on;
  "what did my câmara decide and spend this month?" is a sharper hook than national DRE.
- **Data-model impact:** add `municipality` (+ source adapter registry) alongside
  `editions`; acts/summaries gain a municipal scope. Defer until the DRE MVP is solid.
```

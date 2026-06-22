# o-que-mudou — MVP plan

> Living planning doc. Decisions captured from the initial scoping session.

## Goal (MVP)

A **private register of what changed** in Diário da República **Série I**, in **plain
language**, with **citations**. Something the maintainer browses and validates privately.

Explicitly **deferred**: personal-profile filters, newsletter/social distribution,
community review / provenance promotion (the 👥 and ✓ rungs). MVP ships only the
🤖 **unreviewed** rung plus a private **validated** flag.

## Constraints / decisions

- **Ingestion:** build our own scraper (no reuse of Apify/`hgg/dre`, though they confirm feasibility).
- **Audience:** private only. Hosted on `example.internal`, VPN-gated.
- **Stack:** Elixir / **Phoenix + LiveView**, Postgres. No SPA / React. LiveView only where it makes the UI snappier.
- **LLM provider:** undecided. Summarization is abstracted behind a behaviour so the
  adapter can be swapped — hosted API, local model, or even a **manual / SSH-driven
  session** (drive a personal Claude subscription live and write summaries back).
  Provider choice deferred; the pipeline must not assume a synchronous API call.
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
```

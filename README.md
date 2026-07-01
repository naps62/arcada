# o-que-mudou

**Arcada — o Diário da República em linguagem simples**

> Status: early planning. This README captures the loose project description; scope and architecture are still being worked out.

## The idea

Daily scrape of **Diário da República Série I** → classify by life-domain → plain-language LLM summaries answering *what changed, for whom, from when*, with **article-level citations**.

A **provenance ladder**:

1. 🤖 **unreviewed** (opt-in, screenshot-proof labeling, hot-topics carved out)
2. 👥 **community-reviewed** (vouched reviewers, flag-anyone / promote-by-vouch)
3. ✓ **verified**

A personal profile filters the firehose to your life. Newsletter + social bot for distribution; **journalists as the growth loop**.

No clean official API — it's OutSystems scraping (prior art exists: `hgg/dre`, Apify) — so the real cost is the **daily editorial cadence**, kept coffee-sized by Série I's low volume and the review-as-diff-against-grounding trick.

## Ratings (from the shortlist)

- **Effort to MVP:** weeks
- **Upkeep:** daily but small, community-distributable
- **Money:** donations/grants at most
- **Fit:** high — civic gravitas; the cadence is the one real commitment

## Design principles

- **Signpost, not authority.** Visible source links, "last verified" dates, plain "isto não é aconselhamento" framing.
- **Go to market one district deep, not nationally shallow.**

## Shared infrastructure

Shares its entire crawl/classify/verify pipeline with [`filho-em-portugal`](../filho-em-portugal) and the recall & safety aggregator (which could even be a *module* of this).

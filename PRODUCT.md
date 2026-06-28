# Product

## Register

product

## Users

Portuguese citizens — a broad public including older and less technical readers — trying to
answer one question: *what changed for me, and from when?* They arrive intimidated by legalese,
short on time, and read on phones as often as desktops. A second key audience is **journalists**,
who use the register as a research and growth surface and need fast scanning, clear citations,
and confidence in provenance.

## Product Purpose

Turn *Diário da República, Série I* into plain-language summaries that answer *what changed, for
whom, from when* — with article-level citations and a visible **provenance ladder** (🤖
unreviewed → 👥 community-reviewed → ✓ verified). A personal profile filters the firehose to
each reader's life. Success is a citizen leaving with an honest, sourced understanding of a legal
change they'd otherwise never have parsed — and trusting where that understanding came from. The
product is a **signpost, not an authority**: it never poses as legal advice.

## Brand Personality

Trustworthy, clear, sober. The voice is plain-language Portuguese — calm and human. Warmth lives
in the copy and the summaries, not in decorative chrome. It frames honestly at every turn
(*"isto não é aconselhamento jurídico"*, visible source links, "última verificação" dates) and
earns confidence through transparency and restraint rather than persuasion. It reads like a
credible public-service utility — never marketing-y, never alarmist, never partisan.

## Anti-references

- **Default framework scaffolding** — the current Phoenix logo / header / `@elixirphoenix` and
  GitHub links / brand-orange version pill must go.
- **Corporate-SaaS gradients and hero fluff** — no gradient-drenched landing chrome on a reading
  tool.
- **Alarmist news-site urgency** — no breaking-news red, countdown energy, or outrage framing.
- **Nationalistic flag styling** — avoid green/red Portuguese-flag palette as identity; it reads
  partisan.

## Design Principles

1. **Signpost, not authority.** Every screen makes provenance, sources, and "last verified"
   visible. Never imply official endorsement or legal advice; transparency is the primary trust
   mechanism.
2. **Content leads, chrome recedes.** A quiet, near-monochrome frame keeps the plain-language
   summary and its citations as the visual focus. No decoration competes with the text.
3. **Color is a signal, not a style.** Reserve saturated color for the provenance ladder and
   genuine status. Status must read without relying on color alone (icon + label + color).
4. **Reach over polish-for-the-few.** Build for AA *and beyond*: comfortable large text, generous
   tap targets, very plain interaction patterns, full keyboard support, visible focus, respected
   reduced-motion. Assume an older, low-tech reader on a phone.
5. **Plain over precise-but-opaque.** When clarity and completeness conflict, choose the wording
   an ordinary citizen understands — then link to the official source for the rest.

## Accessibility & Inclusion

Target **WCAG 2.1 AA, plus extra reach**: deliberate large-text comfort, generous tap targets,
and very plain interaction patterns for low-tech and older users. Provenance and status never
depend on color alone. Respect `prefers-reduced-motion` and `prefers-color-scheme` (theme
defaults to auto). UI language is Portuguese, including dates (`28 de junho de 2026`) and labels.

---
name: O que mudou
description: Plain-language broadsheet for Diário da República — a civic signpost, not an authority.
colors:
  # Light theme (newsprint, canonical). Dark variants carry the `-dark` suffix.
  bg: "oklch(0.965 0.008 85)"
  surface: "oklch(0.945 0.01 85)"
  surface-inset: "oklch(0.925 0.011 85)"
  ink: "oklch(0.23 0.012 60)"
  muted: "oklch(0.45 0.014 65)"
  border: "oklch(0.84 0.012 80)"
  rule-strong: "oklch(0.23 0.012 60)"
  primary: "oklch(0.46 0.12 255)"
  primary-hover: "oklch(0.4 0.12 255)"
  # Provenance ladder — the only saturated color on the page.
  state-unreviewed-bg: "oklch(0.93 0.06 80)"
  state-unreviewed-ink: "oklch(0.42 0.11 60)"
  state-community-bg: "oklch(0.93 0.04 250)"
  state-community-ink: "oklch(0.37 0.10 255)"
  state-verified-bg: "oklch(0.93 0.05 150)"
  state-verified-ink: "oklch(0.35 0.10 150)"
  # System status (flash notices) — restrained red, errors only.
  state-error-bg: "oklch(0.93 0.05 27)"
  state-error-ink: "oklch(0.47 0.16 27)"
  # Dark theme (evening edition)
  bg-dark: "oklch(0.18 0.006 70)"
  surface-dark: "oklch(0.22 0.008 70)"
  ink-dark: "oklch(0.92 0.01 85)"
  muted-dark: "oklch(0.68 0.012 80)"
  border-dark: "oklch(0.32 0.01 75)"
  rule-strong-dark: "oklch(0.62 0.012 80)"
  primary-dark: "oklch(0.74 0.11 250)"
typography:
  nameplate:
    fontFamily: "Fraunces, Newsreader, Georgia, serif"
    fontSize: "clamp(2.25rem, 6vw, 3.25rem)"
    fontWeight: 900
    lineHeight: 1
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "Fraunces, Newsreader, Georgia, serif"
    fontSize: "1.375rem"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "normal"
  deck:
    fontFamily: "Fraunces, Newsreader, Georgia, serif"
    fontSize: "2rem"
    fontWeight: 300
    lineHeight: 1.2
    letterSpacing: "normal"
  reading:
    fontFamily: "Newsreader, Georgia, 'Times New Roman', serif"
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.6
    letterSpacing: "normal"
  body:
    fontFamily: "Inter, ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.9375rem"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "normal"
  kicker:
    fontFamily: "Inter, ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.6875rem"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "0.09em"
rounded:
  xs: "3px"
  sm: "4px"
  md: "8px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "40px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.bg}"
    rounded: "{rounded.md}"
    padding: "10px 18px"
    typography: "{typography.body}"
  section-link-active:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.kicker}"
  flag-unreviewed:
    backgroundColor: "{colors.state-unreviewed-bg}"
    textColor: "{colors.state-unreviewed-ink}"
    rounded: "{rounded.xs}"
    padding: "2px 8px"
    typography: "{typography.kicker}"
  flag-verified:
    backgroundColor: "{colors.state-verified-bg}"
    textColor: "{colors.state-verified-ink}"
    rounded: "{rounded.xs}"
    padding: "2px 8px"
    typography: "{typography.kicker}"
---

# Design System: O que mudou

## 1. Overview

**Creative North Star: "The Plain-Language Broadsheet"**

A daily paper for the law. Warm newsprint stock, a high-contrast serif nameplate, hairline
rules between stories, and a kicker over every headline naming who issued it. It reads like a
quality broadsheet — but every "story" is a diploma from *Diário da República, Série I*, and the
standfirst beneath each headline is the plain-language summary of what actually changed.

This is a **product** surface dressed as editorial. It serves citizens — many older, many on
phones, intimidated by legalese — and the journalists who mine it. It earns trust the way a paper
of record does: a legible masthead, sourced kickers, a visible "última verificação", and an
absolute refusal to oversell. It is a **signpost, not an authority** — never legal advice, always
the official source one tap away.

What it rejects: the default Phoenix scaffold it was born from (deleted); corporate-SaaS cards,
gradients, and hero fluff; alarmist news-site urgency (no breaking-news red, no countdowns); and
the Portuguese flag's green/red as identity (reads partisan).

**Key Characteristics:**
- Warm newsprint paper, never pure white; a warm "evening edition" dark.
- Three serif/sans jobs: **Fraunces** display headlines, **Newsreader** reading prose, **Inter**
  furniture (kickers, flags, section bar, meta).
- Stories are **ruled, not carded** — hairline dividers, kicker → headline → standfirst.
- Color is a *signal*, never decoration — reserved for the three provenance flags.
- Built for reach: large serif headlines, 17px reading prose, auto light/dark, full keyboard paths.

## 2. Colors

A warm newsprint greyscale carrying a single deep ink-blue, with one tightly-scoped semantic trio
for the provenance ladder. The strategy is **Restrained**: saturated color covers well under 10%
of any screen, and almost all of that is status.

### Primary
- **Ink Blue** (`oklch(0.46 0.12 255)`): links, the active section, primary actions, focus rings.
  Deep and sober against the warm paper — institutional, not a tech-brand pop. Lifts to
  `oklch(0.74 0.11 250)` in dark mode. ~6.5:1 as link text on paper; white text clears 7:1 on it.

### Secondary
The provenance ladder is the expressive layer — small uppercase **flags**, each a pale fill +
dark same-hue ink + icon + word, never relying on hue alone.
- **Unreviewed Amber** (`oklch(0.68 0.13 80)`, fill `0.93 0.06 80`, ink `0.42 0.11 60`): 🤖 *não
  revisto*. Machine-made, not yet vouched-for.
- **Community Blue** (`oklch(0.50 0.11 250)`, fill `0.93 0.04 250`, ink `0.37 0.10 255`): 👥
  *comunidade*. People have looked.
- **Verified Green** (`oklch(0.52 0.12 150)`, fill `0.93 0.05 150`, ink `0.35 0.10 150`): ✓
  *verificado*. Confirmed — the top of the ladder.

### Neutral
- **Ink** (`oklch(0.23 0.012 60)`): a warm printing-ink near-black. ~15:1 on paper.
- **Muted** (`oklch(0.45 0.014 65)`): kickers, meta, emitter lines. Held dark — 6.7:1 — because
  washed-out grey is the biggest readability failure.
- **Paper** (`oklch(0.965 0.008 85)`): the body. A genuine warm newsprint stock at very low chroma
  — newsprint, not the saturated AI cream. Dark mode is a warm near-black (`oklch(0.18 0.006 70)`).
- **Border** (`oklch(0.84 0.012 80)`): hairline rules between stories. **Rule-strong** (= ink) is
  the heavy rule under the nameplate and date dividers.

### Named Rules
**The Signal-Only Rule.** Saturated color is forbidden as decoration. If a colored element is not
a link, a primary action, a focus state, or a provenance flag, its color is a bug.

**The Colour-Is-Never-Alone Rule.** Every provenance flag pairs a hue with an icon and a word.
Remove the color and the state must still be unambiguous.

## 3. Typography

**Display Font:** Fraunces (with `Newsreader, Georgia` fallback) — high-contrast, characterful.
**Reading Font:** Newsreader (with `Georgia, 'Times New Roman'` fallback) — calm text serif.
**Furniture Font:** Inter (with `system-ui` fallback) — kickers, flags, section bar, meta, data.

**Character:** A newspaper stack. Fraunces is the masthead and every headline — the voice that
says "this is a story." Newsreader carries the plain-language standfirst and full summaries — the
voice that says "this is written for you to read." Inter handles all furniture. Three families,
three unambiguous jobs; never blurred.

### Hierarchy
- **Nameplate** (Fraunces 900, clamp 2.25→3.25rem, lh 1): the masthead "O que mudou", centered,
  with a kicker line above and a heavy rule below.
- **Deck** (Fraunces 300 italic, ~2rem): the standfirst under the masthead — the standing line.
- **Headline** (Fraunces 600, 1.25→1.375rem): each act's title, the story headline.
- **Reading** (Newsreader 400, 1.0625rem/17px, lh 1.6, ≤70ch): summary + act prose. Reach-first.
- **Body** (Inter 400, 0.9375rem): UI copy, controls, source links.
- **Kicker** (Inter 600, 0.6875rem, uppercase, 0.09em): the issuing-body line over each headline,
  the section bar, the provenance flags, date dividers.

### Named Rules
**The Serif-For-Reading Rule.** Newsreader is for prose a citizen reads, and nothing else.
**The Headlines-Are-Fraunces Rule.** Fraunces is display only — nameplate, deck, headlines.
Never set body or a control in Fraunces; never set a headline in Inter.

## 4. Elevation

Flat, everywhere. Depth is the **rule**, not the shadow: a hairline `border` divides stories, a
heavy `rule-strong` opens each date section, underlines the nameplate, and separates the
act-detail summary from its sources. Even the act page is flat — the plain-language summary sits
directly on the paper as the article body, never in a card. Shadow is reserved for genuinely
floating, transient layers (dropdowns, dialogs, **flash notices**).

### Shadow Vocabulary
- **Floating** (`0 8px 24px -8px oklch(0.23 0.012 60 / 0.22)`): popovers and dialogs only.

### Named Rules
**The Ruled-Not-Carded Rule.** Stories are separated by hairline rules, not boxed in cards. A
resting card with a border-radius and a shadow in the register feed is wrong; the rule is the
divider.

## 5. Components

### Nameplate (masthead)
Centered Fraunces 900 wordmark, a small uppercase kicker line above (`Diário da República · Série
I` / `Novo a cada dia útil`), a 2px `rule-strong` below. Present on every page; links home.

### Section bar (domain filter)
A horizontal row of uppercase Inter links (the life-domains + "Tudo"), counts trailing in small
muted figures. Active link is ink with a 2px under-rule; inactive is muted → ink on hover; a
zero-count domain dims to 50%. Replaces pills — this is a newspaper section bar, not an app chip
row. Generous `py` keeps tap targets comfortable.

### Story entry (act) — *ruled, not carded*
- **Kicker:** the issuing body, uppercase Inter muted.
- **Headline:** Fraunces 600, ~1.375rem, links to the act.
- **Standfirst:** the plain-language summary in Newsreader, ≤70ch.
- **Foot:** domain flags + `fonte oficial` / PDF links in Inter.
- **Provenance flag** sits top-right of the headline row.
- Entries are divided by `divide-y` hairlines inside a date section; the section opens with a
  `rule-strong` date divider and a diploma count.

### Brief (act without a summary)
A quiet one-line ruled row: headline in Fraunces at body size + a muted uppercase `por gerar`.
Recedes so summarised stories carry the page.

### Provenance flag (signature)
Small uppercase Inter, `3px` corners, pale state-fill + dark state-ink + icon + word. Three
variants: 🤖 *não revisto* (amber), 👥 *comunidade* (blue), ✓ *verificado* (green). The one place
color carries meaning — always with an icon and a word.

### Buttons / links
Links are Ink Blue, underline on hover/focus. The act-detail actions (`Fonte oficial`, PDF, full
text, `Marcar como validado`) are bordered Inter controls with ≥44px targets.

### Notices (flash)
A flat surface notice pinned top-right, `floating` shadow, dismissible. **Info** carries an Ink
Blue icon on neutral ink; **error** carries the restrained red `state-error` icon + title on the
same neutral surface — never a full red fill. Copy is Portuguese. The only place a transient
shadow appears.

## 6. Do's and Don'ts

### Do:
- **Do** keep the page in ink, muted, and rule until an element earns color — a link, a primary
  action, focus, or a provenance flag.
- **Do** set headlines in Fraunces, reading prose in Newsreader, everything else in Inter.
- **Do** divide stories with hairline rules; open date sections and the nameplate with the heavy
  `rule-strong`.
- **Do** render every provenance flag as icon + word + color, surviving with color removed.
- **Do** hold muted text at ≥4.5:1 (`oklch(0.45 0.014 65)` on paper); never let a grey go faint.
- **Do** size for reach: ≥44px controls, 17px reading prose, visible `:focus-visible` rings,
  `prefers-reduced-motion` fallbacks, and respect `prefers-color-scheme`.
- **Do** keep the official source and the "última verificação" date visible on every act.

### Don't:
- **Don't** box stories in rounded cards with shadows — that's the app reflex this rejects. Rules
  divide; the page is flat.
- **Don't** reintroduce default Phoenix scaffold (the orange `#FD4F00` pill, the logo, the
  `@elixirphoenix` / GitHub links).
- **Don't** use a pure-white body — the stock is warm newsprint. And don't push the paper into
  saturated AI cream; keep chroma ≤ ~0.012.
- **Don't** use corporate-SaaS gradients, hero metrics, or glassmorphism.
- **Don't** signal urgency like a news site — no breaking-news red, no countdowns, no alarm.
- **Don't** use the Portuguese flag's green/red as identity; status green is a provenance signal.
- **Don't** put a colored `border-left` stripe on a story — full-width hairline rules only.
- **Don't** set a headline in Inter or a control/label in Fraunces.

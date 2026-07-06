// A ghost placeholder for the search field that shows a different example query
// on every page load, then — for readers who accept motion — gently cycles
// through the rest, backspacing one and typing the next behind a blinking caret.
// The empty field always suggests *how* to search: plain life-language ("renda
// de casa"), not diploma numbers.
//
// The caret (and the dimmed placeholder colour) make it unmistakable that this
// is a hint being typed, not text the reader entered. It only ever touches the
// `placeholder` attribute, and only while the field is empty and unfocused — the
// instant the reader engages, the caret is dropped (the native one takes over)
// and cycling freezes, so patches during typing never fight it.
//
// Progressive enhancement: the server renders a real example as the placeholder,
// so with the hook absent the field is still labelled; under reduced motion the
// hook picks one example and stops — no typing, no blink.
//
// Expects: <input phx-hook="SearchPlaceholder" data-placeholders='["…","…"]'>

const HOLD_MS = 3400 // a completed example rests this long before clearing
const TYPE_MS = 42 // per character while typing the next example
const ERASE_MS = 22 // per character while backspacing the current one
const GAP_MS = 450 // the beat between an empty field and the next example
const BLINK_MS = 530 // caret on/off cadence — the familiar terminal beat
const CARET = "│" // box-drawing vertical: full-height, thin, near-universal
const PREFIX = "ex.: " // stable lead-in — never erased; examples cycle after it

const LAST_SHOWN_KEY = "arcada:search-placeholder"

export const SearchPlaceholder = {
  mounted() {
    // Autofocus on mount so the field is ready to type — covers SPA
    // (live_navigate/patch) arrivals where the HTML `autofocus` attribute
    // doesn't re-fire. Skip when the field already carries a query (e.g. a
    // shared `?q=…` link) so we don't yank the caret to the end mid-read.
    if (this.el.value === "") this.el.focus()

    this.reduce = window.matchMedia("(prefers-reduced-motion: reduce)")

    try {
      this.examples = JSON.parse(this.el.dataset.placeholders || "[]")
    } catch {
      this.examples = []
    }
    if (this.examples.length === 0) return

    this.timer = null // sequencing (type/erase/hold)
    this.blink = null // caret on/off interval
    this.caretOn = false
    this.paused = false
    this.text = ""
    this.queue = this.shuffled(this.examples)

    this.onFocus = () => this.pause()
    this.onBlur = () => this.resume()
    this.el.addEventListener("focus", this.onFocus)
    this.el.addEventListener("blur", this.onBlur)

    // The first pick is the per-load "always something different" — shown at
    // once, no typing, even before any cycling begins.
    const first = this.queue.shift()
    this.text = first
    this.remember(first)

    if (this.reduce.matches || this.busy()) {
      this.render() // static, caretless
      return
    }
    this.startCaret()
    this.schedule(() => this.cycle(), HOLD_MS)
  },

  destroyed() {
    this.stop()
    this.stopCaret()
    if (this.onFocus) this.el.removeEventListener("focus", this.onFocus)
    if (this.onBlur) this.el.removeEventListener("blur", this.onBlur)
  },

  // Never animate over a field the reader is using or has already typed into.
  busy() {
    return (
      this.paused ||
      this.el.value.length > 0 ||
      document.activeElement === this.el
    )
  },

  pause() {
    this.paused = true
    this.stop()
    this.stopCaret() // drop our caret so it never doubles the native one
  },

  resume() {
    this.paused = false
    if (this.reduce.matches || this.busy()) return
    this.startCaret()
    this.schedule(() => this.cycle(), GAP_MS)
  },

  async cycle() {
    if (this.busy()) return
    if (this.queue.length === 0) this.queue = this.shuffled(this.examples)
    const next = this.queue.shift()

    await this.erase()
    if (this.busy()) return
    await this.type(next)
    this.remember(next)
    if (!this.busy()) this.schedule(() => this.cycle(), HOLD_MS)
  },

  erase() {
    return new Promise((resolve) => {
      const step = () => {
        if (this.busy()) return resolve()
        if (this.text.length === 0) return this.schedule(resolve, GAP_MS)
        this.setText(this.text.slice(0, -1))
        this.schedule(step, ERASE_MS)
      }
      step()
    })
  },

  type(text) {
    return new Promise((resolve) => {
      let i = 0
      const step = () => {
        if (this.busy()) return resolve()
        i += 1
        this.setText(text.slice(0, i))
        if (i >= text.length) return resolve()
        this.schedule(step, TYPE_MS)
      }
      step()
    })
  },

  setText(text) {
    this.text = text
    this.render()
  },

  render() {
    this.el.setAttribute(
      "placeholder",
      PREFIX + this.text + (this.caretOn ? CARET : "")
    )
  },

  startCaret() {
    this.stopCaret()
    this.caretOn = true
    this.render()
    this.blink = window.setInterval(() => {
      this.caretOn = !this.caretOn
      this.render()
    }, BLINK_MS)
  },

  stopCaret() {
    if (this.blink) {
      window.clearInterval(this.blink)
      this.blink = null
    }
    this.caretOn = false
    this.render()
  },

  // A single reused timer for sequencing — every phase runs strictly one after
  // another, so scheduling the next step always supersedes the last.
  schedule(fn, ms) {
    this.stop()
    this.timer = window.setTimeout(fn, ms)
  },

  stop() {
    if (this.timer) {
      window.clearTimeout(this.timer)
      this.timer = null
    }
  },

  shuffled(list) {
    const a = list.slice()
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1))
      ;[a[i], a[j]] = [a[j], a[i]]
    }
    // Don't re-open with the example the previous page load ended on.
    const last = this.recall()
    if (a.length > 1 && a[0] === last) [a[0], a[1]] = [a[1], a[0]]
    return a
  },

  remember(text) {
    try {
      sessionStorage.setItem(LAST_SHOWN_KEY, text)
    } catch {
      /* private mode / storage disabled — rotation just loses cross-load memory */
    }
  },

  recall() {
    try {
      return sessionStorage.getItem(LAST_SHOWN_KEY)
    } catch {
      return null
    }
  },
}

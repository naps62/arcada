// Smoothly animates a native <details> open/close so the answer doesn't jump
// in and out. Native <details> hides its content instantly on toggle, which
// gives no room for a CSS transition on close — so we drive the height with the
// Web Animations API instead: keep the element open through the whole collapse,
// then commit the real `open` state when the animation lands.
//
// Progressive enhancement: with JS off (or reduced motion), the native toggle
// still works — this hook only intercepts to add the motion.
//
// Expects markup: <details phx-hook="Collapsible"><summary>…</summary>
//   <div data-collapsible-content>…</div></details>

const OPEN_MS = 300
const CLOSE_MS = 220
// ease-out-quart — confident deceleration, no bounce.
const EASING = "cubic-bezier(0.25, 1, 0.5, 1)"

export const Collapsible = {
  mounted() {
    this.summary = this.el.querySelector("summary")
    this.content = this.el.querySelector("[data-collapsible-content]")
    this.animation = null
    this.isClosing = false
    this.isExpanding = false
    this.reduce = window.matchMedia("(prefers-reduced-motion: reduce)")

    this.onClick = (event) => this.handleClick(event)
    this.summary.addEventListener("click", this.onClick)
  },

  destroyed() {
    if (this.summary) this.summary.removeEventListener("click", this.onClick)
    if (this.animation) this.animation.cancel()
  },

  handleClick(event) {
    // Reduced motion: let the browser toggle instantly, no interception.
    if (this.reduce.matches) return

    event.preventDefault()
    this.el.style.overflow = "hidden"

    if (this.isClosing || !this.el.open) {
      this.open()
    } else if (this.isExpanding || this.el.open) {
      this.shrink()
    }
  },

  open() {
    this.el.style.height = `${this.el.offsetHeight}px`
    this.el.open = true
    window.requestAnimationFrame(() => this.expand())
  },

  expand() {
    this.isExpanding = true
    const start = `${this.el.offsetHeight}px`
    const end = `${this.summary.offsetHeight + this.content.offsetHeight}px`
    this.run(start, end, OPEN_MS, true)
  },

  shrink() {
    this.isClosing = true
    const start = `${this.el.offsetHeight}px`
    const end = `${this.summary.offsetHeight}px`
    this.run(start, end, CLOSE_MS, false)
  },

  run(start, end, duration, open) {
    if (this.animation) this.animation.cancel()

    this.animation = this.el.animate(
      { height: [start, end] },
      { duration, easing: EASING }
    )
    this.animation.onfinish = () => this.finish(open)
    this.animation.oncancel = () => {
      this.isExpanding = false
      this.isClosing = false
    }
  },

  finish(open) {
    this.el.open = open
    this.animation = null
    this.isClosing = false
    this.isExpanding = false
    this.el.style.height = ""
    this.el.style.overflow = ""
  },
}

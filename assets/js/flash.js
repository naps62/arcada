// Briefly flashes the search-results container whenever a search completes, so
// it's clear the list refreshed even when the results are identical (e.g.
// deleting a character re-runs the search but returns the same acts). The
// server bumps a `data-token` on every completed search, which patches this
// element and fires `updated()`. See RegisterLive's `search_token`.
export const FlashOnResult = {
  mounted() {
    this.token = this.el.dataset.token
  },
  updated() {
    // Only flash when the search token actually changed — not for unrelated
    // patches to children.
    if (this.el.dataset.token === this.token) return
    this.token = this.el.dataset.token

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    this.el.animate(
      [
        {opacity: 0.45, transform: "translateY(4px)"},
        {opacity: 1, transform: "translateY(0)"}
      ],
      {duration: 260, easing: "cubic-bezier(0.25, 1, 0.5, 1)"}
    )
  }
}

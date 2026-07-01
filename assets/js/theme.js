// Three-way theme toggle (auto / light / dark).
//
// The no-flash startup script in root.html.heex applies the stored choice
// before first paint and exposes `window.__applyTheme(theme)`. This hook owns
// the interactive control: it reflects the current choice on the buttons,
// persists clicks to localStorage, and keeps `theme-color` live while the OS
// preference changes in "auto" mode.
//
// `auto` is represented as the *absence* of a localStorage key, so clearing the
// override cleanly reverts to `prefers-color-scheme`.

const STORAGE_KEY = "theme"

function currentChoice() {
  try {
    return localStorage.getItem(STORAGE_KEY) || "auto"
  } catch (_e) {
    return "auto"
  }
}

function store(theme) {
  try {
    if (theme === "auto") localStorage.removeItem(STORAGE_KEY)
    else localStorage.setItem(STORAGE_KEY, theme)
  } catch (_e) {
    /* private mode / storage disabled — the in-memory choice still applies */
  }
}

export const ThemeToggle = {
  mounted() {
    this.buttons = Array.from(this.el.querySelectorAll("[data-theme-option]"))

    this.render = () => {
      const choice = currentChoice()
      for (const btn of this.buttons) {
        btn.setAttribute(
          "aria-pressed",
          btn.dataset.themeOption === choice ? "true" : "false"
        )
      }
    }

    this.onClick = (event) => {
      const theme = event.currentTarget.dataset.themeOption
      store(theme)
      if (window.__applyTheme) window.__applyTheme(theme)
      this.render()
    }

    for (const btn of this.buttons) {
      btn.addEventListener("click", this.onClick)
    }

    // Keep theme-color following the OS while in auto mode.
    this.mql = window.matchMedia("(prefers-color-scheme: dark)")
    this.onSystemChange = () => {
      if (currentChoice() === "auto" && window.__applyTheme) {
        window.__applyTheme("auto")
      }
    }
    this.mql.addEventListener("change", this.onSystemChange)

    this.render()
  },

  destroyed() {
    for (const btn of this.buttons || []) {
      btn.removeEventListener("click", this.onClick)
    }
    if (this.mql) this.mql.removeEventListener("change", this.onSystemChange)
  },
}

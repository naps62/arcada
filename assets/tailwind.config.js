// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/o_que_mudou_web.ex",
    "../lib/o_que_mudou_web/**/*.*ex"
  ],
  theme: {
    extend: {
      colors: {
        // Semantic tokens — resolve to OKLCH custom properties (light/dark auto).
        // See assets/css/app.css and DESIGN.md.
        bg: "var(--bg)",
        surface: "var(--surface)",
        "surface-inset": "var(--surface-inset)",
        ink: "var(--ink)",
        muted: "var(--muted)",
        border: "var(--border)",
        "rule-strong": "var(--rule-strong)",
        primary: {
          DEFAULT: "var(--primary)",
          hover: "var(--primary-hover)",
          fg: "var(--on-primary)",
        },
        state: {
          "unreviewed-bg": "var(--state-unreviewed-bg)",
          "unreviewed-ink": "var(--state-unreviewed-ink)",
          "community-bg": "var(--state-community-bg)",
          "community-ink": "var(--state-community-ink)",
          "verified-bg": "var(--state-verified-bg)",
          "verified-ink": "var(--state-verified-ink)",
          "error-bg": "var(--state-error-bg)",
          "error-ink": "var(--state-error-ink)",
        },
      },
      fontFamily: {
        sans: ["Inter", "ui-sans-serif", "system-ui", "sans-serif"],
        serif: ["Newsreader", "Georgia", "Times New Roman", "serif"],
        display: ["Fraunces", "Newsreader", "Georgia", "serif"],
      },
      boxShadow: {
        floating: "var(--shadow-floating)",
      },
      transitionTimingFunction: {
        "out-quart": "var(--ease-out-quart)",
      },
      maxWidth: {
        reading: "70ch",
      },
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function({matchComponents, theme}) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"]
      ]
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = {name, fullPath: path.join(iconsDir, dir, file)}
        })
      })
      matchComponents({
        "hero": ({name, fullPath}) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          let size = theme("spacing.6")
          if (name.endsWith("-mini")) {
            size = theme("spacing.5")
          } else if (name.endsWith("-micro")) {
            size = theme("spacing.4")
          }
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            "mask": `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            "width": size,
            "height": size
          }
        }
      }, {values})
    })
  ]
}

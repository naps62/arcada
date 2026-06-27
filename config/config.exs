# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :o_que_mudou,
  ecto_repos: [OQueMudou.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures Oban (background jobs + daily cron).
# The DRE scraper runs on a daily cron; see docs/PLAN.md.
config :o_que_mudou, Oban,
  repo: OQueMudou.Repo,
  queues: [default: 10, scrape: 1, summarize: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron, crontab: []}
  ]

# Configures the endpoint
config :o_que_mudou, OQueMudouWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: OQueMudouWeb.ErrorHTML, json: OQueMudouWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: OQueMudou.PubSub,
  live_view: [signing_salt: "6KZMKO7g"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  o_que_mudou: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  o_que_mudou: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :care_route,
  ecto_repos: [CareRoute.Repo],
  generators: [timestamp_type: :utc_datetime]

# Oban runs Claude API calls as background jobs
config :care_route, Oban,
  engine: Oban.Engines.Basic,
  repo: CareRoute.Repo,
  queues: [ai: 10]

# Anthropic API (key is read at runtime in config/runtime.exs)
config :care_route, :anthropic,
  model: "claude-opus-5",
  base_url: "https://api.anthropic.com"

# Google Gemini API (key is read at runtime in config/runtime.exs).
# When GEMINI_API_KEY is set it takes precedence over Anthropic.
# Models are tried in order; the next one is used when one is overloaded (429/5xx).
config :care_route, :gemini,
  models: ["gemini-3.6-flash", "gemini-3.5-flash", "gemini-3.1-flash-lite"]

# Simulated patient position (Yaya Centre, Nairobi) used for facility distances
# when the browser doesn't share a real location.
config :care_route, :demo_origin, %{lat: -1.2925, lng: 36.7870}

# Configure the endpoint
config :care_route, CareRouteWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CareRouteWeb.ErrorHTML, json: CareRouteWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CareRoute.PubSub,
  live_view: [signing_salt: "FyutmF1y"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :care_route, CareRoute.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  care_route: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  care_route: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

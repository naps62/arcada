defmodule Arcada.PromEx do
  @moduledoc """
  PromEx wiring — exposes Prometheus metrics at `/metrics` (mounted via
  `PromEx.Plug` in the endpoint).

  Prometheus scrapes `http://arcada-app:4000/metrics` over the `dokploy-network`.
  Dashboards are not auto-uploaded (`grafana: :disabled`); the metrics line up
  with the bundled PromEx dashboards which can be imported manually against the
  `prometheus` datasource if desired.
  """
  use PromEx, otp_app: :arcada

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      # App version + dependency info, uptime
      Plugins.Application,
      # BEAM VM: memory, run queues, schedulers, GC
      Plugins.Beam,
      # HTTP request rate/latency/status + channel/socket metrics
      {Plugins.Phoenix, router: ArcadaWeb.Router, endpoint: ArcadaWeb.Endpoint},
      # Ecto query timings (queue/query/decode)
      Plugins.Ecto,
      # Oban queue depth, job duration, success/failure
      Plugins.Oban,
      # LiveView mount/handle_event/handle_params timings
      Plugins.PhoenixLiveView,
      # Search volume by tier + rate-limit degradation (issue #32)
      Arcada.PromEx.SearchMetrics
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"},
      {:prom_ex, "phoenix_live_view.json"}
    ]
  end
end

defmodule Arcada.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Allow LOG_LEVEL to override the configured level at boot.
    LoggerJSON.configure_log_level_from_env!()

    # Emit Oban job lifecycle as structured logs (picked up by the JSON
    # formatter in prod) so job runs are visible in Loki.
    Oban.Telemetry.attach_default_logger(:info)

    children = [
      # PromEx first so it captures init-time telemetry from Ecto/Phoenix/Oban.
      Arcada.PromEx,
      ArcadaWeb.Telemetry,
      Arcada.Repo,
      {DNSCluster, query: Application.get_env(:arcada, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Arcada.PubSub},
      # ETS-backed rate limiter (issue #32); caps semantic-search embedding per
      # caller. Expired buckets are swept every 10 min.
      {Arcada.RateLimit, [clean_period: :timer.minutes(10)]},
      {Oban, Application.fetch_env!(:arcada, Oban)},
      # Runs the semantic leg of a search unlinked (issue #69), so a crashing or
      # killed embedding task degrades to FTS-only instead of taking the visitor
      # LiveView down with it.
      {Task.Supervisor, name: Arcada.Search.TaskSupervisor},
      # Semantic-search index (issue #27): loads summary embeddings into ETS.
      Arcada.Search.Index,
      # Start a worker by calling: Arcada.Worker.start_link(arg)
      # {Arcada.Worker, arg},
      # Start to serve requests, typically the last entry
      ArcadaWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Arcada.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ArcadaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

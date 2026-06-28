defmodule OQueMudou.Application do
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
      OQueMudou.PromEx,
      OQueMudouWeb.Telemetry,
      OQueMudou.Repo,
      {DNSCluster, query: Application.get_env(:o_que_mudou, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: OQueMudou.PubSub},
      {Oban, Application.fetch_env!(:o_que_mudou, Oban)},
      # Start a worker by calling: OQueMudou.Worker.start_link(arg)
      # {OQueMudou.Worker, arg},
      # Start to serve requests, typically the last entry
      OQueMudouWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: OQueMudou.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OQueMudouWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

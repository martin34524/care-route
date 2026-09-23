defmodule CareRoute.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CareRouteWeb.Telemetry,
      CareRoute.Repo,
      {DNSCluster, query: Application.get_env(:care_route, :dns_cluster_query) || :ignore},
      {Oban, Application.fetch_env!(:care_route, Oban)},
      {Phoenix.PubSub, name: CareRoute.PubSub},
      # Start a worker by calling: CareRoute.Worker.start_link(arg)
      # {CareRoute.Worker, arg},
      # Start to serve requests, typically the last entry
      CareRouteWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CareRoute.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CareRouteWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

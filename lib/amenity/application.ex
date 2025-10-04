defmodule Amenity.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AmenityWeb.Telemetry,
      Amenity.Repo,
      {DNSCluster, query: Application.get_env(:amenity, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Amenity.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Amenity.Finch},
      # Registry for trivia game servers
      {Registry, keys: :unique, name: Amenity.Trivia.GameRegistry},
      # DynamicSupervisor for trivia game servers
      {DynamicSupervisor, strategy: :one_for_one, name: Amenity.Trivia.GameSupervisor},
      # Start a worker by calling: Amenity.Worker.start_link(arg)
      # {Amenity.Worker, arg},
      # Start to serve requests, typically the last entry
      AmenityWeb.Endpoint,
      AmenityWeb.Presence
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Amenity.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AmenityWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

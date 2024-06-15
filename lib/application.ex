defmodule Venomous.Application do
  @moduledoc """
    Initializes Snake Managers and handles config
  """
  use Application
  @default_ttl_minutes 15
  @default_cleaner_interval 60_000
  @default_perpetual_workers 10

  def start(_type, _args) do
    children =
      [
        Supervisor.child_spec(
          {Venomous.SnakeManager, snake_manager_specs()},
          id: Venomous.SnakeManager,
          restart: :permanent
        ),
        Supervisor.child_spec(
          {Venomous.PetSnakeManager,
           %{table: :ets.new(:adopted_snake_terrarium, [:set, :public])}},
          id: Venomous.PetSnakeManager,
          restart: :permanent
        )
      ] ++ snake_supervisor_spec()

    opts = [strategy: :one_for_one, name: Venomous.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp snake_manager_specs() do
    table = :ets.new(:snake_terrarium, [:set, :public])

    config = Application.get_env(:venomous, :snake_manager, %{})
    snake_ttl = Map.get(config, :snake_ttl_minutes, @default_ttl_minutes)

    perpetual_workers =
      Map.get(config, :perpetual_workers, @default_perpetual_workers)

    cleaner_interval_ms =
      Map.get(config, :cleaner_interval, @default_cleaner_interval)

    python_opts =
      config
      |> Map.get(:python_opts, [])
      |> Keyword.merge(erlport_encoder: Map.get(config, :erlport_encoder, %{}))

    %{
      table: table,
      snake_ttl_minutes: snake_ttl,
      perpetual_workers: perpetual_workers,
      cleaner_interval_ms: cleaner_interval_ms,
      python_opts: python_opts
    }
  end

  defp snake_supervisor_spec() do
    if Application.get_env(:venomous, :snake_supervisor_enabled, false) do
      [
        {Venomous.SnakeSupervisor, [strategy: :one_for_one, max_restarts: 0, max_children: 50]},
        {Venomous.PetSnakeSupervisor, [strategy: :one_for_one, max_children: 10]}
      ]
    else
      []
    end
  end
end

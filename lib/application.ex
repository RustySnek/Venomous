defmodule Venomous.Application do
  @moduledoc """
    Initializes Snake Manager/Supervisor/Watcher and handles config
  """
  use Application
  @default_ttl_minutes 15
  @default_cleaner_interval 60_000
  @default_perpetual_workers 10
  @default_serpent_config [
    logging: true,
    module: :serpent_watcher,
    func: :watch_directories,
    manager_pid: Venomous.SnakeManager
  ]

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
      ] ++
        snake_supervisor_spec() ++
        watch_serpent_spec()

    opts = [strategy: :one_for_one, name: Venomous.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp snake_manager_specs do
    table = :ets.new(:snake_terrarium, [:set, :public])

    config = Application.get_env(:venomous, :snake_manager, %{})
    snake_ttl = Map.get(config, :snake_ttl_minutes, @default_ttl_minutes)

    perpetual_workers =
      Map.get(config, :perpetual_workers, @default_perpetual_workers)

    cleaner_interval_ms =
      Map.get(config, :cleaner_interval, @default_cleaner_interval)

    reload_module = Map.get(config, :reload_module, :reload)

    python_opts = python_opts(config)

    %{
      table: table,
      snake_ttl_minutes: snake_ttl,
      perpetual_workers: perpetual_workers,
      cleaner_interval_ms: cleaner_interval_ms,
      python_opts: python_opts,
      reload_module: reload_module
    }
  end

  defp watch_serpent_spec do
    config = Application.get_env(:venomous, :serpent_watcher, [])

    case Keyword.get(config, :enable, false) do
      true ->
        serpent_opts =
          python_opts()
          |> Keyword.merge(@default_serpent_config)
          |> Keyword.merge(config)

        [
          Supervisor.child_spec(
            {Venomous.SerpentWatcher, serpent_opts},
            id: Venomous.SerpentWatcher,
            restart: :permanent
          )
        ]

      false ->
        []
    end
  end

  defp snake_supervisor_spec do
    if Application.get_env(:venomous, :test_snake_supervisor, false) do
      [
        {Venomous.SnakeSupervisor, [strategy: :one_for_one, max_restarts: 0, max_children: 50]},
        {Venomous.PetSnakeSupervisor, [strategy: :one_for_one, max_children: 10]}
      ]
    else
      []
    end
  end

  defp python_opts(env \\ Application.get_env(:venomous, :snake_manager, %{})) do
    env
    |> Map.get(:python_opts, [])
    |> Keyword.merge(erlport_encoder: Map.get(env, :erlport_encoder, %{}))
  end
end

defmodule Venomous.Application do
  @moduledoc """
  This module initializes the application supervision tree.
  It starts the supervisor for managing SnakeManager process.
  """
  use Application

  def start(_type, _args) do
    children =
      [
        Supervisor.child_spec(
          {Venomous.SnakeManager, snake_manager_specs()},
          id: Venomous.SnakeManager,
          restart: :permanent
        )
      ] ++ snake_supervisor_spec()

    opts = [strategy: :one_for_one, name: Venomous.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp snake_manager_specs() do
    table = :ets.new(:snake_terrarium, [:set, :public])

    %{
      table: table,
      snake_ttl_minutes: 0,
      perpetual_workers: 0,
      cleaner_interval_ms: 100_000
    }
  end

  defp snake_supervisor_spec() do
    if Application.get_env(:venomous, :snake_supervisor_enabled, false) do
      [{Venomous.SnakeSupervisor, [strategy: :one_for_one, max_restarts: 0, max_children: 50]}]
    else
      []
    end
  end
end

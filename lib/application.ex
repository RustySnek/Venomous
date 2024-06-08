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
          {Venomous.SnakeManager, :ets.new(:snake_terrarium, [:set, :public])},
          id: Venomous.SnakeManager,
          restart: :permanent
        )
      ] ++ snake_supervisor_spec()

    opts = [strategy: :one_for_one, name: Venomous.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp snake_supervisor_spec() do
    if Application.get_env(:venomous, :snake_supervisor_enabled, false) do
      [{Venomous.SnakeSupervisor, [strategy: :one_for_one, max_restarts: 0, max_children: 50]}]
    else
      []
    end
  end
end

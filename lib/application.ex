defmodule Venomous.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Venomous.SnakeSupervisor, [strategy: :one_for_one, max_restarts: 0, max_children: 50]},
      Supervisor.child_spec(
        {Venomous.SnakeManager, :ets.new(:snake_terrarium, [:set, :public])},
        id: Venomous.SnakeManager,
        restart: :permanent
      )
    ]

    opts = [strategy: :one_for_one, name: Venomous.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

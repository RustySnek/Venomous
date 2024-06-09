![Venomous](https://github.com/RustySnek/Venomous/blob/master/assets/venomous_logo.png)

> A wrapper for managing concurrent [Erlport](http://erlport.org/) Python processes with ease.

[![CI](https://github.com/rustysnek/venomous/actions/workflows/elixir.yml/badge.svg)](https://github.com/rustysnek/venomous/actions/workflows/elixir.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/venomous)](https://hex.pm/packages/venomous)
[![Hex.pm](http://img.shields.io/hexpm/dt/venomous.svg)](https://hex.pm/packages/venomous)
## Installation
Add `:venomous` to your list of dependencies in `mix.exs`:
```elixir
def deps do
  [
    {:venomous, "~> 0.1.1"}
  ]
end
```
## Getting Started  
  Check the [documentation](https://hexdocs.pm/venomous) for more in-depth information.
  
  For custom type conversion read [Erlport documentation](http://erlport.org/docs/python.html#custom-data-types)
  ### Configure the SnakeManager options
  ```elixir
  config :venomous, :snake_manager, %{
    # Optional :erlport encoder/decoder for type conversion between elixir/python applied to all workers.
    erlport_encoder: %{
      module: :my_encoder_module,
      func: :encode_my_snakes_please,
      args: []
    },
    # TTL whenever python process is inactive. Default: 15
    snake_ttl_minutes: 10,
    # Number of python workers that don't get cleared by SnakeManager when their TTL while inactive ends. Default: 10
    perpetual_workers: 1,
    # Interval for killing python processes past their ttl while inactive. Default: 60_000ms (1 min)
    cleaner_interval: 5_000
  }
  ```
  ### Configure the SnakeSupervisor to start on application boot.
  ```elixir
  defmodule YourApp.Application do
    @moduledoc false

    use Application

    @doc false
    def start(_type, _args) do
      children = [
        {Venomous.SnakeSupervisor, [strategy: :one_for_one, max_restarts: 0, max_children: 50]}
      ]
      opts = [strategy: :one_for_one, name: YourApp.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end
  ```

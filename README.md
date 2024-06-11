![Venomous](https://github.com/RustySnek/Venomous/blob/master/assets/venomous_logo.png)

> A wrapper for managing concurrent [Erlport](http://erlport.org/) Python processes with ease.

[![CI](https://github.com/rustysnek/venomous/actions/workflows/elixir.yml/badge.svg)](https://github.com/rustysnek/venomous/actions/workflows/elixir.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/venomous)](https://hex.pm/packages/venomous)
[![Hex.pm](http://img.shields.io/hexpm/dt/venomous.svg)](https://hex.pm/packages/venomous)

Venomous is a wrapper around erlport python Ports, designed to simplify concurrent use. It focuses on dynamic extensibility, like spawning, reusing and killing processes on demand. Furthermore, unused processes get automatically killed by scheduled process which can be configured inside config.exs. Venomous core functions capture and handle :EXIT calls ensuring that all python process die with it and do not continue their execution.

## Installation
Add `:venomous` to your list of dependencies in `mix.exs`:
```elixir
def deps do
  [
    {:venomous, "~> 0.2.0"}
  ]
end
```
## Getting Started  
  Check the [documentation](https://hexdocs.pm/venomous) for more in-depth information.
  
  For custom type conversion see the [Handling Erlport API](https://github.com/RustySnek/Venomous/blob/master/PYTHON.md)
  ### Configure the SnakeManager options
  ```elixir
  config :venomous, :snake_manager, %{
    # Optional :erlport encoder/decoder for type conversion between elixir/python applied to all workers. The function may also include any :erlport callbacks from python api
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

## Quickstart
### Basic way to call python process
```elixir
alias Venomous.SnakeArgs
import Venomous

timeout = 1_000
args = SnakeArgs.from_params(:builtins, :sum, [[0,1,2,3,4,5]])

case python(args, timeout) do
    {:retrieve_error, msg} -> "No Snakes? #{inspect(msg)}"
    %{error: :timeout} -> "We timed out..."
    sum -> assert sum == 15
end

# or just use python!/3 which waits for the available snake.
timeout = :infinity
assert python!(args, timeout) == 15
```
### Concurrency and :EXIT signals
Venomous is designed with concurrency, as well as proper exits in mind.
```elixir
alias Venomous.SnakeArgs
import Venomous

# Venomous can handle as much concurrent python as you've setup
# in your snake_manager configuration. However the python! will
# wait for any process to free up in case none are available.
args = SnakeArgs.from_params(:time, :sleep, [0.5])
Enum.map(1..100, fn _ -> 
    Task.async(fn ->
        python!(args)
    end)
end) |> Task.await_many(5_000)

# You can view the spawned and ready snakes using the list_alive_snakes() 
list_alive_snakes() |> dbg
```
```elixir
alias Venomous.SnakeArgs
import Venomous

# Venomous kills the OS pid of the python process on :EXIT
# ensuring the process will not proceed with the execution further
Enum.map(1..200, fn _ ->
  {:ok, pid} =
    Task.start(fn ->
      SnakeArgs.from_params(:time, :sleep, [1000]) |> python!()
    end)

  pid
end)
|> Enum.each(fn pid ->
  Process.send_after(pid, {:EXIT, :snake_slithered_away}, 100)
end)

# We'll sleep to make sure all exits got sent.
Process.sleep(1_000)
assert list_alive_snakes() == []
```

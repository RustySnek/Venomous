defmodule Venomous do
  @moduledoc """
  Venomous is the main module for managing concurrent Python processes using Erlport in an Elixir application.

  The core concept revolves around "Snakes" which represent Python worker processes. These `Venomous.SnakeWorker` are managed and supervised with `Venomous.SnakeManager` GenServer to allow concurrent and efficient execution of Python code. The `Snakes` pids and python pids are stored inside `:ets` table and the Processes are handled by `DymanicSupervisor` called `Venomous.SnakeSupervisor`. The unused `Snakes` get automatically killed by `SnakeManager` depending on the given configuration.

  ## Main Functionality

  - `python/2`: The primary function to execute a Python function. It retrieves a Snake (Python worker process) and runs the specified Python function using the arguments provided in a `SnakeArgs` struct. If no ready Snakes are available, a new one is spawned. If max_children is reached it will return an error with appropriate message.
  - `python!/3` | `python!/1`: Will wait until any `Venomous.SnakeWorker` is freed, requesting it with the given interval. 

  ## Architecture

  Venomous consists of several key components:

  - `Venomous.SnakeWorker`: Manages the execution of Python processes.
  - `Venomous.SnakeSupervisor`: A DynamicSupervisor that oversees the SnakeWorkers.
  - `Venomous.SnakeManager`: A GenServer that coordinates the SnakeWorkers and handles operations like spawning, retrieval and cleanup.

  ## Configuration Options

  The behavior and management of Snakes can be configured through the following options:

  - `erlport_encoder: %{module: atom(), func: atom(), args: list(any())}`: Optional :erlport encoder/decoder python function for converting types.
  - `snake_ttl_minutes: non_neg_integer()`: Time-to-live for a Snake in minutes. Default is 15 min.
  - `perpetual_workers: non_neg_integer()`: Number of Snakes to keep alive perpetually. Default is 10.
  - `cleaner_interval_ms: non_neg_integer()`: Interval in milliseconds for cleaning up inactive Snakes. Default is 60_000 ms.

  ## Auxiliary Functions

  - `list_alive_snakes/0`: Returns a list of :ets table containing currently alive Snakes.
  - `clean_inactive_snakes/0`: Manually clears inactive Snakes depending on their ttl and returns the number of Snakes cleared.
  - `slay_python_worker/1`: Kills a specified Python worker process and its SnakeWorker.

  """
  alias Venomous.SnakeArgs
  alias Venomous.SnakeManager

  @wait_for_snake_interval 100
  @default_timeout 15_000
  @default_interval 200

  @doc "Returns list of :ets table containing alive snakes"
  @spec list_alive_snakes() :: list({pid(), pid(), atom(), any()})
  def list_alive_snakes(), do: GenServer.call(SnakeManager, :list_snakes)

  @spec clean_inactive_snakes() :: non_neg_integer()
  @doc "Clears inactive snakes manually, returns number of snakes cleared"
  def clean_inactive_snakes(), do: GenServer.call(SnakeManager, :clean_inactive_workers)

  @doc """
  Kills python process and its SnakeWorker
  ## Parameters
    - SnakeWorker pid
    - Python pid
  ## Returns 
    :ok
  """
  @spec slay_python_worker({pid(), pid()}) :: :ok
  def slay_python_worker({pid, pypid}) do
    :python.stop(pypid)
    send(SnakeManager, {:sacrifice_snake, pid})
  end

  defp get_snakes_ready(0, acc), do: acc

  defp get_snakes_ready(amount, acc) do
    case retrieve_snake() do
      {:retrieve_error, _} -> acc
      pids -> get_snakes_ready(amount - 1, [pids | acc])
    end
  end

  @spec get_snakes_ready(non_neg_integer()) :: list({pid(), pid()})
  @doc """
  Retrieves x amount of ready snakes. In case of hitting max_children cap, stops and returns all available snakes.
  ## Parameters
    - amount of snakes to retrieve

  ## Returns
    - A list of tuples `{pid, pid}`

  """
  def get_snakes_ready(amount) when is_integer(amount), do: get_snakes_ready(amount, [])

  @spec retrieve_snake() :: {:retrieve_error, reason :: term()} | {pid(), pid()}
  @doc """
  Retrieves ready SnakeWorker and python pids.
  If all processes are busy and exceeds max_children will return {:retrieve_error, message}.

  ## Returns
    - A tuple `{pid, pid}` containing the process IDs of the SnakeWorker and python processes. In case of error `{:retrieve_error, message}`
  """
  def retrieve_snake(), do: GenServer.call(SnakeManager, :get_ready_snake, :infinity)

  @spec retrieve_snake!(non_neg_integer()) :: {pid(), pid()}
  @doc """
  Retrieves ready SnakeWorker and python pids.
  The worker is then set to :busy until its ran with snake_run(), preventing it from getting removed automatically or used by other process
  If all processes are busy and exceeds max_children will wait for interval ms and try again.
  ## Parameters
    - interval: The time to wait in milliseconds before retrying. Default is `@wait_for_snake_interval`.

  ## Returns
    - A tuple `{pid, pid}` containing the process IDs of the SnakeWorker and python processes.
  """
  def retrieve_snake!(interval \\ @wait_for_snake_interval) do
    case retrieve_snake() do
      {:retrieve_error, _} ->
        Process.sleep(interval)
        retrieve_snake!(interval)

      process_ids ->
        process_ids
    end
  end

  @doc """
  Runs given %SnakeArgs{} inside given Snake pids.
  ## Parameters
    - %SnakeArgs{} struct of :module, :func, :args 
    - {pid, pypid} tuple containing SnakeWorker pid and python pid
    - python_timeout \\ @default_timeout non_neg_integer() | :infinity Timeout for python call.
      In case of timeout it will kill python worker/process and return {error: "timeout"}

  ## Returns 
    - any() | {error: "timeout"} | %SnakeError{} retrieves output of python function or error

  """
  @spec snake_run(SnakeArgs.t(), {pid(), pid()}, non_neg_integer()) :: any()
  def snake_run(%SnakeArgs{} = snake_args, {pid, pypid}, python_timeout \\ @default_timeout) do
    GenServer.call(pid, {:run_snake, self(), snake_args})

    receive do
      {:EXIT, _from, _type} ->
        slay_python_worker({pid, pypid})
        exit(:normal)

      {:EXIT, _type} ->
        slay_python_worker({pid, pypid})
        exit(:normal)

      {:SNAKE_DONE, data} ->
        GenServer.call(SnakeManager, {:employ_snake, pid, pypid}, :infinity)
        data

      {:SNAKE_ERROR, error} ->
        slay_python_worker({pid, pypid})
        error
    after
      python_timeout ->
        slay_python_worker({pid, pypid})
        %{error: "timeout"}
    end
  end

  @doc """
  Wrapper for python workers
  Tries to retrieve SnakeWorker which then runs given function inside given module with args. In case of failure will return {:error, message}.
  In case :EXIT happens, it will kill python worker/process and exit(:normal)
  ## Parameters
    - %SnakeArgs{} struct of :module, :func, :args 
    - python_timeout \\ @default_timeout non_neg_integer() | :infinity Timeout for python call.
      In case of timeout it will kill python worker/process and return {error: "timeout"}

  ## Returns 
    - any() | {error: "timeout"} | {error: any()} retrieves output of python function or error
  """
  @spec python(SnakeArgs.t(), non_neg_integer()) :: any()
  def python(%SnakeArgs{} = snake_args, python_timeout \\ @default_timeout) do
    case retrieve_snake() do
      {:retrieve_error, msg} -> {:retrieve_error, msg}
      pids -> snake_args |> snake_run(pids, python_timeout)
    end
  end

  @doc "If no Snake is available will continue requesting it with the given interval until any gets freed"
  @spec python!(SnakeArgs.t(), non_neg_integer(), non_neg_integer()) :: any()
  def python!(
        %SnakeArgs{} = snake_args,
        python_timeout \\ @default_timeout,
        retrieve_interval \\ @default_interval
      ) do
    snake_pids = retrieve_snake!(retrieve_interval)
    snake_args |> snake_run(snake_pids, python_timeout)
  end
end

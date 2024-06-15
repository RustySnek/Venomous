defmodule Venomous do
  @moduledoc """
  Venomous is a wrapper around erlport python Ports, designed to simplify concurrent use. It focuses dynamic extensibility, like spawning, reusing and killing processes on demand. Furthermore, unused processes get automatically killed by scheduled process which can be configured inside config.exs. Venomous core functions capture and handle :EXIT calls ensuring that all python process die with it and do not continue their execution.

  The core concept revolves around "Snakes" which represent Python worker processes. These `Venomous.SnakeWorker` are managed and supervised with `Venomous.SnakeManager` GenServer to allow concurrent and efficient execution of Python code. The `Snakes` pids and python pids are stored inside `:ets` table and the Processes are handled by `DymanicSupervisor` called `Venomous.SnakeSupervisor`. The unused `Snakes` get automatically killed by `SnakeManager` depending on the given configuration.

  ## Main Functionality

  - `python/2`: The primary function to execute a Python function. It retrieves a Snake (Python worker process) and runs the specified Python function using the arguments provided in a `SnakeArgs` struct. If no ready Snakes are available, a new one is spawned. If max_children is reached it will return an error with appropriate message.
  - `python!/2` | `python!/1`: Will wait until any `Venomous.SnakeWorker` is freed, requesting it with the given interval. 

  ## Architecture

  Venomous consists of several key components:

  - `Venomous.SnakeWorker`: Manages the execution of Python processes.
  - `Venomous.SnakeSupervisor`: A DynamicSupervisor that oversees the SnakeWorkers.
  - `Venomous.SnakeManager`: A GenServer that coordinates the SnakeWorkers and handles operations like spawning, retrieval and cleanup.

  ## Configuration Options

  The behavior and management of Snakes can be configured through the following options inside :venomous :snake_manager config key:

  - `erlport_encoder: %{module: atom(), func: atom(), args: list(any())}`: Optional :erlport encoder/decoder python function for converting types. This function is applied to every unnamed python process started by SnakeManager. For more information see [Handling Erlport API](PYTHON.md)
  - `snake_ttl_minutes: non_neg_integer()`: Time-to-live for a Snake in minutes. Default is 15 min.
  - `perpetual_workers: non_neg_integer()`: Number of Snakes to keep alive perpetually. Default is 10.
  - `cleaner_interval: non_neg_integer()`: Interval in milliseconds for cleaning up inactive Snakes. Default is 60_000 ms.

  ## Auxiliary Functions

  - `list_alive_snakes/0`: Returns a list of :ets table containing currently alive Snakes.
  - `clean_inactive_snakes/0`: Manually clears inactive Snakes depending on their ttl and returns the number of Snakes cleared.
  - `slay_python_worker/2`: Kills a specified Python worker process and its SnakeWorker. :brutal can be specified as option, which will `kill -9` the os process of python which prevents the code from executing until it finalizes or goes through iteration.

  """
  alias Venomous.SnakeWorker
  alias Venomous.SnakeArgs
  alias Venomous.SnakeManager

  @wait_for_snake_interval 100
  @default_timeout 15_000
  @default_interval 200

  @doc "Returns list of :ets table containing alive snakes"
  @spec list_alive_snakes() :: list({pid(), pid(), non_neg_integer(), atom(), any()})
  def list_alive_snakes(), do: GenServer.call(SnakeManager, :list_snakes)

  @spec clean_inactive_snakes() :: non_neg_integer()
  @doc "Clears inactive snakes manually, returns number of snakes cleared."
  def clean_inactive_snakes(), do: GenServer.call(SnakeManager, :clean_inactive_workers)

  @doc """
  Kills python process and its SnakeWorker
  :brutal also kills the OS process of python, ensuring the process does not continue execution.
  ## Parameters
    - SnakeWorker pid, Python pid tuple
    - a Way to kill process. default: :brutal additionally kills with kill -9 ensuring the python does not execute further
  ## Returns 
    :ok
  """
  @spec slay_python_worker(SnakeWorker.t(), atom() | SnakeWorker.t()) :: :ok
  def slay_python_worker(
        %SnakeWorker{pid: pid, pypid: pypid, os_pid: os_pid},
        termination_style \\ :peaceful
      ) do
    send(SnakeManager, {:sacrifice_snake, pid})
    # We exterminate the snake in the sanest way possible.
    if termination_style == :brutal, do: System.cmd("kill", ["-9", "#{os_pid}"])

    :ok
  end

  defp get_snakes_ready(0, acc), do: acc

  defp get_snakes_ready(amount, acc) do
    case retrieve_snake() do
      {:retrieve_error, _} -> acc
      pids -> get_snakes_ready(amount - 1, [pids | acc])
    end
  end

  @spec get_snakes_ready(non_neg_integer()) :: list(SnakeWorker.t())
  @doc """
  Retrieves x amount of ready snakes. In case of hitting max_children cap, stops and returns all available snakes.
  ## Parameters
    - amount of snakes to retrieve

  ## Returns
    - A list of tuples `{pid, pid}`

  """
  def get_snakes_ready(amount)
      when is_integer(amount),
      do: get_snakes_ready(amount, [])

  @spec retrieve_snake() :: {:retrieve_error, reason :: term()} | SnakeWorker.t()
  @spec retrieve_snake(boolean()) :: {:retrieve_error, reason :: term()} | SnakeWorker.t()
  @doc """
  Retrieves ready SnakeWorker and python pids.
  If all processes are busy and exceeds max_children will return {:retrieve_error, message}.

  ## Returns
    - A tuple `{pid, pid}` containing the process IDs of the SnakeWorker and python processes. In case of error `{:retrieve_error, message}`
  """
  def retrieve_snake(set_ready \\ false) do
    GenServer.call(SnakeManager, :get_ready_snake, :infinity)
  end

  @spec retrieve_snake!(non_neg_integer()) :: SnakeWorker.t()
  @doc """
  Retrieves ready SnakeWorker and python pids.
  The worker is then set to :busy until its ran with snake_run(), preventing it from getting removed automatically or used by other process
  If all processes are busy and exceeds max_children will wait for interval ms and try again. Traps the exit signals, to safely escape loop.
  ## Parameters
   - interval: The time to wait in milliseconds before retrying. Default is `@wait_for_snake_interval`.

  ## Returns
    - A tuple `{pid, pid}` containing the process IDs of the SnakeWorker and python processes.
  """
  def retrieve_snake!(interval \\ @wait_for_snake_interval) do
    Process.flag(:trap_exit, true)

    case retrieve_snake() do
      {:retrieve_error, _} ->
        receive do
          {:EXIT, reason} ->
            exit(reason)

          {:EXIT, _from, reason} ->
            exit(reason)
        after
          interval ->
            retrieve_snake!(interval)
        end

      process_ids ->
        process_ids
    end
  end

  @doc """
  Runs given %SnakeArgs{} inside given Snake pids. Takes in a python_timeout which brutally kills the python process after surpassing it.
  Traps exit and awaits signals [:SNAKE_DONE, :SNAKE_ERROR, :EXIT]
  In case of an exit, brutally kills the python process ensuring it doesn't get executed any further.

  ## Parameters
    - %SnakeArgs{} struct of :module, :func, :args 
    - {pid, pypid} tuple containing SnakeWorker pid and python pid
    - opts \\ []
  ## Opts
  - `:python_timeout` ms timeout. Kills python OS process on timeout. Default: 15_000
  - `:kill_python_on_exception` Should python process be killed on exception. Should be fine to set to `true` if your are sure the Python process won't exit(). In case exit() happens and it's set to true, Python will never reply, waiting till timeout. Default: false


  ## Returns 
    - any() | {error: :timeout} | %SnakeError{} retrieves output of python function or error

  """
  @spec snake_run(SnakeArgs.t(), SnakeWorker.t(), keyword()) :: any()
  @spec snake_run(SnakeArgs.t(), SnakeWorker.t()) :: any()
  def snake_run(
        %SnakeArgs{} = snake_args,
        %SnakeWorker{pid: pid, pypid: _pypid, os_pid: _os_pid} = worker,
        opts \\ []
      ) do
    Process.flag(:trap_exit, true)
    python_timeout = Keyword.get(opts, :python_timeout, @default_timeout)
    kill_python_on_exception = Keyword.get(opts, :kill_on_exception, true)

    GenServer.call(SnakeManager, {:molt_snake, :busy, worker}, :infinity)

    try do
      GenServer.call(pid, {:run_snake, self(), snake_args})
    catch
      :exit, _reason ->
        slay_python_worker(worker, :brutal)
    end

    receive do
      {:EXIT, _from, reason} ->
        slay_python_worker(worker, :brutal)
        exit(reason)

      {:EXIT, reason} ->
        slay_python_worker(worker, :brutal)
        exit(reason)

      {:SNAKE_DONE, data} ->
        GenServer.call(SnakeManager, {:molt_snake, :ready, worker})
        data

      {:SNAKE_ERROR, error} ->
        if kill_python_on_exception do
          slay_python_worker(worker)
        else
          GenServer.call(SnakeManager, {:molt_snake, :ready, worker})
        end

        error
    after
      python_timeout ->
        slay_python_worker(worker, :brutal)
        %{error: :timeout}
    end
  end

  @doc """
  Wrapper for python workers
  Tries to retrieve `Venomous.SnakeWorker` which then runs given function inside module with args. In case of failure will return {:error, message}.
  In case :EXIT happens, it will kill python worker/process and exit(reason)
  ## Parameters
    - %SnakeArgs{} struct of :module, :func, :args 
    - opts \\ []
  ## Opts
  - `:python_timeout` ms timeout. Kills python OS process on timeout. Default: 15_000
  - `:kill_python_on_exception` Should python process be killed on exception. Should be fine to set to `true` if your are sure the Python process won't exit(). In case exit() happens and it's set to true, Python will never reply, waiting till timeout. Default: false

  ## Returns 
    - any() | {error: :timeout} | {error: any()} retrieves output of python function or error
  """
  @spec python(SnakeArgs.t(), keyword()) :: any()
  @spec python(SnakeArgs.t()) :: any()
  def python(%SnakeArgs{} = snake_args, opts \\ []) do
    case retrieve_snake() do
      {:retrieve_error, msg} -> {:retrieve_error, msg}
      pids -> snake_args |> snake_run(pids, opts)
    end
  end

  @doc """
  If no Snake is available will continue requesting it with the given interval until any gets freed or receives :EXIT signal
  ## Opts
  - `:retrieve_interval` ms to wait before requesting snake again Default: 200
  - `:python_timeout` ms timeout. Kills python OS process on timeout. Default: 15_000
  - `:kill_python_on_exception` Should python process be killed on exception. Should be fine to set to `true` if your are sure the Python process won't exit(). In case exit() happens and it's set to true, Python will never reply, waiting till timeout. Default: false
  """
  @spec python!(SnakeArgs.t(), keyword()) :: any()
  @spec python!(SnakeArgs.t()) :: any()
  def python!(
        %SnakeArgs{} = snake_args,
        opts \\ []
      ) do
    {interval, opts} = Keyword.pop(opts, :retrieve_interval, @default_interval)

    snake_pids = retrieve_snake!(interval)
    snake_args |> snake_run(snake_pids, opts)
  end
end

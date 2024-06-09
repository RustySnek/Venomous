defmodule Venomous do
  @moduledoc """
  Wrapper for SnakeManager GenServer used for running Python processes.
  """
  alias Venomous.SnakeArgs
  alias Venomous.SnakeManager

  @wait_for_snake_interval 100
  @default_timeout 15_000

  @doc "Returns list of :ets table"
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
      {:error, _} -> acc
      pids -> get_snakes_ready(amount - 1, [pids | acc])
    end
  end

  @spec get_snakes_ready(non_neg_integer()) :: list({pid(), pid()})
  @doc """
  Retrieves x amount of ready snakes. In case of :error, stops and returns all available snakes.

  ## Parameters
    - amount of snakes to retrieve

  ## Returns
    - A list of tuples `{pid, pid}`

  """
  def get_snakes_ready(amount) when is_integer(amount), do: get_snakes_ready(amount, [])

  @spec retrieve_snake() :: {:error, reason :: term()} | {pid(), pid()}
  @doc """
  Retrieves ready SnakeWorker and python pids.
  If all processes are busy and exceeds max_children will return {:error, message}.

  ## Returns
    - A tuple `{pid, pid}` containing the process IDs of the SnakeWorker and python processes. In case of error `{:error, message}`
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
      {:error, _} ->
        Process.sleep(interval)
        retrieve_snake!(interval)

      process_ids ->
        process_ids
    end
  end

  @doc """

  ## Parameters
    - %SnakeArgs{} struct of :module, :func, :args 
    - {pid, pypid} tuple containing SnakeWorker pid and python pid
    - python_timeout \\ @default_timeout non_neg_integer() | :infinity Timeout for python call.
      In case of timeout it will kill python worker/process and return {error: "timeout"}

  ## Returns 
    - any() | {error: "timeout"} | {error: any()} retrieves output of python function or error

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
  Waits for available SnakeWorker which then runs given function inside given module with args
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
    snake = retrieve_snake!()
    snake_args |> snake_run(snake, python_timeout)
  end
end

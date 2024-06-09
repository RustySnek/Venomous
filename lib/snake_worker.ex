defmodule Venomous.SnakeWorker do
  @moduledoc """
  🔨🐍
  A brave snake worker slithering across...

  This module defines a GenServer that manages a snake worker, which interacts with a Python process to execute specified functions asynchronously.
  The main :run_snake call, creates a `Task.async/1` which calls python and handles exceptions returning python result or an Error struct which gets sent with signal to the caller process. This `Task` gets awaited inside the :run cast(). The original call() returns :ok

  ## Features

  - Starts and initializes a Python process.
  - Executes Python functions with given arguments.
  - Handles the results of the Python function calls, including errors.
  - Returns the result with a signal to caller process

  ## Process Lifecycle

  - On initialization, the worker starts a Python process.
  - If provided, the worker initializes an encoder by calling a specified Python function with arguments.
  - The worker can run Python functions on demand and return the results to the caller.
  """
  alias Venomous.SnakeManager
  alias Venomous.SnakeArgs
  alias Venomous.SnakeError
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    case :python.start() do
      {:error, reason} ->
        # please no snake crashing...
        {:EXIT, reason}

      {:ok, pypid} ->
        case args do
          %{:module => module, :func => func, :args => args} ->
            {:ok, pypid, {:continue, {:init_encoder, module, func, args}}}

          _ ->
            {:ok, pypid}
        end
    end
  end

  def handle_continue({:init_encoder, module, func, args}, pypid) do
    :python.call(pypid, module, func, args)
    {:noreply, pypid}
  end

  def handle_call(:get_pypid, _from, pypid) do
    {:reply, pypid, pypid}
  end

  def handle_call({:run_snake, origin, %SnakeArgs{} = snake_args}, from, pypid) do
    task =
      Task.async(fn ->
        data =
          try do
            :python.call(pypid, snake_args.module, snake_args.func, snake_args.args)
          rescue
            error ->
              case error do
                %ErlangError{original: {:python, exception, error, backtrace}} ->
                  %SnakeError{
                    exception: exception,
                    error: error,
                    backtrace: backtrace
                  }

                exception ->
                  exception
              end
          end

        case data do
          %{:error => _} ->
            send(origin, {:SNAKE_ERROR, data})

          _ ->
            send(origin, {:SNAKE_DONE, data})
        end
      end)

    GenServer.cast(self(), {:run, task})
    GenServer.reply(from, :ok)
    {:noreply, pypid}
  end

  def terminate(_reason, pypid) do
    GenServer.call(SnakeManager, {:remove_snake, self()})
    :python.stop(pypid)
  end

  def handle_cast({:run, task}, pypid) do
    Task.await(task, :infinity)
    {:noreply, pypid}
  end
end

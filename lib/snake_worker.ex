defmodule Venomous.SnakeWorker do
  @moduledoc """
  🔨🐍
  A brave snake worker slithering across...

  This module defines a GenServer that manages a snake worker, which interacts with a Python process to execute specified functions asynchronously.
  The main :run_snake call, creates a `Task.async/1` which calls python and handles exceptions returning python result or an Error struct which gets sent with signal to the caller process. This `Task` gets awaited inside the :run cast(). The original call() returns :ok

  ## Configuration
    Python options can be configured inside :venomous :python_opts config key
    All of these are optional. However you will most likely want to set module_paths
   ```elixir
    @available_opts [
    :module_paths, # List of paths to your python modules
    :cd, # Change python's directory on spawn. Default is $PWD
    :compressed, # Can be set from 0-9. May affect performance. Read more on [Erlport documentation](http://erlport.org/docs/python.html#erlang-api)
    :envvars, # additional python process envvars
    :packet_bytes, # Size of erlport python packet. Default: 4 = max 4GB of data. Can be set to 1 = 256 bytes or 2 = ? bytes if you are sure you won't be transfering a lot of data.
    :python_executable # path to python executable to use.
  ]
  ``` 

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
  alias Venomous.SnakeArgs
  alias Venomous.SnakeError
  alias Venomous.SnakeManager
  use GenServer
  require Logger

  defstruct [
    :pid,
    :pypid,
    :os_pid
  ]

  @type t() :: %__MODULE__{
          pid: pid(),
          pypid: pid(),
          os_pid: non_neg_integer()
        }

  @available_opts [
    :module_paths,
    :cd,
    :compressed,
    :envvars,
    :packet_bytes,
    :python_executable
  ]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  defp construct_python_opts({:module_paths, paths}) when is_list(paths) do
    {:python_path, Enum.map(paths, &to_charlist(&1))}
  end

  defp construct_python_opts({:module_paths, path}) when is_binary(path) do
    {:python_path, to_charlist(path)}
  end

  defp construct_python_opts({:envvars, vars}) when is_list(vars) do
    {:env, Enum.map(vars, fn {key, val} -> {to_charlist(key), to_charlist(val)} end)}
  end

  defp construct_python_opts({:python_executable, path}) when is_binary(path) do
    {:python, to_charlist(path)}
  end

  defp construct_python_opts({:packet_bytes, bytes}) when is_integer(bytes) do
    {:packet, bytes}
  end

  defp construct_python_opts(keyword), do: keyword

  def init(opts) do
    {encoder, opts} = Keyword.pop(opts, :erlport_encoder)

    opts = opts |> Keyword.take(@available_opts) |> Keyword.new(&construct_python_opts(&1))

    case :python.start_link(opts) do
      {:error, reason} ->
        # please no snake crashing...
        Logger.error("FAILED TO START PYTHON PROCESS")
        {:EXIT, reason}

      {:ok, pypid} ->
        case encoder do
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

  @spec handle_call(:get_pypid, pid(), pid()) :: %__MODULE__{}
  def handle_call(:get_pypid, _from, pypid) do
    {:reply,
     %__MODULE__{
       pid: self(),
       pypid: pypid,
       os_pid: get_os_pid(pypid)
     }, pypid}
  end

  def handle_call({:run_snake, origin, %SnakeArgs{} = snake_args}, _from, pypid) do
    Task.start(fn ->
      data =
        try do
          :python.call(pypid, snake_args.module, snake_args.func, snake_args.args)
        rescue
          error ->
            error_message =
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

            %{error: error_message}
        end

      case data do
        %{:error => error_data} ->
          send(origin, {:SNAKE_ERROR, error_data})

        _ ->
          send(origin, {:SNAKE_DONE, data})
      end
    end)

    {:reply, :ok, pypid}
  end

  def terminate(_reason, pypid) do
    GenServer.call(SnakeManager, {:remove_snake, self()})
    :python.stop(pypid)
  end

  defp get_os_pid(pypid) do
    {_, _, _, port, _, _} = :sys.get_state(pypid)
    info = port |> Port.info()
    info[:os_pid]
  end
end

defmodule Venomous do
  @moduledoc """
  Venomous is a wrapper around erlport python Ports, designed to simplify concurrent use. It focuses dynamic extensibility, like spawning, reusing and killing processes on demand. Furthermore, unused processes get automatically killed by scheduled process which can be configured inside config.exs. Venomous core functions capture and handle :EXIT calls ensuring that all python process die with it and do not continue their execution.

  The core concept revolves around "Snakes" which represent Python worker processes. These `Venomous.SnakeWorker` are managed and supervised with `Venomous.SnakeManager` GenServer to allow concurrent and efficient execution of Python code. The `Snakes` pids and python pids are stored inside `:ets` table and the Processes are handled by `DymanicSupervisor` called `Venomous.SnakeSupervisor`. The unused `Snakes` get automatically killed by `SnakeManager` depending on the given configuration.

  You can checkout examples [here](https://github.com/RustySnek/venomous-examples)

  Be sure to also check the [README](readme.html)

  ## Main Functionality  

  ### Basic processes

    These are automatically managed and made for concurrent operations
    - `python/2`: The primary function to execute a Python function. It retrieves a Snake (Python worker process) and runs the specified Python function using the arguments provided in a `SnakeArgs` struct. If no ready Snakes are available, a new one is spawned. If max_children is reached it will return an error with appropriate message.
    - `python!/2` | `python!/1`: Will wait until any `Venomous.SnakeWorker` is freed, requesting it with the given interval. 

  ### Named processes

    Python processes with unique names. Meant for miscellaneous processes.
    - `adopt_snake_pet/2`: Creates a new `Venomous.SnakeWorker` with a name inside `Venomous.PetSnakeSupervisor`
    - `pet_snake_run/3`: Runs given `Venomous.SnakeArgs` inside the named python process


  ## Architecture

  Venomous consists of several key components:

  - `Venomous.SerpentWatcher`: Manages hot reloading.
  - `Venomous.SnakeWorker`: Manages the execution of Python processes.
  - `Venomous.SnakeSupervisor`: A DynamicSupervisor that oversees the SnakeWorkers.
  - `Venomous.SnakeManager`: A GenServer that coordinates the SnakeWorkers and handles operations like spawning, retrieval and cleanup.
  - `Venomous.PetSnakeSupervisor`: Similar to SnakeSupervisor but for named processes.
  - `Venomous.PetSnakeManager`: Manages named python processes

  ## Configuration Options

  ### SnakeManager

  The behavior and management of Snakes can be configured through the following options:
  ```elixir
  :venomous, :snake_manager, %{
    snake_ttl_minutes: non_neg_integer(), # Time-to-live for a Snake in minutes. Default is 15 min.
    perpetual_workers: non_neg_integer(), # Number of Snakes to keep alive perpetually. Default is 10.
    cleaner_interval: non_neg_integer(), # Interval in milliseconds for cleaning up inactive Snakes. Default is 60_000 ms.
    erlport_encoder: %{module: atom(), func: atom(), args: list(any())}, # Optional :erlport encoder/decoder python function for converting types. This function is applied to every unnamed python process started by SnakeManager. For more information see [Handling Erlport API](PYTHON.md)
    }
  ```

  ### Python options 

    All of these are optional. However you will most likely want to set module_paths
   ```elixir
    config :venomous, :snake_manager, %{
    ...
    python_opts: [
      module_paths: [], # List of paths to your python modules.
      cd: "", # Change python's directory on spawn. Default is $PWD
      compressed: 0, # Can be set from 0-9. May affect performance. Read more on [Erlport documentation](http://erlport.org/docs/python.html#erlang-api)
      envvars: [], # additional python process envvars
      packet_bytes: 4, # Size of erlport python packet. Default: 4 = max 4GB of data. Can be set to 1 = 256 bytes or 2 = ? bytes if you are sure you won't be transfering a lot of data.
      python_executable: "" # path to python executable to use. defaults to PATH
    ]
    ...
  }
  ``` 

  ### Hot reloading
    Requires watchdog python module, which can be installed with `mix venomous.watchdog install`.
    Only files inside `module_paths` config are watched.
    ```elixir
    config :venomous, :serpent_watcher, enable: true
    ```
  ### Struct/Class comp
    Venomous provides an easy way to convert structs into classes and back with VenomousTrait class and `mix venomous.structs ...` task.
    ```
    $ mix venomous.structs
    Simple utility to create python elixir compatible classes.

            VenomousTrait class provides 2 functions: 
              - def from_dict(cls, erl_map: Map | Dict, structs: Dict = {}) -> cls
                # converts Erlport Map or a Dict into the object class
              - def into_erl(self) -> Map
                # returns erlang compatible struct from self

               
            To create basic python classes and encode/decode functions based on structs: 
                - mix venomous.structs MyModule.MyStruct MyModule.MoreStructs ...

            To create extended classes depending on existing python class: 
                - mix venomous.structs MyModule.MyStruct:PythonClassName ...

            To create for all available structs inside an application
                - mix venomous.structs all my_application
    ```

    You can see this used in the [test_struct.exs](https://github.com/RustySnek/Venomous/blob/struct_class_handling/test/test_struct.exs) and [test_venomous.py](https://github.com/RustySnek/Venomous/blob/struct_class_handling/python/test_venomous.py)


  ## Auxiliary Functions

  - `list_alive_snakes/0`: Returns a list of :ets table containing currently alive Snakes.

  - `clean_inactive_snakes/0`: Manually clears inactive Snakes depending on their ttl and returns the number of Snakes cleared.

  - `slay_python_worker/2`: Kills a specified Python worker process and its SnakeWorker. :brutal can be specified as option, which will `kill -9` the os process of python which prevents the code from executing until it finalizes or goes through iteration.

  - `slay_pet_worker/2`: Kills a named Python process

  - `retrieve_snake/0`: Retrieves a `Venomous.SnakeWorker` and sets its status to :retrieved
   
  - `get_snakes_ready/1`: Retrieves given amount of `Venomous.SnakeWorker`s

  """
  alias Venomous.PetSnakeManager
  alias Venomous.SnakeArgs
  alias Venomous.SnakeManager
  alias Venomous.SnakeWorker

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
    - `Venomous.SnakeWorker` struct
    - a Way to kill process. :brutal additionally kills with kill -9 ensuring the python does not execute further. Default: :peaceful
  ## Returns 
    :ok
  """
  @spec slay_python_worker(SnakeWorker.t(), termination_style :: atom()) :: :ok
  @spec slay_python_worker(SnakeWorker.t()) :: :ok
  def slay_python_worker(
        %SnakeWorker{pid: pid, pypid: _pypid, os_pid: os_pid},
        termination_style \\ :peaceful
      ) do
    send(SnakeManager, {:sacrifice_snake, pid})

    # We exterminate the snake in the sanest way possible.
    if termination_style == :brutal,
      do: System.cmd("sh", ["-c", "kill -9 #{os_pid} 2&>/dev/null"], parallelism: true)

    :ok
  end

  @doc """
  Kills the named python process
  :brutal also kills the OS process of python, ensuring the process does not continue execution.
  ## Parameters
  - `name` atom
  - a Way to kill process. :brutal additionally kills with kill -9 ensuring the python does not execute further. Default: :peaceful
  ## Returns 
  :ok
  """
  @spec slay_pet_worker(name :: atom(), termination_style :: atom()) :: :ok
  @spec slay_pet_worker(name :: atom()) :: :ok
  def slay_pet_worker(name, termination_style \\ :peaceful) when is_atom(name) do
    send(PetSnakeManager, {:reject_pet, name, termination_style})
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
  Retrieves x amount of ready snakes and sets their status to :retrieved. In case of hitting max_children cap, stops and returns all available snakes.
  > #### Warning {: .warning}
  > In case of retrieving all available snakes and not using them right away, functions like `python!/2` and `retrieve_snake!/0` will loop until they are freed.
  ## Parameters
    - amount of snakes to retrieve

  ## Returns
    - A list of `Venomous.SnakeWorker` structs

  """
  def get_snakes_ready(amount)
      when is_integer(amount),
      do: get_snakes_ready(amount, [])

  @doc """
  Retrieves `Venomous.SnakeWorker` struct and sets it's status to :retrieved preventing other processes from accessing it.
  If all processes are busy and exceeds max_children will return {:retrieve_error, message}.

  ## Returns
    - `Venomous.SnakeWorker` struct. In case of error `{:retrieve_error, message}`
  """
  @spec retrieve_snake() :: {:retrieve_error, reason :: term()} | SnakeWorker.t()
  def retrieve_snake(), do: GenServer.call(SnakeManager, :get_ready_snake, :infinity)

  @spec retrieve_snake!(non_neg_integer()) :: SnakeWorker.t()
  @doc """
  If all processes are busy and exceeds max_children will wait for interval ms and try again. Traps the exit signals, to safely escape loop.
  ## Parameters
   - interval: The time to wait in milliseconds before retrying. Default is `@wait_for_snake_interval`.

  ## Returns
    - `Venomous.SnakeWorker` struct.
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

      snake_worker ->
        snake_worker
    end
  end

  @doc """
  Runs `Venomous.SnakeArgs` inside given `Venomous.SnakeWorker`.
  Traps exit and awaits signals [:SNAKE_DONE, :SNAKE_ERROR, :EXIT]
  In case of an exit, brutally kills the python process ensuring it doesn't get executed any further.

  ## Parameters
    - `Venomous.SnakeArgs` struct of :module, :func, :args 
    - `Venomous.SnakeWorker` struct
    - opts Keywords
  ## Opts
  - `:python_timeout` ms timeout. Kills python OS process on timeout. Default: 15_000
  - `:kill_python_on_exception` Should python process be killed on exception. Should be set to true if your python process exits by itself. Default: false

  ## Returns 
    - any() | {:error, :timeout} | %SnakeError{} retrieves output of python function or error

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
    kill_python_on_exception = Keyword.get(opts, :kill_on_exception, false)

    GenServer.call(SnakeManager, {:molt_snake, :busy, worker}, :infinity)

    try do
      GenServer.call(pid, {:run_snake, self(), snake_args})
    catch
      :exit, {:noproc, _genserver} ->
        slay_python_worker(worker, :brutal)
        send(self(), :SNAKE_DEAD)
    end

    receive do
      :SNAKE_DEAD ->
        {:error, :process_is_dead}

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
        {:error, :timeout}
    end
  end

  @doc """
  Wrapper for calling python process
  Tries to retrieve `Venomous.SnakeWorker` which then runs the given `Venomous.SnakeArgs`. In case of failure will return {:retrieve_error, message}.
  In case :EXIT happens, it will kill python os process along with its worker and exit(reason)
  ## Parameters
    - `Venomous.SnakeArgs` struct of :module, :func, :args 
    - opts \\ []
  ## Opts
  - `:python_timeout` ms timeout. Kills python OS process on timeout. Default: 15_000
  - `:kill_python_on_exception` Should python process be killed on exception. Should be set to true if your python process exits by itself. Default: false

  ## Returns 
    - any() | {:error, :timeout} | {retrieve_error: any()} retrieves output of python function or error
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
  - `:kill_python_on_exception` Should python process be killed on exception. Should be set to true if your python process exits by itself. Default: false
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

  @doc """
  Creates a named `Venomous.SnakeWorker` inside `Venomous.PetSnakeSupervisor`

  ## Parameters 
    - an atom() name.
    - opts for python process
  ## Options 
    Python options can be configured inside :venomous :python_opts config key

    All of these are optional. However you will most likely want to set module_paths

   - `erlport_encoder: %{module: atom(), func: atom(), args: list(any())}`: Optional :erlport encoder/decoder python function for converting types. This function is applied to every unnamed python process started by SnakeManager. For more information see [Handling Erlport API](PYTHON.md)
   - ```elixir
    @available_opts [
    :module_paths, # List of paths to your python modules
    :cd, # Change python's directory on spawn. Default is $PWD
    :compressed, # Can be set from 0-9. May affect performance. Read more on [Erlport documentation](http://erlport.org/docs/python.html#erlang-api)
    :envvars, # additional python process envvars
    :packet_bytes, # Size of erlport python packet. Default: 4 = max 4GB of data. Can be set to 1 = 256 bytes or 2 = ? bytes if you are sure you won't be transfering a lot of data.
    :python_executable # path to python executable to use.
  ]
  ``` 
  ## Returns 
     - :ok, name - in case of success
     - :error, message - in case of failure
  """
  @spec adopt_snake_pet(name :: atom(), opts :: keyword()) ::
          {:error, any()} | {:ok, name :: atom()}
  def adopt_snake_pet(name, opts \\ []) when is_atom(name) do
    GenServer.call(PetSnakeManager, {:adopt_snake, name, opts})
  end

  @doc """
  Used to run given `Venomous.SnakeArgs` inside named snake
  Does not handle :EXIT signals like `snake_run/2` does.
  If pet snake with name does not exist will return :not_found
  """
  @spec pet_snake_run(SnakeArgs.t(), name :: atom()) :: any() | :not_found
  @spec pet_snake_run(SnakeArgs.t(), name :: atom(), timeout()) ::
          any() | :not_found | {:error, :timeout}
  def pet_snake_run(%SnakeArgs{} = args, name, timeout \\ @default_timeout) do
    case GenServer.call(PetSnakeManager, {:get_snake, name}) do
      {:error, reason} ->
        send(self(), {:SNAKE_ERROR, reason})

      pid ->
        GenServer.call(pid, {:run_snake, self(), args})
    end

    receive do
      {:SNAKE_DONE, data} ->
        data

      {:SNAKE_ERROR, error} ->
        error
    after
      timeout ->
        {:error, :timeout}
    end
  end
end

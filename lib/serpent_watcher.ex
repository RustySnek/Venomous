defmodule Venomous.SerpentWatcher do
  @moduledoc """
  🐍🔎 📁 A snake spy watching every step...


    Disabled by default.

    Starts python watchdog process, watching over every module/file visible by python.
    Default watcher requires watchdog module, which can be installed with ...  
    Whenever file is edited/created/deleted watcher casts `:reload` with module name to SnakeManager.
    The default reload module function imports and reloads the module from its name.

    ## Configuration
  ```elixir
  config :venomous,
    serpent_watcher: [
      enable: true,
      module: :serpent_watcher, # default
      func: :watch_directories, #default
      args: [Venomous.SnakeManager] # default
    ]
  ```
  ```elixir
  config :venomous, :snake_manager, %{
    ...
    reload_module: :reload, # default. reload function is hard coded to :reload
    ...
  }
  ```

  """
  alias Venomous.SnakeOpts
  require Logger
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    {:ok, args, {:continue, :start_serpent}}
  end

  def handle_continue(:start_serpent, state) do
    python_opts = SnakeOpts.to_erlport_opts(state)

    case :python.start_link(python_opts) do
      {:error, reason} ->
        Logger.error("Failed to start Serpent Watcher")
        {:stop, reason, state}

      {:ok, pypid} ->
        Logger.info("Started Serpent Watcher")
        :python.call(pypid, state[:module], state[:func], state[:args])
        exit(:serpent_down)
    end
  end
end

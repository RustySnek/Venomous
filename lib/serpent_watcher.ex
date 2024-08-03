defmodule Venomous.SerpentWatcher do
  @moduledoc """
  🐍🔎 📁 A snake spy watching every step...


    Disabled by default. `config :venomous, :serpent_watcher, enable: true` to enable.

    Starts python watchdog process, watching over every python module inside module_paths directories.
    Default watcher requires watchdog module, which can be installed with `mix venomous.watchdog install` 
    Whenever file is edited/created/deleted watcher casts `:reload` with module name to SnakeManager.
    The default reload module function imports and reloads the module from its name.

    ## Configuration
  ```elixir
  config :venomous,
    serpent_watcher: [
      enable: true, # Disabled by default
      logging: true, # Hot reload logging. Enabled by default
      module: :serpent_watcher, # default
      func: :watch_directories, #default
      manager_pid: Venomous.SnakeManager # default
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

  defp create_abs_paths(nil), do: []
  defp create_abs_paths(path) when is_binary(path), do: [Path.expand(path)]

  defp create_abs_paths(paths) when is_list(paths) do
    Enum.map(paths, &Path.expand(&1))
  end

  def handle_continue(:start_serpent, state) do
    python_opts = SnakeOpts.to_erlport_opts(state)

    case :python.start_link(python_opts) do
      {:error, reason} ->
        Logger.error("Failed to start Serpent Watcher")
        {:stop, reason, state}

      {:ok, pypid} ->
        Logger.info("Started Serpent Watcher")
        watchlist = create_abs_paths(state[:module_paths])
        logging = state[:logging]

        :python.call(pypid, state[:module], state[:func], [
          state[:manager_pid],
          watchlist,
          logging
        ])

        exit(:serpent_down)
    end
  end
end

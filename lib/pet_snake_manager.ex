defmodule Venomous.PetSnakeManager do
  @moduledoc "SnakeManager but for pets..."
  use GenServer
  require Logger
  alias Venomous.PetSnakeSupervisor

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(state) do
    Logger.info("Initialized pet_snake manager")

    {:ok, state}
  end

  defp adopt_snake({:error, message}, _name, _table), do: {:error, message}

  defp adopt_snake({:ok, pid}, name, table) do
    worker = GenServer.call(pid, :get_pypid)
    :ets.insert(table, {name, worker.pid, worker.pypid, worker.os_pid})
    {:ok, name}
  end

  defp adopt_snake(true, _name, _opts, _table), do: {:error, :exists}

  defp adopt_snake(false, name, opts, table) do
    PetSnakeSupervisor.deploy_snake_pet(opts) |> adopt_snake(name, table)
  end

  def handle_call({:adopt_snake, name, opts}, _from, state) do
    exists? = state.table |> :ets.lookup(name) |> Kernel.!=([])
    {:reply, adopt_snake(exists?, name, opts, state.table), state}
  end

  def handle_call({:get_snake, name}, _from, state) do
    snake =
      case state.table |> :ets.lookup(name) do
        [] ->
          {:error, :not_found}

        [{_name, pid, _pypid, _os_pid}] ->
          pid
      end

    {:reply, snake, state}
  end
end

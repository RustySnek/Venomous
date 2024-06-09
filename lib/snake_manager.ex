defmodule Venomous.SnakeManager do
  @moduledoc """
  Manager for brave 🐍 workers

  This module manages the snake workers, ensuring that inactive workers are cleaned up periodically.
    
  Main call `:get_ready_snake` retrieves/spawns a `Venomous.SnakeWorker` with :busy/:spawned status.
  Workers with status :ready, :spawned, are considered inactive and will be cleared up by main process loop running `:clean_inactive_workers` if they exceed their given TTL

  ## Configuration
  The following configurations are retrieved from :venomous :snake_manager Application env:

  - `erlport_encoder: %{module: atom(), func: atom(), args: list(any())}`: Optional :erlport encoder/decoder python function for converting types.
  - `snake_ttl_minutes: non_neg_integer()`: Time-to-live for a Snake in minutes. Default is 15 min.
  - `perpetual_workers: non_neg_integer()`: Number of Snakes to keep alive perpetually. Default is 10.
  - `cleaner_interval_ms: non_neg_integer()`: Interval in milliseconds for cleaning up inactive Snakes. Default is 60_000 ms.

  Defaults are provided in case these configurations are not set:

  - Default encoder: none.
  - Default time-to-live for a worker: 15 minutes.
  - Default number of perpetual workers: 10.
  - Default interval for cleaning inactive workers: 60,000 milliseconds.
  """
  use GenServer
  require Logger
  alias Venomous.SnakeSupervisor

  @default_ttl 15
  @default_perpetual 10
  @default_interval 60_000

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(state) do
    Logger.info("Initialized snake manager")

    {:ok, state, {:continue, :clean_inactive}}
  end

  def handle_continue(:clean_inactive, state) do
    GenServer.cast(self(), :clean_inactive_workers)
    {:noreply, state}
  end

  def handle_info(:clean_inactive_info, state) do
    GenServer.cast(self(), :clean_inactive_workers)
    {:noreply, state}
  end

  def handle_info({:sacrifice_snake, pid}, state) do
    :ets.delete(state.table, pid)
    DynamicSupervisor.terminate_child(SnakeSupervisor, pid)
    {:noreply, state}
  end

  def handle_cast(:clean_inactive_workers, state) do
    cleaner_interval = state |> Map.get(:cleaner_interval_ms, @default_interval)
    cleared = clean_inactive_workers(state)
    unless cleared == 0, do: Logger.info("Cleared #{cleared} unused snakes.")
    Process.send_after(self(), :clean_inactive_info, cleaner_interval)
    {:noreply, state}
  end

  def handle_call(:clean_inactive_workers, _from, state) do
    {:reply, clean_inactive_workers(state), state}
  end

  def handle_call(:list_snakes, _from, state) do
    {:reply, :ets.tab2list(state.table), state}
  end

  def handle_call(:get_ready_snake, _from, state) do
    available? = state.table |> :ets.match({:"$1", :"$2", :ready, :"$3"}) |> Enum.at(0)

    snake =
      case available? do
        nil ->
          deploy_new_snake(state.table, state.erlport_encoder)

        [pid, pypid, update_utc] ->
          :ets.insert(state.table, {pid, pypid, :busy, update_utc})
          {pid, pypid}
      end

    {:reply, snake, state}
  end

  def handle_call({:employ_snake, pid, pypid}, _from, state) do
    now = DateTime.utc_now()
    :ets.insert(state.table, {pid, pypid, :ready, now})
    {:reply, :ok, state}
  end

  defp deploy_new_snake({:ok, pid}, table) do
    pypid = GenServer.call(pid, :get_pypid)
    :ets.insert(table, {pid, pypid, :spawned, DateTime.utc_now()})
    {pid, pypid}
  end

  defp deploy_new_snake({:error, message}, _table) do
    Logger.error("Error while creating new snake: #{message}")
    {:retrieve_error, message}
  end

  defp deploy_new_snake(table, encoder) do
    SnakeSupervisor.deploy_snake_worker(encoder) |> deploy_new_snake(table)
  end

  defp clean_inactive_workers(state) do
    ttl = state |> Map.get(:snake_ttl_minutes, @default_ttl)
    perpetual_workers = state |> Map.get(:perpetual_workers, @default_perpetual)
    clean_inactive_workers(state.table, perpetual_workers, ttl)
  end

  defp clean_inactive_workers({pid, pypid, status, update_utc}, table, ttl) do
    now = DateTime.utc_now()

    max_ttl =
      Timex.shift(update_utc,
        minutes: ttl
      )

    active =
      DateTime.compare(
        now,
        max_ttl
      ) != :gt

    unless status not in [:ready, :spawned] or active do
      :ets.delete(table, pid)
      kill_inactive_worker(pid, pypid)
    end

    active
  end

  defp clean_inactive_workers(table, perpetual_workers, ttl) do
    {_perpetual_workers, rest} = table |> :ets.tab2list() |> Enum.split(perpetual_workers)

    rest |> Enum.filter(&(clean_inactive_workers(&1, table, ttl) == false)) |> length()
  end

  defp kill_inactive_worker(pid, pypid) do
    :python.stop(pypid)
    DynamicSupervisor.terminate_child(SnakeSupervisor, pid)
  end

  def get_snake_worker_status(table, pid) when is_pid(pid) do
    with [snake | _] <- :ets.lookup(table, pid) do
      {_pid, pypid, status, update_utc} = snake
      {pypid, status, update_utc}
    end
  end
end

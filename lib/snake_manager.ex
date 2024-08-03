defmodule Venomous.SnakeManager do
  @moduledoc """
  Manager for brave 🐍 workers

  This module manages the snake workers, ensuring that inactive workers are cleaned up periodically.

  Main call `:get_ready_snake` retrieves/spawns a `Venomous.SnakeWorker` with :retrieved status.
  Workers with status :ready and :retrieved are considered inactive and will be cleared up by main process loop running `:clean_inactive_workers` if they exceed their given TTL
  Workers with :retrieved retrieved again until they are used.

  ## Configuration
  The following configurations are retrieved from :venomous :snake_manager Application env:

  - `erlport_encoder: %{module: atom(), func: atom(), args: list(any())}`: Optional :erlport encoder/decoder python function for converting types. The function can also provide any callbacks from :erlport documentation like .cast() message handler
  - `snake_ttl_minutes: non_neg_integer()`: Time-to-live for a Snake in minutes. Default is 15 min.
  - `perpetual_workers: non_neg_integer()`: Number of Snakes to keep alive perpetually. Default is 10.
  - `cleaner_interval: non_neg_integer()`: Interval in milliseconds for cleaning up inactive Snakes. Default is 60_000 ms.
  """
  use GenServer
  require Logger
  alias Venomous.SnakeSupervisor
  alias Venomous.SnakeWorker

  @default_ttl 15
  @default_perpetual 10
  @default_interval 60_000

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(state) do
    Logger.info("Started Snake Manager")
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

  def handle_info({:reload, module}, state) do
    reload_module = state.reload_module

    serpent_opts = %Venomous.SnakeArgs{
      module: reload_module,
      func: :reload,
      args: [module |> to_string()]
    }

    :ets.tab2list(state.table)
    |> Enum.each(fn {pid, _pypid, _os_pid, _status, _date} ->
      send(pid, {:reload, serpent_opts})
    end)

    {:noreply, state}
  end

  def handle_info({_ref, :ok}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    Logger.error("Snake Crashed ")
    {:noreply, state}
  end

  def handle_info({:sacrifice_snake, pid}, state) do
    try do
      DynamicSupervisor.terminate_child(SnakeSupervisor, pid)

      :ets.delete(state.table, pid)
    catch
      :exit, reason ->
        Logger.error("Crashed at terminating #{inspect(reason)}")
        :ets.delete(state.table, pid)
    end

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

  def handle_call(
        {:molt_snake, status, %SnakeWorker{pid: pid, pypid: pypid, os_pid: os_pid}},
        from,
        state
      ) do
    # Does Task even make a difference here? lol
    Task.start(fn ->
      now = DateTime.utc_now()
      :ets.insert(state.table, {pid, pypid, os_pid, status, now})
      GenServer.reply(from, :ok)
    end)

    {:noreply, state}
  end

  def handle_call(:list_snakes, _from, state) do
    {:reply, :ets.tab2list(state.table), state}
  end

  def handle_call(:get_ready_snake, from, state) do
    available? = state.table |> :ets.match({:"$1", :"$2", :"$3", :ready, :_}) |> Enum.at(0)

    case available? do
      nil ->
        Task.start(fn ->
          snake = deploy_new_snake(state.table, state.python_opts)
          GenServer.reply(from, snake)
        end)

        {:noreply, state}

      [pid, pypid, os_pid] ->
        :ets.insert(state.table, {pid, pypid, os_pid, :retrieved, DateTime.utc_now()})

        {:reply, %SnakeWorker{pid: pid, pypid: pypid, os_pid: os_pid}, state}
    end
  end

  def handle_call({:remove_snake, pid}, _from, state) do
    :ets.delete(state.table, pid)
    {:reply, :ok, state}
  end

  defp deploy_new_snake({:ok, pid}, table) do
    try do
      worker = GenServer.call(pid, :get_pypid)

      :ets.insert(
        table,
        {worker.pid, worker.pypid, worker.os_pid, :retrieved, DateTime.utc_now()}
      )

      worker
    catch
      :exit, reason ->
        Logger.error("Crashed at deploying new snake: #{inspect(reason)}")
        {:retrieve_error, reason}
    end
  end

  defp deploy_new_snake({:error, message}, _table) do
    # Logger.error("Error while creating new snake: #{message}")
    {:retrieve_error, message}
  end

  defp deploy_new_snake(table, python_opts) do
    SnakeSupervisor.deploy_snake_worker(python_opts) |> deploy_new_snake(table)
  end

  defp clean_inactive_workers(state) do
    ttl = state |> Map.get(:snake_ttl_minutes, @default_ttl)
    perpetual_workers = state |> Map.get(:perpetual_workers, @default_perpetual)
    clean_inactive_workers(state.table, perpetual_workers, ttl)
  end

  defp clean_inactive_workers({pid, _pypid, _os_pid, status, update_utc}, table, ttl) do
    now = DateTime.utc_now()

    max_ttl =
      DateTime.add(
        update_utc,
        ttl,
        :minute
      )

    active =
      DateTime.compare(
        now,
        max_ttl
      ) != :gt

    unless status not in [:ready, :retrieved] or active do
      :ets.delete(table, pid)
      kill_inactive_worker(pid)
    end

    active
  end

  defp clean_inactive_workers(table, perpetual_workers, ttl) do
    {_perpetual_workers, rest} = table |> :ets.tab2list() |> Enum.split(perpetual_workers)

    rest |> Enum.filter(&(clean_inactive_workers(&1, table, ttl) == false)) |> length()
  end

  defp kill_inactive_worker(pid) do
    DynamicSupervisor.terminate_child(SnakeSupervisor, pid)
  end

  def get_snake_worker_status(table, pid) when is_pid(pid) do
    with [{_pid, pypid, os_pid, status, update_utc} | _] <- :ets.lookup(table, pid) do
      {pypid, os_pid, status, update_utc}
    end
  end
end

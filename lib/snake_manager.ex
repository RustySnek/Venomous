defmodule Venomous.SnakeManager do
  @moduledoc """
  Manager for brave 🐍 workers
  """
  use GenServer
  require Logger
  alias Venomous.SnakeSupervisor

  def start_link(table) do
    GenServer.start_link(__MODULE__, table, name: __MODULE__)
  end

  def init(table) do
    Logger.info("Initialized snake manager")

    {:ok, table, {:continue, :clean_inactive}}
  end

  def handle_continue(:clean_inactive, table) do
    GenServer.cast(self(), :clean_inactive_workers)
    {:noreply, table}
  end

  def handle_cast(:clean_inactive_workers, table) do
    clean_inactive_workers(table)
    # DynamicSupervisor.count_children(SnakeSupervisor)
    Process.send_after(self(), :clean_inactive_info, 10_000)
    {:noreply, table}
  end

  def handle_info(:clean_inactive_info, table) do
    GenServer.cast(self(), :clean_inactive_workers)
    {:noreply, table}
  end

  def handle_info({:sacrifice_snake, pid}, table) do
    :ets.delete(table, pid)
    DynamicSupervisor.terminate_child(SnakeSupervisor, pid)
    {:noreply, table}
  end

  def handle_call(:get_ready_snake, _from, table) do
    available? = table |> :ets.match({:"$1", :"$2", :ready, :"$3"}) |> Enum.at(0)

    snake =
      case available? do
        nil ->
          deploy_new_snake(table)

        [pid, pypid, update_utc] ->
          :ets.insert(table, {pid, pypid, :busy, update_utc})
          {pid, pypid}
      end

    {:reply, snake, table}
  end

  def handle_call({:employ_snake, pid, pypid}, _from, table) do
    now = DateTime.utc_now()
    :ets.insert(table, {pid, pypid, :ready, now})
    {:reply, :ok, table}
  end

  defp deploy_new_snake({:ok, pid}, table) do
    pypid = GenServer.call(pid, :get_pypid)
    :ets.insert(table, {pid, pypid, :busy, DateTime.utc_now()})
    {pid, pypid}
  end

  defp deploy_new_snake({:error, message}, _table) do
    Logger.error("Error while creating new snake: #{message}")
    {:error, message}
  end

  defp deploy_new_snake(table) do
    SnakeSupervisor.deploy_snake_worker() |> deploy_new_snake(table)
  end

  defp clean_inactive_workers(table) do
    {_perpetual_workers, rest} = table |> :ets.tab2list() |> Enum.split(10)

    Enum.each(rest, fn {pid, pypid, status, update_utc} ->
      now = DateTime.utc_now()

      max_ttl =
        Timex.shift(update_utc,
          minutes: 15
        )

      active =
        DateTime.compare(
          now,
          max_ttl
        ) != :gt

      unless active or status != :ready do
        :ets.delete(table, pid)
        kill_inactive_worker(pid, pypid)
      end

      active
    end)
  end

  defp kill_inactive_worker(pid, pypid) do
    :python.stop(pypid)
    DynamicSupervisor.terminate_child(SnakeSupervisor, pid)
    Logger.info("Cleared unused snake")
  end

  def get_snake_worker_status(table, pid) when is_pid(pid) do
    with [snake | _] <- :ets.lookup(table, pid) do
      [_pid, pypid, status, update_utc] = snake
      {pypid, status, update_utc}
    end
  end
end

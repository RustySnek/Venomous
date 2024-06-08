defmodule Venomous.SnakeManager do
  @moduledoc """
  Manager for brave 🐍 workers
  """
  use GenServer
  require Logger
  alias Venomous.SnakeSupervisor

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state \\ MapSet.new()) do
    Logger.info("Initialized snake manager")

    {:ok, state, {:continue, :clean_inactive}}
  end

  def handle_continue(:clean_inactive, state) do
    GenServer.cast(self(), :clean_inactive_workers)
    {:noreply, state}
  end

  def handle_cast({:reply_ready_snake, task}, state) do
    Task.await(task)

    {:noreply, state}
  end

  def handle_cast(:clean_inactive_workers, state) do
    state = clean_inactive_workers(state)
    # DynamicSupervisor.count_children(SnakeSupervisor)
    Process.send_after(self(), :clean_inactive_info, 10_000)
    {:noreply, state}
  end

  def handle_info(:clean_inactive_info, state) do
    GenServer.cast(self(), :clean_inactive_workers)
    {:noreply, state}
  end

  def handle_info({:sacrifice_snake, pid}, state) do
    DynamicSupervisor.terminate_child(SnakeSupervisor, pid)
    {:noreply, MapSet.delete(state, pid)}
  end

  def handle_call(:get_ready_snake, from, state) do
    available? = state |> Enum.at(0)

    case available? do
      nil ->
        task =
          Task.async(fn ->
            result = _deploy_new_snake()

            GenServer.reply(from, result)
          end)

        GenServer.cast(self(), {:reply_ready_snake, task})
        {:noreply, state}

      pid ->
        state = MapSet.delete(state, pid)

        task =
          Task.async(fn ->
            {pypid, _update} = GenServer.call(pid, :status)
            GenServer.reply(from, {pid, pypid})
          end)

        GenServer.cast(self(), {:reply_ready_snake, task})
        {:noreply, state}
    end
  end

  def handle_call({:employ_snake, pid}, _from, state) do
    {:reply, :ok, MapSet.put(state, pid)}
  end

  defp _deploy_new_snake() do
    case SnakeSupervisor.deploy_snake_worker() do
      {:ok, pid} ->
        {pypid, _update} = GenServer.call(pid, :status)
        {pid, pypid}

      {:error, message} ->
        Logger.error("Error while creating new snake: #{message}")
        {:error, message}
    end
  end

  defp _kill_inactive_worker(pid, pypid) do
    :python.stop(pypid)
    DynamicSupervisor.terminate_child(SnakeSupervisor, pid)
    Logger.info("Cleared unused snake")
  end

  defp clean_inactive_workers(state) do
    {perpetual_workers, rest} = state |> Enum.split(10)

    Enum.filter(rest, fn pid ->
      {pypid, update} = GenServer.call(pid, :status)
      now = DateTime.now!("Europe/Warsaw")

      active =
        DateTime.compare(
          now,
          Timex.shift(update,
            minutes: 15
          )
        ) != :gt

      unless active do
        _kill_inactive_worker(pid, pypid)
      end

      active
    end)
    |> Kernel.++(perpetual_workers)
    |> MapSet.new()
  end
end

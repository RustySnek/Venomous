defmodule Venomous.SnakeWorker do
  @moduledoc """
  🔨🐍
  A brave snake worker slithering across...
  """
  alias Venomous.SnakeError
  use GenServer
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    case :python.start() do
      {:error, reason} ->
        Logger.error(reason |> inspect)

        {:error, :rip_python}

      {:ok, pid} ->
        case args do
          [encoder_module, encoder_func] ->
            {:ok, set_state(pid), {:continue, {:init_encoder, encoder_module, encoder_func}}}

          [] ->
            {:ok, set_state(pid)}
        end
    end
  end

  def handle_continue({:init_encoder, module, func, args}, state) do
    :python.call(state.pid, module, func, args)
    {:noreply, set_state(state.pid)}
  end

  def handle_call(:status, _from, state) do
    {:reply, {state.pid, state.update}, state}
  end

  def handle_call({:run_snake, origin, {module, func, args}}, _from, state) do
    task =
      Task.async(fn ->
        data =
          try do
            :python.call(state.pid, module, func, args)
          rescue
            error ->
              case error do
                %ErlangError{original: {:python, exception, error, backtrace}} ->
                  Logger.error("#{exception}\n#{error}\nBacktrace: #{backtrace}")

                  %SnakeError{
                    exception: exception,
                    error: error,
                    backtrace: backtrace
                  }

                exception ->
                  Logger.error(exception |> inspect)
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
    GenServer.reply(_from, :ok)
    {:noreply, set_state(state.pid)}
  end

  def handle_cast({:run, task}, state) do
    Task.await(task, :infinity)
    {:noreply, state}
  end

  defp set_state(pid) do
    update = DateTime.now!("Europe/Warsaw")
    %{pid: pid, update: update}
  end
end

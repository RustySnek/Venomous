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
        reason |> dbg
        Logger.error("Lol xd we had to debug")

        {:error, :rip_python}

      {:ok, pypid} ->
        case args do
          [encoder_module, encoder_func] ->
            {:ok, pypid, {:continue, {:init_encoder, encoder_module, encoder_func}}}

          [] ->
            {:ok, pypid}
        end
    end
  end

  def handle_continue({:init_encoder, module, func, args}, pypid) do
    :python.call(pypid, module, func, args)
    {:noreply, pypid}
  end

  def handle_call(:get_pypid, _from, pypid) do
    {:reply, pypid, pypid}
  end

  def handle_call({:run_snake, origin, {module, func, args}}, _from, pypid) do
    task =
      Task.async(fn ->
        data =
          try do
            :python.call(pypid, module, func, args)
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
                  exception |> dbg
                  Logger.error("WTF")
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
    {:noreply, pypid}
  end

  def handle_cast({:run, task}, pypid) do
    Task.await(task, :infinity)
    {:noreply, pypid}
  end
end

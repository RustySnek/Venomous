defmodule Venomous.SnakeWorker do
  @moduledoc """
  🔨🐍
  A brave snake worker slithering across...
  """
  alias Venomous.SnakeArgs
  alias Venomous.SnakeError
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    case :python.start() do
      {:error, reason} ->
        # xd
        {:EXIT, reason}

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

  def handle_call({:run_snake, origin, %SnakeArgs{} = snake_args}, from, pypid) do
    task =
      Task.async(fn ->
        data =
          try do
            :python.call(pypid, snake_args.module, snake_args.func, snake_args.args)
          rescue
            error ->
              case error do
                %ErlangError{original: {:python, exception, error, backtrace}} ->
                  %SnakeError{
                    exception: exception,
                    error: error,
                    backtrace: backtrace
                  }

                exception ->
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
    GenServer.reply(from, :ok)
    {:noreply, pypid}
  end

  def handle_cast({:run, task}, pypid) do
    Task.await(task, :infinity)
    {:noreply, pypid}
  end
end

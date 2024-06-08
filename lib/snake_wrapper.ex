defmodule Venomous.SnakeWrapper do
  @moduledoc """
  Wrapper for SnakeManager GenServer to run python functions.
  """
  alias Venomous.SnakeManager

  @doc """
  Call python GenServer
  """

  require Logger

  def slay_python_worker(pid, pypid) do
    Logger.warning("KILLING")
    :python.stop(pypid)
    send(SnakeManager, {:sacrifice_snake, pid})
  end

  def python(module, func, args, python_timeout \\ 5_000) do
    # Prevents :python processes from not exiting
    Process.flag(:trap_exit, true)
    # Venomous.SnakeSupervisor |> DynamicSupervisor.count_children() |> dbg

    case GenServer.call(SnakeManager, :get_ready_snake, :infinity) do
      {:error, _} ->
        receive do
          {:EXIT, _from, reason} ->
            reason |> dbg
            Logger.warning("EXITED WITHOUT PYTHON")
            exit(:normal)
        after
          1500 ->
            python(module, func, args)
        end

      {pid, pypid} ->
        GenServer.call(pid, {:run_snake, self(), {module, func, args}})

        receive do
          {:EXIT, _from, type} ->
            slay_python_worker(pid, pypid)
            type |> dbg
            Logger.warning("EXITED ")
            exit(:normal)

          {:EXIT, type} ->
            type |> dbg
            slay_python_worker(pid, pypid)
            Logger.warning("EXITED ")
            exit(:normal)

          {:SNAKE_DONE, data} ->
            GenServer.call(SnakeManager, {:employ_snake, pid}, :infinity)

            data

          {:SNAKE_ERROR, error} ->
            slay_python_worker(pid, pypid)
            error
        after
          python_timeout ->
            slay_python_worker(pid, pypid)
            Logger.warning("TIMED OUT")
            %{error: "timeout"}
            exit(:timeout)
        end
    end
  end
end

defmodule VenomousTest.BreakTest do
  alias Venomous.SnakeWorker
  alias Venomous.SnakeError
  alias Venomous.SnakeSupervisor
  use ExUnit.Case
  import Venomous
  alias Venomous.SnakeArgs

  defp wait_for_process(pid) do
    if Process.alive?(pid) do
      wait_for_process(pid)
    end
  end

  test "snake abuse" do
    list_alive_snakes()
    |> Enum.each(fn {pid, pypid, os_pid, _, _} ->
      slay_python_worker(%SnakeWorker{pid: pid, pypid: pypid, os_pid: os_pid}, :brutal)
    end)

    Enum.map(1..100, fn _ ->
      {:ok, pid} =
        Task.start(fn ->
          Enum.map(1..20, fn _ ->
            Task.async(fn ->
              SnakeArgs.from_params(:time, :sleep, [0.01]) |> python!(python_timeout: 10_000)
            end)
          end)
          |> Task.await_many(:infinity)
        end)

      pid
    end)
    |> Enum.each(&wait_for_process(&1))

    assert list_alive_snakes() |> Enum.filter(fn {_, _, _, status, _} -> status != :ready end) ==
             []
  end

  test "exit abuse" do
    list_alive_snakes()
    |> Enum.each(fn {pid, pypid, os_pid, _, _} ->
      slay_python_worker(%SnakeWorker{pid: pid, pypid: pypid, os_pid: os_pid}, :brutal)
    end)

    args = SnakeArgs.from_params(:time, :sleep, [10])

    me = self()

    Enum.map(0..100, fn i ->
      {:ok, pid} =
        Task.start(fn ->
          python!(args)

          send(me, :fail)
        end)

      pid
    end)
    |> Enum.each(fn pid ->
      Process.send_after(pid, {:EXIT, :left}, 200)
    end)

    receive do
      :fail -> assert(false)
    after
      1000 ->
        assert list_alive_snakes() == []
    end
  end
end

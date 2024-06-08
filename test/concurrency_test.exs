defmodule ConcurrencyTest do
  use ExUnit.Case
  import Venomous.SnakeWrapper, only: [python: 3, python: 4, get_snakes_ready: 1]

  @tag timeout: :infinity
  test "stress snakes" do
    sum_that =
      1..1000
      |> Enum.map(fn _ ->
        Task.async(fn ->
          python(:builtins, :sum, [[1, 1]])
        end)
      end)
      |> Task.await_many(:infinity)
      |> Enum.sum()

    assert sum_that == 2 * 1000
  end

  test "concurrent python processes" do
    Process.send_after(self(), :fail, 5_000)

    1..100
    |> Enum.map(fn _ ->
      Task.async(fn -> python(:time, :sleep, [2]) end)
    end)
    |> Task.await_many(:infinity)

    send(self(), :ok)

    receive do
      :fail ->
        assert(false)

      :ok ->
        assert(true)
    end
  end
end

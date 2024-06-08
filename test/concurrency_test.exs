defmodule VenomousTest.ConcurrencyTest do
  use ExUnit.Case
  import Venomous.SnakeArgs
  import Venomous
  # @tag timeout: :infinity
  # test "stress snakes" do
  #   sum_that =
  #     1..1000
  #     |> Enum.map(fn _ ->
  #       Task.async(fn ->
  #         python(:builtins, :sum, [[1, 1]])
  #       end)
  #     end)
  #     |> Task.await_many(:infinity)
  #     |> Enum.sum()

  #   assert sum_that == 2 * 1000
  # end

  test "concurrent python processes" do
    Process.send_after(self(), :fail, 1_000)
    args = snake_args(:time, :sleep, [0.1])

    1..100
    |> Enum.map(fn _ ->
      Task.async(fn -> python(args) end)
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

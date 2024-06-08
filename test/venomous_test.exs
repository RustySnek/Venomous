defmodule VenomousTest do
  alias Venomous.SnakeError
  alias Venomous.SnakeSupervisor
  use ExUnit.Case
  import Venomous.SnakeWrapper, only: [python: 3, python: 4]
  doctest Venomous

  test "greets the world" do
    assert Venomous.hello() == :world
  end

  test "reuse alive snakes" do
    assert python(:builtins, :round, [0.9]) == 1
    assert python(:builtins, :round, [0.9]) == 1
    assert python(:builtins, :round, [0.9]) == 1

    snakes = DynamicSupervisor.count_children(SnakeSupervisor) |> Map.get(:workers)
    assert snakes == 1
  end

  test "python builtin func" do
    neg_number = :rand.uniform() * -1_000
    assert Venomous.SnakeWrapper.python(:builtins, :abs, [neg_number]) == abs(neg_number)
    assert python(:builtins, :round, [1.5]) == 2
  end

  test "python timeout" do
    result =
      try do
        python(:time, :sleep, [0.5], 100)
      catch
        :exit, _ -> :ok
        _ -> :fail
      end

    assert result == :ok
  end

  test "snake errors" do
    sleepy_snake = python(:time, :sleep, ["sleepy snake"])
    slithering_across = python(:snake, :slithering, ["across"])
    hilarious = python("this", "is", "hilariousssssss")
    assert match?(sleepy_snake, %SnakeError{})
    assert match?(slithering_across, %SnakeError{})
    assert match?(hilarious, %FunctionClauseError{})
  end
end

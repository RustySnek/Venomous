defmodule VenomousTest do
  alias Venomous.SnakeError
  alias Venomous.SnakeSupervisor
  use ExUnit.Case
  import Venomous.SnakeWrapper
  import Venomous.SnakeArgs
  doctest Venomous

  test "greets the world" do
    assert Venomous.hello() == :world
  end

  test "reuse alive snakes" do
    round_args =
      snake_args(
        :builtins,
        :round,
        [0.9]
      )

    assert python(round_args) == 1
    assert python(round_args) == 1
    assert python(round_args) == 1

    snakes = DynamicSupervisor.count_children(SnakeSupervisor) |> Map.get(:workers)
    assert snakes == 1
  end

  test "python builtin func" do
    neg_number = :rand.uniform() * -1_000
    assert snake_args(:builtins, :abs, [neg_number]) |> python() |> Kernel.==(abs(neg_number))
    assert snake_args(:builtins, :round, [1.5]) |> python() |> Kernel.==(2)
  end

  test "python timeout" do
    result =
      snake_args(:time, :sleep, [0.5]) |> python(100)

    assert result == %{error: "timeout"}
  end

  test "snake errors" do
    _sleepy_snake = snake_args(:time, :sleep, ["sleepy snake"]) |> python()
    _slithering_across = snake_args(:snake, :slithering, ["across"]) |> python()
    _hilarious = snake_args("this", "is", "hilariousssssss") |> python()
    assert match?(_sleepy_snake, %SnakeError{})
    assert match?(_slithering_across, %SnakeError{})
    assert match?(_hilarious, %FunctionClauseError{})
  end
end

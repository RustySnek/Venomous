defmodule VenomousTest do
  alias Venomous.SnakeError
  alias Venomous.SnakeSupervisor
  use ExUnit.Case
  import Venomous
  import Venomous.SnakeArgs
  doctest Venomous

  test "reuse alive snakes" do
    list_alive_snakes()
    |> Enum.each(fn {pid, pypid, _, _} -> slay_python_worker({pid, pypid}) end)

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

  test "SLAY AND REVIVE SNEKS" do
    list_alive_snakes()
    |> Enum.each(fn {pid, pypid, _, _} -> slay_python_worker({pid, pypid}) end)

    assert list_alive_snakes() == []
    args = snake_args(:builtins, :sum, [[1]])

    assert get_snakes_ready(10)
           |> Enum.map(fn pids ->
             snake_run(pids, args)
           end)
           |> Enum.sum()
           |> Kernel.==(10)

    assert length(list_alive_snakes()) == 10
    retrieve_snake!() |> slay_python_worker()
    assert length(list_alive_snakes()) == 9
  end
end

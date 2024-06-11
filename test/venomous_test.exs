defmodule VenomousTest do
  alias Venomous.SnakeError
  alias Venomous.SnakeSupervisor
  use ExUnit.Case
  import Venomous
  alias Venomous.SnakeArgs
  doctest Venomous

  test "reuse alive snakes" do
    list_alive_snakes()
    |> Enum.each(fn {pid, pypid, _, _} -> slay_python_worker({pid, pypid}, :brutal) end)

    round_args =
      SnakeArgs.from_params(
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

    assert SnakeArgs.from_params(:builtins, :abs, [neg_number])
           |> python()
           |> Kernel.==(abs(neg_number))

    assert SnakeArgs.from_params(:builtins, :round, [1.5]) |> python() |> Kernel.==(2)
  end

  test "python timeout" do
    result =
      SnakeArgs.from_params(:time, :sleep, [0.5]) |> python(100)

    assert result == %{error: :timeout}
  end

  test "snake errors" do
    _sleepy_snake = SnakeArgs.from_params(:time, :sleep, ["sleepy snake"]) |> python()
    _slithering_across = SnakeArgs.from_params(:snake, :slithering, ["across"]) |> python()
    _hilarious = SnakeArgs.from_params("this", "is", "hilariousssssss") |> python()
    assert match?(_sleepy_snake, %SnakeError{})
    assert match?(_slithering_across, %SnakeError{})
    assert match?(_hilarious, %FunctionClauseError{})
  end

  test "SLAY AND REVIVE SNEKS" do
    list_alive_snakes()
    |> Enum.each(fn {pid, pypid, _, _} -> slay_python_worker({pid, pypid}, :brutal) end)

    assert list_alive_snakes() == []
    args = SnakeArgs.from_params(:builtins, :sum, [[1]])
    snakes = get_snakes_ready(10)
    assert snakes |> length() == 10

    sum =
      Enum.map(snakes, fn pids ->
        snake_run(args, pids)
      end)
      |> Enum.sum()

    assert sum == 10
    assert length(list_alive_snakes()) == 10
    retrieve_snake!() |> slay_python_worker(:brutal)
    assert length(list_alive_snakes()) == 9
  end

  test "exit theeem" do
    args = SnakeArgs.from_params(:time, :sleep, [0.5])

    me = self()

    Enum.map(1..100, fn i ->
      {:ok, pid} =
        Task.start(fn ->
          python!(args)

          send(me, :fail)
        end)

      pid
    end)
    |> Enum.each(fn pid ->
      Process.send_after(pid, {:EXIT, :left}, 100)
    end)

    receive do
      :fail -> assert(false)
    after
      1_000 ->
        assert list_alive_snakes() == []
    end
  end
end

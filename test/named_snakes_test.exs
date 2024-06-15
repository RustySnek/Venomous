defmodule VenomousTest.NamedSnakesTest do
  use ExUnit.Case
  import Venomous
  alias Venomous.SnakeArgs

  test "test named processes" do
    kitty = adopt_snake_pet(:kitty, cd: "/", non_existant_opt: nil)
    copy_cat = adopt_snake_pet(:kitty)
    assert kitty == {:ok, :kitty}
    assert copy_cat == {:error, :exists}

    cwd = SnakeArgs.from_params(:os, :getcwd, [])
    assert pet_snake_run(cwd, :kitty) == ~c"/"

    slay_pet_worker(:kitty, :brutal)
    assert pet_snake_run(cwd, :kitty) == :not_found
  end
end

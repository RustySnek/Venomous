defmodule VenomousTest.Venom do
  alias VenomousTest.TestStruct
  defstruct [:test_struct]

  @type t() :: %__MODULE__{
          test_struct: TestStruct.t()
        }
end

defmodule VenomousTest.TestStruct do
  defstruct [:test, :snake]
  use ExUnit.Case
  import Venomous
  import Venomous.SnakeArgs

  @type t() :: %__MODULE__{
          test: String.t(),
          snake: list()
        }

  test "venom struct/class" do
    {:ok, snake} =
      adopt_snake_pet(:struct_test,
        module_paths: ["../python/"],
        erlport_encoder: %{
          module: :test_venomous,
          func: :erl_encode,
          args: []
        }
      )

    test_struct = %__MODULE__{
      test: "123",
      snake: ["s", "s", "s"]
    }

    assert from_params(:test_venomous, :test_venomous_trait, [[{%{"x" => test_struct}}, "abc"]])
           |> pet_snake_run(snake) ==
             [
               %VenomousTest.Venom{
                 test_struct: test_struct
               },
               "abc"
             ]
  end
end

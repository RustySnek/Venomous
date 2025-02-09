defmodule VenomousREPL do
  @moduledoc """
  #Simple REPL for Venomous
    ## Dev/Test REPL
  Venomous provides dev/test only REPL
  ```
  $ iex -S mix test
  Erlang/OTP 25 [erts-13.2.2.7] [source] [64-bit] [smp:16:2] [ds:16:2:10] [async-threads:1] [jit:ns]

  Compiling 1 file (.ex)

  15:45:10.953 [info] Started Snake Manager

  15:45:10.954 [info] Started Pet Snake Manager
  ............
  Finished in 12.9 seconds (0.00s async, 12.9s sync)
  12 tests, 0 failures

  Randomized with seed 961929
  Interactive Elixir (1.16.2) - press Ctrl+C to exit (type h() ENTER for help)
  iex(1)> test_struct = %VenomousTest.TestStruct{test: "123", snake: ["s","s","s"]}
  %VenomousTest.TestStruct{test: "123", snake: ["s", "s", "s"]}
  iex(2)> VenomousREPL.repl(inputs: [test_struct: test_struct])
  Python REPL (module/outputs/pop/r (repeat)/exit): test_venomous
  Python REPL (function): 
  Available functions:

  Test()
        name: self
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: undefined

        name: test
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: <class 'str'>

        name: snake
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: <class 'list'>
  TestStruct()
        name: self
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: undefined

        name: test
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: <class 'str'>

        name: snake
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: <class 'list'>

        name: __struct__
        kind: POSITIONAL_OR_KEYWORD
        default: b'Elixir.VenomousTest.TestStruct'
        annotation: <class 'erlport.erlterms.Atom'>
  Venom()
        name: self
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: undefined

        name: test_struct
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: <class 'test_venomous.Test'>
  VenomStruct()
        name: self
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: undefined

        name: test_struct
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: <class 'test_venomous.Test'>

        name: __struct__
        kind: POSITIONAL_OR_KEYWORD
        default: b'Elixir.VenomousTest.Venom'
        annotation: <class 'erlport.erlterms.Atom'>
  decoder()
        name: value
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: typing.Any
  encoder()
        name: value
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: typing.Any
  erl_encode()
        
  test_venomous_trait()
        name: test
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: undefined
  Python REPL (function): test_venomous_trait
  Python REPL (arg 1): [{%{"x" => test_struct}}, "abc"]
  Python REPL (arg 2): 
  [lib/repl.ex:121: VenomousREPL.repl/1]
  Venomous.python!(params) #=> [
  %VenomousTest.Venom{
    test_struct: %{
      "__struct__" => VenomousTest.TestStruct,
      "snake" => ["s", "s", "s"],
      "test" => "123"
    }
  },
  "abc"
  ]

  Python REPL (module/outputs/pop/r (repeat)/exit): r
  [lib/repl.ex:109: VenomousREPL.repl/1]
  Venomous.python!(previous_args) #=> [
  %VenomousTest.Venom{
    test_struct: %{
      "__struct__" => VenomousTest.TestStruct,
      "snake" => ["s", "s", "s"],
      "test" => "123"
    }
  },
  "abc"
  ]

  Python REPL (module/outputs/pop/r (repeat)/exit): outputs
  [lib/repl.ex:96: VenomousREPL.repl/1]
  outputs #=> [
  [
    %VenomousTest.Venom{
      test_struct: %{
        "__struct__" => VenomousTest.TestStruct,
        "snake" => ["s", "s", "s"],
        "test" => "123"
      }
    },
    "abc"
  ]
  ]

  Python REPL (module/outputs/pop/r (repeat)/exit):
  ```
  """
  @compile if Mix.env() in [:test, :dev], do: :export_all
  # credo:disable-for-this-file Credo.Check.Warning.Dbg

  defp repl_input(n, inputs, outputs) do
    IO.gets("Python REPL (arg #{n}): ")
    |> String.trim_trailing("\n")
    |> Code.eval_string(Keyword.merge(inputs, outputs: outputs))
    |> elem(0)
  end

  defp repl_args(nil, args, _n, _inputs, _outputs), do: args

  defp repl_args(arg, args, n, inputs, outputs) do
    repl_input(n, inputs, outputs)
    |> repl_args([arg | args], n + 1, inputs, outputs)
  end

  defp repl_args(inputs, outputs) do
    repl_input(1, inputs, outputs)
    |> repl_args([], 2, inputs, outputs)
  end

  defp functions(module) do
    Venomous.SnakeArgs.from_params(:venomous, :module_functions, [module]) |> Venomous.python!()
  end

  defp modules() do
    Venomous.SnakeArgs.from_params(:venomous, :all_modules, []) |> Venomous.python!()
  end

  defp reload() do
    ["venomous", "reload", "serpent_watcher", "venomous_test"]
    |> Enum.each(&(Venomous.SnakeArgs.from_params(:reload, :reload, [&1]) |> Venomous.python!()))
  end

  defp sanitize_params(params) do
    params
    |> Enum.map_join("\n\n\t", fn param ->
      param
      |> Map.to_list()
      |> Enum.reverse()
      |> Enum.map_join("\n\t", &Enum.join(Tuple.to_list(&1), ": "))
    end)
  end

  defp get_function(module) do
    func =
      IO.gets("Python REPL (function): ") |> String.trim_trailing("\n")

    if func == "" do
      IO.puts("Available functions:\n")

      module
      |> to_string
      |> functions()
      |> Map.to_list()
      |> Enum.each(fn {func, params} ->
        IO.puts("#{func}()\n\t#{sanitize_params(params)}")
      end)

      get_function(module)
    else
      func |> String.to_atom()
    end
  end

  defp get_module() do
    mod =
      IO.gets("Python REPL (module/outputs/pop/r (repeat)/exit): ") |> String.trim_trailing("\n")

    if mod == "" do
      modules() |> Enum.join(", ") |> IO.puts()
      get_module()
    else
      mod
    end
  end

  def repl(opts \\ []) do
    inputs = Keyword.get(opts, :inputs, [])
    outputs = Keyword.get(opts, :outputs, [])
    previous_args = Keyword.get(opts, :previous_args)
    reload()
    mod = get_module()

    case mod do
      "exit" ->
        outputs

      "outputs" ->
        outputs |> dbg()
        repl(inputs: inputs, outputs: outputs)

      "inputs" ->
        inputs |> dbg()
        repl(inputs: inputs, outputs: outputs)

      "pop" ->
        [_ | outputs] = outputs
        repl(inputs: inputs, outputs: outputs)

      "r" ->
        outputs =
          if previous_args != nil do
            [_ | previous] = outputs
            [Venomous.python!(previous_args) |> dbg | previous]
          else
            outputs
          end

        repl(inputs: inputs, outputs: outputs, previous_args: previous_args)

      mod ->
        func = get_function(mod)
        args = repl_args(inputs, outputs)
        params = Venomous.SnakeArgs.from_params(String.to_atom(mod), func, args)

        outputs = [
          Venomous.python!(params) |> dbg
          | outputs
        ]

        repl(inputs: inputs, outputs: outputs, previous_args: params)
    end
  end
end

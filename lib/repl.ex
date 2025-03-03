defmodule VenomousREPL do
  @moduledoc """
    # Venomous REPL 
    List of keywords:
            - Enter leading "%" in case of colliding keyword/module names
            - RETURN: Brings up all visible modules/functions
            - '(i)nputs': views inputs list
            - '(o)utputs': views outputs list
            - '(h)elp': views this
            - '(r)epeat': repeats last function with the same arguments
            - '(e)dit': edit arguments
            - 'pop': removes first item from the outputs
            - 'exit': exits the REPL

  """
  @compile if Mix.env() in [:test, :dev], do: :export_all
  @options ["exit", "o", "i", "h", "pop", "e", "r", "h"]
  # credo:disable-for-this-file Credo.Check.Warning.Dbg
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity 
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  defp repl_input(n, inputs, outputs) do
    IO.gets("[Python REPL] Enter (arg #{n}): ")
    |> String.trim_trailing("\n")
    |> Code.eval_string(Keyword.merge(inputs, outputs: outputs))
    |> elem(0)
  end

  defp repl_args(nil, args, _n, _inputs, _outputs), do: args

  defp repl_args(arg, args, n, inputs, outputs) do
    repl_input(n, inputs, outputs)
    |> repl_args(args ++ [arg], n + 1, inputs, outputs)
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

  defp sanitize_functions(functions) do
    functions
    |> Map.to_list()
    |> Enum.each(fn {func, params} ->
      IO.puts("#{func}()\n\t#{sanitize_params(params)}")
    end)
  end

  defp get_function(functions, "", module) do
    IO.puts("Available functions:\n")
    sanitize_functions(functions)
    get_function(functions, module)
  end

  defp get_function(functions, <<"%", func::binary>>, _module),
    do: {functions[func], String.to_atom(func)}

  defp get_function(functions, func, module) do
    if functions |> Map.keys() |> Enum.member?(func) do
      {functions[func], String.to_atom(func)}
    else
      IO.puts("#{func} wasn't found. Enter leading '%' to force.")
      get_function(functions, module)
    end
  end

  defp get_function(functions, module) do
    func =
      IO.gets("[Python REPL] Enter function name: ") |> String.trim_trailing("\n")

    get_function(functions, func, module)
  end

  defp get_function(module) do
    module
    |> to_string
    |> functions()
    |> get_function(module)
  end

  defp get_module(modules \\ modules()) do
    mod =
      IO.gets("[Python REPL] Enter module name or (h)elp: ") |> String.trim_trailing("\n")

    case mod do
      "" ->
        modules |> Enum.join(", ") |> IO.puts()
        get_module(modules)

      mod when mod in @options ->
        mod

      <<"%", mod::binary>> ->
        mod

      mod ->
        if Enum.member?(modules, mod) == false do
          IO.puts("#{mod} wasn't found. Enter leading '%' to force.")
          get_module(modules)
        else
          mod
        end
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

      "o" ->
        outputs |> dbg()
        repl(inputs: inputs, outputs: outputs, previous_args: previous_args)

      "i" ->
        inputs |> dbg()
        repl(inputs: inputs, outputs: outputs, previous_args: previous_args)

      "pop" ->
        outputs =
          case outputs do
            [] -> outputs
            [_ | outputs] -> outputs
          end

        dbg(outputs)
        repl(inputs: inputs, outputs: outputs, previous_args: previous_args)

      "e" ->
        case previous_args do
          %Venomous.SnakeArgs{args: args} = previous_args ->
            old_args =
              args
              |> Enum.with_index()
              |> Enum.reduce(Keyword.new(), fn {val, idx}, acc ->
                Keyword.merge(["e#{idx + 1}": val], acc)
              end)

            dbg(old_args)
            args = repl_args(Keyword.merge(old_args, inputs), outputs)
            previous_args = %Venomous.SnakeArgs{previous_args | args: args}

            outputs = [
              Venomous.python!(previous_args) |> dbg
              | outputs
            ]

            repl(inputs: inputs, outputs: outputs, previous_args: previous_args)

          _ ->
            repl(inputs: inputs, outputs: outputs, previous_args: previous_args)
        end

      "r" ->
        outputs =
          if previous_args != nil do
            previous =
              case outputs do
                [] -> outputs
                [_ | previous] -> previous
              end

            [Venomous.python!(previous_args) |> dbg | previous]
          else
            outputs
          end

        repl(inputs: inputs, outputs: outputs, previous_args: previous_args)

      "h" ->
        IO.puts("""
          List of keywords:
            - Enter leading "%" in case of colliding keyword/module names
            - RETURN: Brings up all visible modules/functions
            - '(i)nputs': views inputs list
            - '(o)utputs': views outputs list
            - '(h)elp': views this
            - '(r)epeat': repeats last function with the same arguments
            - '(e)dit': edit arguments
            - 'pop': removes first item from the outputs
            - 'exit': exits the REPL
        """)

        repl(inputs: inputs, outputs: outputs, previous_args: previous_args)

      mod ->
        {function_signature, func} = get_function(mod)
        dbg(function_signature)
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

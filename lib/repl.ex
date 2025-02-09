defmodule VenomousREPL do
  @moduledoc """
    Simple REPL for Venomous
  """
  @compile if Mix.env() in [:test, :dev], do: :export_all
  # credo:disable-for-this-file Credo.Check.Warning.Dbg

  defp repl_input(n, inputs, outputs) do
    IO.gets("Python REPL (arg #{n}): ")
    |> String.trim_trailing("\n")
    |> Code.eval_string(Keyword.merge(inputs, [outputs: outputs]))
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
  inputs      = Keyword.get(opts, :inputs, [])
  outputs     = Keyword.get(opts, :outputs, [])
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
        outputs = if previous_args != nil do
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

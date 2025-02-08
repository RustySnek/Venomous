defmodule VenomousREPL do
  @compile if Mix.env() in [:test, :dev], do: :export_all

  defp repl_input(n, outputs) do
    IO.gets("Python REPL (arg #{n}): ")
    |> String.trim_trailing("\n")
    |> Code.eval_string(outputs: outputs)
    |> elem(0)
  end

  defp repl_args(nil, args, _n, _outputs), do: args

  defp repl_args(arg, args, n, outputs) do
    repl_input(n, outputs)
    |> repl_args([arg | args], n + 1, outputs)
  end

  defp repl_args(outputs) do
    repl_input(1, outputs)
    |> repl_args([], 2, outputs)
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

  def repl(outputs \\ [], previous_args \\ nil) do
    reload()
    mod = get_module()

    case mod do
      "exit" ->
        outputs

      "outputs" ->
        outputs |> inspect() |> IO.puts()
        repl(outputs)

      "pop" ->
        [_ | outputs] = outputs
        repl(outputs)

      "r" ->
        if previous_args != nil do
          [_ | previous] = outputs
          [Venomous.python!(previous_args) |> dbg | previous]
        else
          outputs
        end
        |> repl(previous_args)

      mod ->
        func = get_function(mod)
        args = repl_args(outputs)
        params = Venomous.SnakeArgs.from_params(String.to_atom(mod), func, args)

        [
          Venomous.python!(params) |> dbg
          | outputs
        ]
        |> repl(params)
    end
  end
end

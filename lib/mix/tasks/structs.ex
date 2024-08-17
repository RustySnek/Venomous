defmodule Mix.Tasks.Venomous.Structs do
  @moduledoc false
  use Mix.Task

  @default_imports """
  from typing import Any
  from dataclasses import dataclass
  from venomous import VenomousTrait
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [] ->
        Mix.raise("""
        Simple utility to create python elixir compatible classes.

        VenomousTrait class provides 2 functions: 
          - def from_dict(cls, erl_map: Map | Dict) -> cls
            # converts Erlport Map or a Dict into the object class
          - def into_erl(self) -> Map
            # returns erlang compatible struct from self

           
        To create basic python classes based on structs: 
            - mix venomous.structs MyModule.MyStruct MyModule.MoreStructs ...

        To create extended classes depending on existing python class: 
            - mix venomous.structs MyModule.MyStruct:PythonClassName ...

        To create for all available structs inside an application
            - mix venomous.structs all my_application
            
        """)

      ["all", module] ->
        all_from_module(module)

      modules ->
        both_way_modules(modules) |> IO.puts()
    end
  end

  defp sanitize_modulename(input) do
    input
    |> String.replace_prefix("Elixir.", "")
    |> String.replace(".", "")
    |> Kernel.<>("Struct")
  end

  defp generate_inherited_class(name, class_name) do
    """
    @dataclass
    class #{class_name}Struct(VenomousTrait, #{class_name}):
        __struct__: str = "#{name}"
        
        def __post_init__(self) -> None:
            #{class_name}.__init__(self)

    """
  end

  defp generate_python_class({name, args}) do
    remove_prefix = sanitize_modulename(name)

    attributes =
      args
      |> Enum.map(fn attr_atom ->
        attr_atom |> to_string |> Kernel.<>(": Any = None")
      end)

    """
    @dataclass
    class #{remove_prefix}(VenomousTrait):
        #{Enum.join(attributes, "\n    ")}
        __struct__: str = "#{name}"
    """
  end

  defp prefix_elixir_to_module(mod) do
    if String.starts_with?(mod, "Elixir.") do
      mod
    else
      "Elixir." <> mod
    end
  end

  defp mod_into_struct_keys(module) do
    module = Module.concat([module])
    Code.ensure_loaded(module)

    if module |> Kernel.function_exported?(:__struct__, 0) do
      struct(module) |> Map.pop(:__struct__) |> elem(1) |> Map.keys()
    else
      Mix.raise("#{module} isn't a struct")
    end
  end

  defp create_encoding(class) do
    """
        if isinstance(value, #{class}):
            return #{class}Struct.from_dict(value.__dict__).into_erl()
    """
  end

  defp create_class_and_keypair([module, class], {classes, keypairs, encoder}) do
    {
      classes <> generate_inherited_class(module, class) <> "\n",
      keypairs <> "Atom(b\"#{module}\"): #{class}Struct,\n    ",
      encoder <> create_encoding(class)
    }
  end

  defp create_class_and_keypair([module], {classes, keypairs, encoder}) do
    {
      classes <> generate_python_class({to_string(module), mod_into_struct_keys(module)}) <> "\n",
      keypairs <> "Atom(b\"#{module}\"): #{sanitize_modulename(module)},\n    ",
      encoder <>
        create_encoding(sanitize_modulename(module) |> String.replace_suffix("Struct", ""))
    }
  end

  defp both_way_modules(modules) do
    encoder = """
        if isinstance(value, dict):
            return {key: encoder(value) for key, value in value.items()}
        if isinstance(value, (list, tuple, set)):
            return type(value)(encoder(item) for item in value)

    """

    {classes, keypairs, encoders} =
      modules
      |> Enum.reduce({"", "", encoder}, fn module, classes_and_keypair_and_encoder ->
        module = prefix_elixir_to_module(module)

        String.split(module, ":") |> create_class_and_keypair(classes_and_keypair_and_encoder)
      end)

    """
    #{@default_imports}
    #{classes}venomous_structs = {
        #{keypairs}}

    def encoder(value: Any) -> Any:
    #{encoders}
        return value

    def decoder(value: Any) -> Any:
        if isinstance(value, (Map, dict)):
            if struct := value.get(Atom(b"__struct__")):
                return venomous_structs[struct].from_dict(value, venomous_structs)
            return {decoder(key): decoder(val) for key, val in value.items()}
        elif isinstance(value, (set, list, tuple)):
            return type(value)(decoder(_val) for _val in value)

        return value
    """
  end

  defp all_from_module(module) do
    modules =
      case String.to_existing_atom(module) |> :application.get_all_key() do
        {:ok, mod} ->
          Keyword.get(mod, :modules)

        :undefined ->
          Mix.raise("Couldn't find the module. Make sure you aren't providing a sub-module.")
      end

    Enum.each(modules, &Code.ensure_loaded(&1))
    structs = Enum.filter(modules, &Kernel.function_exported?(&1, :__struct__, 0))

    struct_dic =
      Enum.reduce(structs, "\nvenomous_structs = {\n    ", fn struct_mod, acc ->
        name = to_string(struct_mod)
        acc <> "Atom(b\"#{name}\"): #{sanitize_modulename(name)},\n    "
      end)
      |> Kernel.<>("}")

    struct_classes =
      Enum.map(structs, fn struct_mod ->
        {to_string(struct_mod),
         struct_mod |> struct() |> Map.pop(:__struct__) |> elem(1) |> Map.keys()}
      end)
      |> Enum.map(&generate_python_class/1)

    """
    #{@default_imports}
    #{Enum.join(struct_classes, "\n")}#{struct_dic}

    def encoder(value: Any) -> Any:
        if isinstance(value, VenomousTrait):
           return value.into_erl()
        return value

    def decoder(value: Any) -> Any:
        if isinstance(value, Map):
            if struct := value.get(Atom(b"__struct__")):
                return venomous_structs[struct].from_dict(value)
        return value

    """
    |> IO.puts()
  end
end

defmodule Venomous.SnakeOpts do
  @moduledoc """
    Module for converting Venomous python config keywords to erlport ones
  """
  @available_opts [
    :module_paths,
    :cd,
    :compressed,
    :envvars,
    :packet_bytes,
    :python_executable
  ]

  defp construct_python_opts({:module_paths, paths}) when is_list(paths) do
    {:python_path, Enum.map(paths, &to_charlist(&1))}
  end

  defp construct_python_opts({:module_paths, path}) when is_binary(path) do
    {:python_path, to_charlist(path)}
  end

  defp construct_python_opts({:envvars, vars}) when is_list(vars) do
    {:env, Enum.map(vars, fn {key, val} -> {to_charlist(key), to_charlist(val)} end)}
  end

  defp construct_python_opts({:python_executable, path}) when is_binary(path) do
    {:python, to_charlist(path)}
  end

  defp construct_python_opts({:packet_bytes, bytes}) when is_integer(bytes) do
    {:packet, bytes}
  end

  defp construct_python_opts(keyword), do: keyword

  def to_erlport_opts(opts) do
    opts |> Keyword.take(@available_opts) |> Keyword.new(&construct_python_opts(&1))
  end
end

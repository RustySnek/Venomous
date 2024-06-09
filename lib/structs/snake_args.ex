defmodule Venomous.SnakeArgs do
  @moduledoc """
  A module to handle arguments for a Python function call.

  This module defines a struct for storing the module name, function name,
  and the list of arguments that can be used to call a Python function.
  """
  defstruct [
    :module,
    :func,
    :args
  ]

  @type t :: %__MODULE__{
          module: atom(),
          func: atom(),
          args: list(any())
        }
  @spec from_params(atom(), atom(), list(any())) :: %__MODULE__{}
  @doc """
  Builds SnakeArgs struct from params
  ## Parameters
    - module atom() of python module ex. :builtins
    - function atom() of function from given module ex. :sum
    - args list(any()) list of arguments for function ex. [ [1,2,3,4,5] ]
  ## Returns 
    %SnakeArgs{}
  """
  def from_params(module, func, args) do
    %__MODULE__{
      module: module,
      func: func,
      args: args
    }
  end
end

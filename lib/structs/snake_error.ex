defmodule Venomous.SnakeError do
  @moduledoc """
  A module to handle errors raised during Python function calls.

  This module defines a struct for storing exception information,
  including the exception itself, the error message, and the backtrace.
  """

  @type t :: %__MODULE__{
          exception: String.t(),
          error: String.t(),
          backtrace: String.t()
        }
  defstruct [
    :exception,
    :error,
    :backtrace
  ]
end

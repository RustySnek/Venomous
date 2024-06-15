defmodule Venomous.PetSnakeSupervisor do
  @moduledoc """
  DynamicSupervisor for named `Venomous.SnakeWorker`
  The maximum cap of `Venomous.SnakeWorker` is defined with :max_children option
  """
  alias Venomous.SnakeWorker
  use DynamicSupervisor

  def start_link(opts \\ [strategy: :one_for_one, max_children: 10]) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    DynamicSupervisor.init(opts)
  end

  @doc """
  Deploys a named snake with its own specified encoder and options 
  """
  def deploy_snake_pet(opts \\ []) do
    spec = {SnakeWorker, opts}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end

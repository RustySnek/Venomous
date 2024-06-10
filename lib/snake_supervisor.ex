defmodule Venomous.SnakeSupervisor do
  @moduledoc """
  DynamicSupervisor for Snakes
  The maximum cap of `Venomous.SnakeWorker` is defined with :max_children option
  > #### Warning {: .warning}
  >
  > The maximum amount of python processes is capped at your systems maximum number of open file-descriptors
  > `ulimit -n` to check your limit
  """
  alias Venomous.SnakeWorker
  use DynamicSupervisor

  def start_link(opts \\ [strategy: :one_for_one, max_children: 50]) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    DynamicSupervisor.init(opts)
  end

  @doc """
  Deploys snake with given opts Map containing :erlport encoder/decoder module, func and args
  """
  def deploy_snake_worker(opts \\ %{}) do
    spec = {SnakeWorker, opts}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end

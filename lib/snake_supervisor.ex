defmodule Venomous.SnakeSupervisor do
  @moduledoc """
  DynamicSupervisor for Snakes
  """
  alias Venomous.SnakeWorker
  use DynamicSupervisor

  def start_link(opts \\ [strategy: :one_for_one]) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    DynamicSupervisor.init(opts)
  end

  def deploy_snake_worker do
    spec = {SnakeWorker, []}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end

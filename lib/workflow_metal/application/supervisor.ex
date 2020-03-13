defmodule WorkflowMetal.Application.Supervisor do
  @moduledoc false

  use DynamicSupervisor
  import Supervisor.Spec

  @doc """
  Start the application supervisor.
  """
  @spec start_link(atom(), atom(), keyword()) :: {:ok, pid()}
  def start_link(application, name, opts) do
    Supervisor.start_link(
      __MODULE__,
      {application, name, opts},
      name: name
    )
  end

  @impl true
  def init({_application, name, _opts} = args) do
    registry_name = Module.concat(name, Registry)

    children = [
      {Registry, keys: :unique, name: registry_name},
      supervisor(WorkflowMetal.Application.WorkflowsSupervisor, [args])
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

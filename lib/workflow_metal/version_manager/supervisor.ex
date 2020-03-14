defmodule WorkflowMetal.VersionManager.Supervisor do
  @moduledoc """
  VersionManager is a `DynamicSupervisor` used to manage versions of a workflow.
  """

  use DynamicSupervisor

  @doc """
  Start the workflows supervisor to supervise all workflows.
  """
  @spec start_link({{module(), atom(), keyword()}, keyword()}) :: Supervisor.on_start()
  def start_link({config, args}) do
    supervisor_name = supervisor_name(config, args)

    DynamicSupervisor.start_link(
      __MODULE__,
      {config, args},
      name: supervisor_name
    )
  end

  @impl true
  def init({config, args}) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [config, args])
  end

  defp supervisor_name({application, name, _opts}, opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    registration = Module.concat(name, Registry)

    {:via, Registry, {registration, {application, __MODULE__, workflow_id}}}
  end
end

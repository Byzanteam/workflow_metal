defmodule WorkflowMetal.VersionManager.Supervisor do
  @moduledoc """
  VersionManager is a `DynamicSupervisor` used to manage versions of a workflow.
  """

  use DynamicSupervisor

  @type workflow_arg :: WorkflowMetal.Workflow.Supervisor.workflow_arg()

  @doc """
  Start the workflows supervisor to supervise all workflows.
  """
  @spec start_link(workflow_arg) :: Supervisor.on_start()
  def start_link({application, workflow_params} = workflow_arg) do
    DynamicSupervisor.start_link(
      __MODULE__,
      workflow_arg,
      name: via_name(application, workflow_params)
    )
  end

  @impl true
  def init(workflow_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [workflow_arg])
  end

  defp via_name(application, workflow_params) do
    workflow_id = Map.fetch!(workflow_params, :workflow_id)

    WorkflowMetal.Registration.via_tuple(application, {__MODULE__, workflow_id})
  end
end

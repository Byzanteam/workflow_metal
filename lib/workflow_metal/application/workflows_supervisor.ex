defmodule WorkflowMetal.Application.WorkflowsSupervisor do
  @moduledoc """
  Supervise all workflows.
  """

  use DynamicSupervisor

  @type application :: WorkflowMetal.Application.t()
  @type workflow_params :: WorkflowMetal.Workflow.Supervisor.workflow_params()

  @doc """
  Start the workflows supervisor to supervise all workflows.
  """
  @spec start_link(application) :: Supervisor.on_start()
  def start_link(application) do
    workflows_supervisor = supervisor_name(application)

    DynamicSupervisor.start_link(
      __MODULE__,
      application,
      name: workflows_supervisor
    )
  end

  @impl true
  def init(application) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [application])
  end

  @doc """
  Start a workflow supervisor.
  """
  @spec create_workflow(application, workflow_params) :: DynamicSupervisor.on_start_child()
  def create_workflow(application, workflow_params) do
    workflow_id = Keyword.fetch!(workflow_params, :workflow_id)
    workflows_supervisor = supervisor_name(application)

    child_spec = {WorkflowMetal.Workflow.Supervisor, [workflow_id: workflow_id]}

    DynamicSupervisor.start_child(workflows_supervisor, child_spec)
  end

  defp supervisor_name(application) do
    Module.concat(application, WorkflowsSupervisor)
  end
end

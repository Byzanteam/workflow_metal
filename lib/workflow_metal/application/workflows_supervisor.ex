defmodule WorkflowMetal.Application.WorkflowsSupervisor do
  @moduledoc """
  Supervise all workflows.
  """

  use DynamicSupervisor

  alias WorkflowMetal.Workflow.Schemas

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
    {:ok, workflow} = Schemas.Workflow.new(workflow_params)

    workflow_id = Keyword.fetch!(workflow_params, :id)
    workflow_version = Keyword.fetch!(workflow_params, :version)

    workflows_supervisor = supervisor_name(application)
    storage_name = storage_name(application, workflow_id)

    storage = {WorkflowMetal.Storage, [name: storage_name, init: {workflow_version, workflow}]}

    workflow_supervisor =
      {WorkflowMetal.Workflow.Supervisor, [workflow_id: workflow_id, storage: storage_name]}

    DynamicSupervisor.start_child(workflows_supervisor, storage)
    DynamicSupervisor.start_child(workflows_supervisor, workflow_supervisor)
  end

  defp supervisor_name(application) do
    Module.concat(application, WorkflowsSupervisor)
  end

  defp storage_name(application, workflow_id) do
    WorkflowMetal.Storage.via_name(application, workflow_id)
  end
end

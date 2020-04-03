defmodule WorkflowMetal.Application.WorkflowsSupervisor do
  @moduledoc """
  Supervise all workflows.
  """

  use DynamicSupervisor

  alias WorkflowMetal.Registration
  alias WorkflowMetal.Storage.Schema

  @type application :: WorkflowMetal.Application.t()
  @type workflow_params :: WorkflowMetal.Storage.Schema.Workflow.Params.t()
  @type workflow_schema :: WorkflowMetal.Storage.Schema.Workflow.t()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()

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
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: [application]
    )
  end

  @doc """
  Create a workflow.
  """
  @spec create_workflow(application, workflow_params) ::
          WorkflowMetal.Storage.Adapter.on_create_workflow()
  def create_workflow(application, %Schema.Workflow.Params{} = workflow_params) do
    # TODO: do validation
    WorkflowMetal.Storage.create_workflow(application, workflow_params)
  end

  @doc """
  Retrive the workflow from the storage and open it(start `Supervisor` and its children).
  """
  @spec open_workflow(application, workflow_id) ::
          WorkflowMetal.Registration.Adapter.on_start_child()
          | {:error, :workflow_not_found}
  def open_workflow(application, workflow_id) do
    with(
      {:ok, workflow_schema} <- WorkflowMetal.Storage.fetch_workflow(application, workflow_id)
    ) do
      workflows_supervisor = supervisor_name(application)
      workflow_supervisor = {WorkflowMetal.Workflow.Supervisor, workflow_id: workflow_schema.id}

      Registration.start_child(
        application,
        WorkflowMetal.Workflow.Supervisor.name(workflow_schema.id),
        workflows_supervisor,
        workflow_supervisor
      )
    end
  end

  defp supervisor_name(application) do
    Module.concat(application, WorkflowsSupervisor)
  end
end

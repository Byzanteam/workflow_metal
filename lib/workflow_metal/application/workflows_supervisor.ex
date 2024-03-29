defmodule WorkflowMetal.Application.WorkflowsSupervisor do
  @moduledoc """
  Supervise all workflows.
  """

  use DynamicSupervisor

  alias WorkflowMetal.Registration

  @type application :: WorkflowMetal.Application.t()
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
  Retrieve the workflow from the storage and open it(start `Supervisor` and its children).
  """
  @spec open_workflow(application, workflow_id) ::
          WorkflowMetal.Registration.Adapter.on_start_child()
          | {:error, :workflow_not_found}
  def open_workflow(application, workflow_id) do
    with({:ok, workflow_schema} <- WorkflowMetal.Storage.fetch_workflow(application, workflow_id)) do
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

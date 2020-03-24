defmodule WorkflowMetal.Application.WorkflowsSupervisor do
  @moduledoc """
  Supervise all workflows.
  """

  use DynamicSupervisor

  alias WorkflowMetal.Case.Case
  alias WorkflowMetal.Registration
  alias WorkflowMetal.Workflow.Schema

  @type application :: WorkflowMetal.Application.t()
  @type workflow_id :: WorkflowMetal.Workflow.Workflow.workflow_id()
  @type workflow_params :: WorkflowMetal.Workflow.Supervisor.workflow_params()
  @type case_params :: WorkflowMetal.Case.Supervisor.case_params()

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
  Retrive the workflow from the storage and open it(start `Supervisor` and its children).
  """
  @spec open_workflow(application, workflow_id) ::
          Supervisor.on_start() | {:error, :workflow_not_found}
  def open_workflow(application, workflow_id) do
    workflows_supervisor = supervisor_name(application)
    workflow_supervisor = {WorkflowMetal.Workflow.Supervisor, workflow_id: workflow_id}

    case WorkflowMetal.Storage.retrive_workflow(application, workflow_id) do
      {:ok, _} ->
        Registration.start_child(
          application,
          WorkflowMetal.Workflow.Supervisor.name(workflow_id),
          workflows_supervisor,
          workflow_supervisor
        )

      error ->
        error
    end
  end

  defp supervisor_name(application) do
    Module.concat(application, WorkflowsSupervisor)
  end
end

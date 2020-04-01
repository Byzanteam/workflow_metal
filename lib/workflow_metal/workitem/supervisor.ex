defmodule WorkflowMetal.Workitem.Supervisor do
  @moduledoc """
  `DynamicSupervisor` to supervise all workitems of a workflow.
  """

  use DynamicSupervisor

  alias WorkflowMetal.Registration

  @type application :: WorkflowMetal.Application.t()
  @type workflow :: WorkflowMetal.Storage.Schema.Workflow.t()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type transition_id :: WorkflowMetal.Storage.Schema.Transition.id()
  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.t()

  @doc false
  @spec start_link(workflow_identifier) :: Supervisor.on_start()
  def start_link({application, workflow_id} = workflow_identifier) do
    via_name = via_name(application, workflow_id)

    DynamicSupervisor.start_link(__MODULE__, workflow_identifier, name: via_name)
  end

  @doc false
  @spec name(workflow_id) :: term
  def name(workflow_id) do
    {__MODULE__, workflow_id}
  end

  @impl true
  def init({application, workflow}) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: [{application, workflow}]
    )
  end

  @doc """
  Open a workitem(`GenServer').
  """
  @spec open_workitem(application, workflow_id, case_id, transition_id, workitem_id) ::
          Supervisor.on_start()
          | {:error, :workflow_not_found}
          | {:error, :case_not_found}
          | {:error, :workitem_not_found}
  def open_workitem(application, workflow_id, case_id, transition_id, workitem_id) do
    with(
      {:ok, _} <-
        WorkflowMetal.Task.Supervisor.open_task(application, workflow_id, case_id, transition_id)
    ) do
      workitem_supervisor = via_name(application, workflow_id)

      workitem_spec = {
        WorkflowMetal.Workitem.Workitem,
        [
          case_id: case_id,
          transition_id: transition_id,
          workitem_id: workitem_id
        ]
      }

      Registration.start_child(
        application,
        WorkflowMetal.Workitem.Workitem.name({workflow_id, case_id, transition_id, workitem_id}),
        workitem_supervisor,
        workitem_spec
      )
    end
  end

  defp via_name(application, workflow_id) do
    Registration.via_tuple(application, name(workflow_id))
  end
end

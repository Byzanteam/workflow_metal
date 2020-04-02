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
  @type workitem_schema :: WorkflowMetal.Storage.Schema.Workitem.t()

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
  @spec open_workitem(application, workitem_schema) :: Supervisor.on_start()
  def open_workitem(application, workitem) do
    workitem_supervisor = via_name(application, workitem.workflow_id)

    workitem_spec = {
      WorkflowMetal.Workitem.Workitem,
      [workitem: workitem]
    }

    Registration.start_child(
      application,
      WorkflowMetal.Workitem.Workitem.name({
        workitem.workflow_id,
        workitem.case_id,
        workitem.transition_id,
        workitem.workitem_id
      }),
      workitem_supervisor,
      workitem_spec
    )
  end

  defp via_name(application, workflow_id) do
    Registration.via_tuple(application, name(workflow_id))
  end
end

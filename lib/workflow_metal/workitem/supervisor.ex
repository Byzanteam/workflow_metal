defmodule WorkflowMetal.Workitem.Supervisor do
  @moduledoc """
  `DynamicSupervisor` to supervise all workitems of a workflow.
  """

  use DynamicSupervisor

  alias WorkflowMetal.Registration

  @type application :: WorkflowMetal.Application.t()
  @type workflow_identifier :: WorkflowMetal.Workflow.Supervisor.workflow_identifier()

  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()

  @type workitem_id :: WorkflowMetal.Storage.Schema.Workitem.id()

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
  Open a workitem(`:gen_statem').
  """
  @spec open_workitem(application, workitem_id) ::
          WorkflowMetal.Registration.Adapter.on_start_child()
          | {:error, :workitem_not_found}
  def open_workitem(application, workitem_id) do
    with(
      {:ok, workitem_schema} <- WorkflowMetal.Storage.fetch_workitem(application, workitem_id)
    ) do
      workitem_supervisor = via_name(application, workitem_schema.workflow_id)

      workitem_spec = {
        WorkflowMetal.Workitem.Workitem,
        [workitem_schema: workitem_schema]
      }

      Registration.start_child(
        application,
        WorkflowMetal.Workitem.Workitem.name(workitem_schema),
        workitem_supervisor,
        workitem_spec
      )
    end
  end

  defp via_name(application, workflow_id) do
    Registration.via_tuple(application, name(workflow_id))
  end
end

defmodule WorkflowMetal.Workitem.Supervisor do
  @moduledoc """
  `DynamicSupervisor` to supervise all workitems of a workflow.
  """

  use DynamicSupervisor

  alias WorkflowMetal.Registration

  alias WorkflowMetal.Storage.Schema

  @type application :: WorkflowMetal.Application.t()
  @type workflow_identifier :: WorkflowMetal.Workflow.Supervisor.workflow_identifier()

  @type workflow_id :: Schema.Workflow.id()

  @type workitem_id :: Schema.Workitem.id()
  @type workitem_schema :: Schema.Workitem.t()

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
  @spec open_workitem(application, workitem_schema | workitem_id) ::
          WorkflowMetal.Registration.Adapter.on_start_child()
          | {:error, :workitem_not_found}
  def open_workitem(application, %Schema.Workitem{} = workitem_schema) do
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

  def open_workitem(application, workitem_id) do
    with(
      {:ok, workitem_schema} <- WorkflowMetal.Storage.fetch_workitem(application, workitem_id)
    ) do
      open_workitem(application, workitem_schema)
    end
  end

  @doc """
  Abandon a workitem.
  """
  @spec abandon_workitem(application, workitem_id) ::
          :ok
          | {:error, :workitem_not_found}
  def abandon_workitem(application, workitem_id) do
    with(
      {:ok, %Schema.Workitem{state: workitem_state} = workitem_schema}
      when workitem_state in [:created, :started] <-
        WorkflowMetal.Storage.fetch_workitem(application, workitem_id),
      {:ok, workitem_server} <- open_workitem(application, workitem_schema)
    ) do
      WorkflowMetal.Workitem.Workitem.abandon(workitem_server)
    else
      {:ok, %Schema.Workitem{}} -> :ok
      reply -> reply
    end
  end

  defp via_name(application, workflow_id) do
    Registration.via_tuple(application, name(workflow_id))
  end
end

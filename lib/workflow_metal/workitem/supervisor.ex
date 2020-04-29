defmodule WorkflowMetal.Workitem.Supervisor do
  @moduledoc """
  `DynamicSupervisor` to supervise all workitems of a workflow.
  """

  use DynamicSupervisor

  alias WorkflowMetal.Application.WorkflowsSupervisor

  alias WorkflowMetal.Registration

  alias WorkflowMetal.Storage.Schema

  @type application :: WorkflowMetal.Application.t()
  @type workflow_identifier :: WorkflowMetal.Workflow.Supervisor.workflow_identifier()

  @type workflow_id :: Schema.Workflow.id()

  @type workitem_id :: Schema.Workitem.id()
  @type workitem_schema :: Schema.Workitem.t()
  @type workitem_output :: Schema.Workitem.output()

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
    with(
      {:ok, _} <- WorkflowsSupervisor.open_workflow(application, workitem_schema.workflow_id)
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

  def open_workitem(application, workitem_id) do
    with(
      {:ok, workitem_schema} <- WorkflowMetal.Storage.fetch_workitem(application, workitem_id)
    ) do
      open_workitem(application, workitem_schema)
    end
  end

  @doc """
  Lock tokens before a workitem execution.
  """
  @spec lock_tokens(application, workitem_id) ::
          WorkflowMetal.Task.Task.on_lock_tokens()
          | {:error, :workitem_not_found}
          | {:error, :task_not_available}
  def lock_tokens(application, workitem_id) do
    with(
      {:ok, %Schema.Workitem{task_id: task_id}} <-
        WorkflowMetal.Storage.fetch_workitem(application, workitem_id)
    ) do
      WorkflowMetal.Task.Supervisor.lock_tokens(application, task_id)
    end
  end

  @doc """
  Complete a workitem.
  """
  @spec complete_workitem(application, workitem_id, workitem_output) ::
          WorkflowMetal.Workitem.Workitem.on_complete()
          | {:error, :workitem_not_found}
          | {:error, :workitem_not_available}
  def complete_workitem(application, workitem_id, output) do
    with(
      {:ok, %Schema.Workitem{} = workitem_schema} <-
        WorkflowMetal.Storage.fetch_workitem(application, workitem_id),
      {:ok, workitem_server} <- open_workitem(application, workitem_schema)
    ) do
      WorkflowMetal.Workitem.Workitem.complete(workitem_server, output)
    end
  end

  @doc """
  Abandon a workitem.
  """
  @spec abandon_workitem(application, workitem_id) ::
          WorkflowMetal.Workitem.Workitem.on_abandon()
          | {:error, :workitem_not_found}
          | {:error, :workitem_not_available}
  def abandon_workitem(application, workitem_id) do
    with(
      {:ok, %Schema.Workitem{} = workitem_schema} <-
        WorkflowMetal.Storage.fetch_workitem(application, workitem_id),
      {:ok, workitem_server} <- open_workitem(application, workitem_schema)
    ) do
      WorkflowMetal.Workitem.Workitem.abandon(workitem_server)
    end
  end

  defp via_name(application, workflow_id) do
    Registration.via_tuple(application, name(workflow_id))
  end
end

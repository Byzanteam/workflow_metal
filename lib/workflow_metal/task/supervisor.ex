defmodule WorkflowMetal.Task.Supervisor do
  @moduledoc """
  `DynamicSupervisor` to supervise all tasks of a workflow.
  """

  use DynamicSupervisor

  alias WorkflowMetal.Registration

  alias WorkflowMetal.Storage.Schema

  @type application :: WorkflowMetal.Application.t()
  @type workflow_identifier :: WorkflowMetal.Workflow.Supervisor.workflow_identifier()

  @type workflow_id :: Schema.Workflow.id()

  @type task_id :: Schema.Task.id()
  @type task_schema :: Schema.Task.t()
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
  def init({application, workflow_id}) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: [{application, workflow_id}]
    )
  end

  @doc """
  Open a task(`GenServer').
  """
  @spec open_task(application, task_schema | task_id) ::
          WorkflowMetal.Registration.Adapter.on_start_child()
          | {:error, :task_not_found}
  def open_task(application, %Schema.Task{} = task_schema) do
    %{
      workflow_id: workflow_id
    } = task_schema

    task_supervisor = via_name(application, workflow_id)
    task_spec = {WorkflowMetal.Task.Task, [task_schema: task_schema]}

    Registration.start_child(
      application,
      WorkflowMetal.Task.Task.name(task_schema),
      task_supervisor,
      task_spec
    )
  end

  def open_task(application, task_id) do
    with({:ok, task_schema} <- WorkflowMetal.Storage.fetch_task(application, task_id)) do
      open_task(application, task_schema)
    end
  end

  @doc """
  Lock tokens of a task.
  """
  @spec lock_tokens(application, task_id) ::
          WorkflowMetal.Task.Task.on_lock_tokens()
  def lock_tokens(application, task_id) do
    with({:ok, task_server} <- open_task(application, task_id)) do
      WorkflowMetal.Task.Task.lock_tokens(task_server)
    end
  end

  @doc """
  Update workitem state.
  """
  @spec update_workitem(application, task_id, workitem_schema) :: :ok
  def update_workitem(application, task_id, workitem_schema) do
    with(
      {:ok, task_schema} <- WorkflowMetal.Storage.fetch_task(application, task_id),
      task_server_name = WorkflowMetal.Task.Task.name(task_schema),
      task_server when is_pid(task_server) <-
        WorkflowMetal.Registration.whereis_name(application, task_server_name)
    ) do
      WorkflowMetal.Task.Task.update_workitem(
        task_server,
        workitem_schema.workitem_id,
        workitem_schema.workitem_state
      )
    else
      {:error, :task_not_found} -> :ok
      :undefined -> :ok
      reply -> reply
    end
  end

  defp via_name(application, workflow_id) do
    Registration.via_tuple(application, name(workflow_id))
  end
end

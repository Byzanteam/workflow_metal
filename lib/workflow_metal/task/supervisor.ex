defmodule WorkflowMetal.Task.Supervisor do
  @moduledoc """
  `DynamicSupervisor` to supervise all tasks of a workflow.
  """

  use DynamicSupervisor

  alias WorkflowMetal.Application.WorkflowsSupervisor
  alias WorkflowMetal.Registration
  alias WorkflowMetal.Storage.Schema

  @type application :: WorkflowMetal.Application.t()
  @type workflow_identifier :: WorkflowMetal.Workflow.Supervisor.workflow_identifier()

  @type workflow_id :: Schema.Workflow.id()

  @type task_id :: Schema.Task.id()
  @type task_schema :: Schema.Task.t()
  @type token_schema :: Schema.Token.t()
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

    with({:ok, _} <- WorkflowsSupervisor.open_workflow(application, workflow_id)) do
      task_supervisor = via_name(application, workflow_id)
      task_spec = {WorkflowMetal.Task.Task, [task_schema: task_schema]}

      Registration.start_child(
        application,
        WorkflowMetal.Task.Task.name(task_schema),
        task_supervisor,
        task_spec
      )
    end
  end

  def open_task(application, task_id) do
    with({:ok, task_schema} <- WorkflowMetal.Storage.fetch_task(application, task_id)) do
      open_task(application, task_schema)
    end
  end

  @doc """
  Abandon the task forcibly.
  """
  @spec force_abandon_task(application, task_id) :: :ok
  def force_abandon_task(application, task_id) do
    case open_task(application, task_id) do
      {:ok, task_server} ->
        WorkflowMetal.Task.Task.force_abandon(task_server)

      _ ->
        :ok
    end
  end

  @doc """
  Pre-execute a task and the locked tokens.
  """
  @spec preexecute(application, task_id) ::
          WorkflowMetal.Task.Task.on_preexecute()
  def preexecute(application, task_id) do
    with({:ok, task_server} <- open_task(application, task_id)) do
      WorkflowMetal.Task.Task.preexecute(task_server)
    end
  end

  @doc """
  Offer tokens to a task.
  """
  @spec offer_tokens(application, task_id, [token_schema]) :: :ok
  def offer_tokens(application, task_id, token_schemas)
  def offer_tokens(_application, _task_id, []), do: :ok

  def offer_tokens(application, task_id, token_schemas) do
    with({:ok, task_server} <- open_task(application, task_id)) do
      WorkflowMetal.Task.Task.receive_tokens(task_server, token_schemas)
    end
  end

  @doc """
  Withdraw tokens from a task.
  """
  @spec withdraw_tokens(application, task_id, [token_schema]) :: :ok
  def withdraw_tokens(_application, _task_id, []), do: :ok

  def withdraw_tokens(application, task_id, token_schemas) do
    case whereis_child(application, task_id) do
      :undefined -> :ok
      task_server -> WorkflowMetal.Task.Task.discard_tokens(task_server, token_schemas)
    end
  end

  @doc """
  Update workitem state.
  """
  @spec update_workitem(application, task_id, workitem_schema) :: :ok
  def update_workitem(application, task_id, workitem_schema) do
    with(
      {:ok, task_schema} <- WorkflowMetal.Storage.fetch_task(application, task_id),
      task_server when task_server !== :undefined <- whereis_child(application, task_schema)
    ) do
      WorkflowMetal.Task.Task.update_workitem(
        task_server,
        workitem_schema.id,
        workitem_schema.state
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

  defp whereis_child(application, %Schema.Task{} = task) do
    WorkflowMetal.Registration.whereis_name(
      application,
      WorkflowMetal.Task.Task.name(task)
    )
  end

  defp whereis_child(application, task_id) do
    case WorkflowMetal.Storage.fetch_task(application, task_id) do
      {:ok, task_schema} ->
        whereis_child(application, task_schema)

      _ ->
        :undefined
    end
  end
end

defmodule WorkflowMetal.Task.Supervisor do
  @moduledoc """
  `DynamicSupervisor` to supervise all tasks of a workflow.
  """

  use DynamicSupervisor

  alias WorkflowMetal.Registration

  @type application :: WorkflowMetal.Application.t()
  @type workflow :: WorkflowMetal.Storage.Schema.Workflow.t()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()
  @type task_id :: WorkflowMetal.Storage.Schema.Task.id()

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
  Open a task(`GenServer').
  """
  @spec open_task(application, task_id) ::
          Supervisor.on_start() | {:error, :case_not_found} | {:error, :task_not_found}
  def open_task(application, task_id) do
    with(
      {:ok, task_schema} <- WorkflowMetal.Storage.fetch_task(application, task_id),
      %{
        workflow_id: workflow_id,
        case_id: case_id,
        transition_id: transition_id
      } = task_schema,
      {:ok, _} <- WorkflowMetal.Case.Supervisor.open_case(application, case_id)
    ) do
      task_supervisor = via_name(application, workflow_id)
      task_spec = {WorkflowMetal.Task.Task, [task: task_schema]}

      Registration.start_child(
        application,
        WorkflowMetal.Task.Task.name({workflow_id, case_id, transition_id}),
        task_supervisor,
        task_spec
      )
    end
  end

  defp via_name(application, workflow_id) do
    Registration.via_tuple(application, name(workflow_id))
  end
end

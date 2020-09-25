defmodule WorkflowMetal.Case.Supervisor do
  @moduledoc """
  `DynamicSupervisor` to supervise all case of a workflow.
  """

  use DynamicSupervisor

  alias WorkflowMetal.Application.WorkflowsSupervisor
  alias WorkflowMetal.Registration
  alias WorkflowMetal.Storage.Schema

  @type application :: WorkflowMetal.Application.t()
  @type workflow_identifier :: WorkflowMetal.Workflow.Supervisor.workflow_identifier()

  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()

  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type case_params :: WorkflowMetal.Storage.Schema.Case.Params.t()

  @type task_id :: WorkflowMetal.Storage.Schema.Task.id()

  @type token_id :: WorkflowMetal.Storage.Schema.Token.id()
  @type token_schema :: WorkflowMetal.Storage.Schema.Token.t()
  @type token_params :: WorkflowMetal.Storage.Schema.Token.Params.t()

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
  Create a case.
  """
  @spec create_case(application, case_params) ::
          Supervisor.on_start() | {:error, :workflow_not_found} | {:error, :case_not_found}
  def create_case(application, %Schema.Case.Params{} = case_params) do
    {:ok, case_schema} = WorkflowMetal.Storage.create_case(application, case_params)
    open_case(application, case_schema.id)
  end

  @doc """
  Open a case(`GenServer').
  """
  @spec open_case(application, case_id) ::
          WorkflowMetal.Registration.Adapter.on_start_child()
          | {:error, :case_not_found}
          | {:error, :workflow_not_found}
  def open_case(application, case_id) do
    with(
      {:ok, case_schema} <- WorkflowMetal.Storage.fetch_case(application, case_id),
      %{workflow_id: workflow_id} = case_schema,
      {:ok, _} <- WorkflowsSupervisor.open_workflow(application, workflow_id)
    ) do
      case_supervisor = via_name(application, workflow_id)
      case_spec = {WorkflowMetal.Case.Case, [case_schema: case_schema]}

      Registration.start_child(
        application,
        WorkflowMetal.Case.Case.name(case_schema),
        case_supervisor,
        case_spec
      )
    end
  end

  @doc """
  Terminate a case(`GenServer').
  """
  @spec terminate_case(application, case_id) ::
          :ok
          | {:error, :case_not_found}
          | {:error, :workflow_not_found}
  def terminate_case(application, case_id) do
    with({:ok, case_server} <- open_case(application, case_id)) do
      WorkflowMetal.Case.Case.terminate(case_server)
    end
  end

  @doc """
  Request `:free` and `:locked`(locked by the task) tokens which should offer to the task.

  This usually happens after a task restore from the storage.
  """
  @spec request_tokens(application, case_id, task_id) ::
          {:ok, [token_schema]}
          | {:error, :case_not_found}
  def request_tokens(application, case_id, task_id) do
    with({:ok, case_server} <- open_case(application, case_id)) do
      WorkflowMetal.Case.Case.offer_tokens_to_task(case_server, task_id)
    end
  end

  @doc """
  Lock tokens for the task.

  This usually happens before a workitem execution.
  """
  @spec lock_tokens(application, case_id, nonempty_list(token_id), task_id) ::
          {:ok, nonempty_list(token_schema)}
          | {:error, :tokens_not_available}
          | {:error, :case_not_found}
  def lock_tokens(application, case_id, token_ids, task_id) do
    with({:ok, case_server} <- open_case(application, case_id)) do
      WorkflowMetal.Case.Case.lock_tokens(case_server, token_ids, task_id)
    end
  end

  @doc """
  Free tokens that locked by the task.

  This usually happens afetr a task has been abandoned.
  """
  @spec unlock_tokens(application, case_id, task_id) ::
          :ok
          | {:error, :case_not_available}
          | {:error, :case_not_found}
  def unlock_tokens(application, case_id, task_id) do
    with({:ok, case_server} <- open_case(application, case_id)) do
      WorkflowMetal.Case.Case.free_tokens_from_task(case_server, task_id)
    end
  end

  @doc """
  consume tokens that locked by the task

  This usually happens after a task execution.
  """
  @spec consume_tokens(application, case_id, task_id) ::
          {:ok, nonempty_list(token_schema)}
          | {:error, :tokens_not_available}
          | {:error, :case_not_found}
  def consume_tokens(application, case_id, task_id) do
    with({:ok, case_server} <- open_case(application, case_id)) do
      WorkflowMetal.Case.Case.consume_tokens(case_server, task_id)
    end
  end

  @doc """
  Issue tokens after a task completion.
  """
  @spec issue_tokens(application, case_id, nonempty_list(token_params)) ::
          {:ok, nonempty_list(token_schema)}
          | {:error, :case_not_found}
  def issue_tokens(application, case_id, token_params_list) do
    with({:ok, case_server} <- open_case(application, case_id)) do
      WorkflowMetal.Case.Case.issue_tokens(case_server, token_params_list)
    end
  end

  defp via_name(application, workflow_id) do
    Registration.via_tuple(application, name(workflow_id))
  end
end

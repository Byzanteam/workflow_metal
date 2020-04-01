defmodule WorkflowMetal.Case.Supervisor do
  @moduledoc """
  `DynamicSupervisor` to supervise all case of a workflow.
  """

  use DynamicSupervisor

  alias WorkflowMetal.Registration
  alias WorkflowMetal.Storage.Schema

  @type application :: WorkflowMetal.Application.t()
  @type workflow :: WorkflowMetal.Storage.Schema.Workflow.t()
  @type workflow_id :: WorkflowMetal.Storage.Schema.Workflow.id()
  @type workflow_identifier :: WorkflowMetal.Workflow.Workflow.workflow_identifier()
  @type case_id :: WorkflowMetal.Storage.Schema.Case.id()
  @type case_schema :: WorkflowMetal.Storage.Schema.Case.t()

  alias WorkflowMetal.Application.WorkflowsSupervisor

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
  Create a case.
  """
  @spec create_case(application, case_schema) ::
          Supervisor.on_start() | {:error, :workflow_not_found} | {:error, :case_not_found}
  def create_case(application, %Schema.Case{} = case_schema) do
    :ok = WorkflowMetal.Storage.create_case(application, case_schema)
    open_case(application, case_schema.workflow_id, case_schema.id)
  end

  @doc """
  Open a case(`GenServer').
  """
  @spec open_case(application, workflow_id, case_id) ::
          Supervisor.on_start() | {:error, :workflow_not_found} | {:error, :case_not_found}
  def open_case(application, workflow_id, case_id) do
    with(
      {:ok, _} <- WorkflowsSupervisor.open_workflow(application, workflow_id),
      # TODO: 提供 case_exists?
      {:ok, _} <- WorkflowMetal.Storage.fetch_case(application, workflow_id, case_id)
    ) do
      case_supervisor = via_name(application, workflow_id)
      case_spec = {WorkflowMetal.Case.Case, [case_id: case_id]}

      Registration.start_child(
        application,
        WorkflowMetal.Case.Case.name({workflow_id, case_id}),
        case_supervisor,
        case_spec
      )
    else
      error ->
        error
    end
  end

  defp via_name(application, workflow_id) do
    Registration.via_tuple(application, name(workflow_id))
  end
end

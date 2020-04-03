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
  @type case_params :: WorkflowMetal.Storage.Schema.Case.Params.t()

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
      %{id: case_id, workflow_id: workflow_id} = case_schema,
      {:ok, _} <- WorkflowsSupervisor.open_workflow(application, workflow_id)
    ) do
      case_supervisor = via_name(application, workflow_id)
      case_spec = {WorkflowMetal.Case.Case, [case_schema: case_schema]}

      Registration.start_child(
        application,
        WorkflowMetal.Case.Case.name({workflow_id, case_id}),
        case_supervisor,
        case_spec
      )
    end
  end

  defp via_name(application, workflow_id) do
    Registration.via_tuple(application, name(workflow_id))
  end
end

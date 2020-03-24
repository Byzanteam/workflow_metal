defmodule WorkflowMetal.Workflow.Workflow do
  @moduledoc """
  Workflow is a `GenServer` process used to provide access to a workflow.
  """

  use GenServer

  defstruct [
    :table
  ]

  @type application :: WorkflowMetal.Application.t()
  @type workflow :: WorkflowMetal.Workflow.Supervisor.workflow()
  @type workflow_arg :: WorkflowMetal.Workflow.Supervisor.workflow_arg()
  @type workflow_address :: nil | {pid, String.t()}
  @type workflow_reference :: WorkflowMetal.Workflow.Supervisor.workflow_reference()

  @doc false
  @spec start_link(workflow_arg) :: GenServer.on_start()
  def start_link({application, workflow}) do
    GenServer.start_link(__MODULE__, [workflow: workflow], name: via_name(application, workflow))
  end

  @doc false
  @spec via_name(application, workflow) :: term()
  def via_name(application, workflow) when is_map(workflow) do
    workflow_id = Map.fetch!(workflow, :id)
    WorkflowMetal.Registration.via_tuple(application, {__MODULE__, workflow_id})
  end

  @doc false
  @spec via_name(application, workflow_reference) :: term()
  def via_name(application, workflow_reference) when is_list(workflow_reference) do
    workflow_id = Keyword.fetch!(workflow_reference, :id)
    WorkflowMetal.Registration.via_tuple(application, {__MODULE__, workflow_id})
  end

  @impl true
  def init(_init_args) do
    table = :ets.new(:storage, [:set, :private])

    {:ok, %__MODULE__{table: table}}
  end
end
